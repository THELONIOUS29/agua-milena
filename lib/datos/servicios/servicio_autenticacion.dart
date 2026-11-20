import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dominio/entidades/rol_usuario.dart';
import 'servicio_criptografia.dart';

class ServicioAutenticacion {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final ServicioCriptografia _cryptoService = ServicioCriptografia();

  static const String _legacyGlobalSalt = 'AguaMilenaSecureS4lt_2026!';
  static const String _hashScheme = 'pbkdf2_sha256';
  static const int _pbkdf2Iterations = 210000;
  static const int _derivedKeyLength = 32;
  static const Duration _sessionMaxAge = Duration(days: 7);

  static const String _encryptedUserKey = 'current_user_enc';
  static const String _encryptedMfaKey = 'mfa_enabled_enc';
  static const String _encryptedSessionTimestampKey = 'session_saved_at_enc';
  static const String _encryptedServerSessionTokenKey =
      'server_session_token_enc';
  static const String _legacyUserKey = 'current_user';
  static const String _legacyMfaKey = 'mfa_enabled';
  static const String _supabaseSessionHeader = 'x-agua-milena-session';

  String hashContrasena(String contrasena) {
    final salt = _randomBytes(16);
    final derived = _derivePassword(contrasena, salt, _pbkdf2Iterations);
    return '$_hashScheme\$$_pbkdf2Iterations\$${base64UrlEncode(salt)}\$${base64UrlEncode(derived)}';
  }

  bool verificarContrasena(String contrasena, String hashAlmacenado) {
    if (hashAlmacenado.startsWith('$_hashScheme\$')) {
      final parts = hashAlmacenado.split(r'$');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations <= 0) return false;
      try {
        final salt = Uint8List.fromList(base64Url.decode(parts[2]));
        final expected = Uint8List.fromList(base64Url.decode(parts[3]));
        final derived = _derivePassword(contrasena, salt, iterations);
        return _constantTimeEquals(derived, expected);
      } catch (_) {
        return false;
      }
    }
    return _legacyHash(contrasena) == hashAlmacenado;
  }

  bool necesitaRehash(String hash) => !hash.startsWith('$_hashScheme\$');

  bool esContrasenaValida(String contrasena) {
    if (contrasena.length < 8) return false;
    if (!contrasena.contains(RegExp(r'[0-9]'))) return false;
    if (!contrasena.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) return false;
    return true;
  }

  Future<bool> puedeUsarBiometria() async {
    if (kIsWeb) return false;
    final canBio = await _localAuth.canCheckBiometrics;
    return canBio || await _localAuth.isDeviceSupported();
  }

  Future<bool> autenticarBiometria() async {
    if (kIsWeb) return false;
    try {
      if (!await puedeUsarBiometria()) return false;
      return await _localAuth.authenticate(
        localizedReason: 'Por favor, autentícate para acceder al sistema',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> guardarSesionUsuario(
    UsuarioApp user, {
    required String sessionToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encUser = await _cryptoService.encryptString(
      jsonEncode(user.aJson()),
    );
    final encMfa = await _cryptoService.encryptString('true');
    final encSavedAt = await _cryptoService.encryptString(
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    final encToken = await _cryptoService.encryptString(sessionToken);
    await prefs.setString(_encryptedUserKey, encUser);
    await prefs.setString(_encryptedMfaKey, encMfa);
    await prefs.setString(_encryptedSessionTimestampKey, encSavedAt);
    await prefs.setString(_encryptedServerSessionTokenKey, encToken);
    _aplicarTokenSesionSupabase(sessionToken);
    await _secureStorage.delete(key: _legacyUserKey);
    await _secureStorage.delete(key: _legacyMfaKey);
  }

  Future<UsuarioApp?> obtenerSesionAlmacenada() async {
    final prefs = await SharedPreferences.getInstance();
    final encUser = prefs.getString(_encryptedUserKey);
    final encTimestamp = prefs.getString(_encryptedSessionTimestampKey);
    if (encUser == null) return _migrarSesionLegacy();
    try {
      final savedAtStr = await _cryptoService.decryptString(encTimestamp);
      final savedAtMs = int.tryParse(savedAtStr ?? '');
      if (savedAtMs == null) {
        await _limpiarSesion(preservarMfa: true);
        return null;
      }
      final savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);
      if (DateTime.now().difference(savedAt) > _sessionMaxAge) {
        await _limpiarSesion(preservarMfa: true);
        return null;
      }
      final userJson = await _cryptoService.decryptString(encUser);
      if (userJson == null) return null;
      final sessionToken = await obtenerTokenSesion();
      if (sessionToken != null && sessionToken.trim().isNotEmpty) {
        _aplicarTokenSesionSupabase(sessionToken);
      }
      return UsuarioApp.desdeJson(jsonDecode(userJson) as Map<String, dynamic>);
    } catch (_) {
      await _limpiarSesion(preservarMfa: true);
      return null;
    }
  }

  Future<bool> estaMfaHabilitado() async {
    final prefs = await SharedPreferences.getInstance();
    final encMfa = prefs.getString(_encryptedMfaKey);
    if (encMfa != null) {
      final mfa = await _cryptoService.decryptString(encMfa);
      return mfa == 'true';
    }
    final legacyMfa = await _secureStorage.read(key: _legacyMfaKey);
    if (legacyMfa == null) return false;
    final migrated = await _cryptoService.encryptString(legacyMfa);
    await prefs.setString(_encryptedMfaKey, migrated);
    await _secureStorage.delete(key: _legacyMfaKey);
    return legacyMfa == 'true';
  }

  Future<void> cerrarSesion() async {
    await _limpiarSesion(preservarMfa: true);
    _limpiarTokenSesionSupabase();
    await _secureStorage.delete(key: _legacyUserKey);
  }

  Future<String?> obtenerTokenSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final encToken = prefs.getString(_encryptedServerSessionTokenKey);
    return _cryptoService.decryptString(encToken);
  }

  Future<UsuarioApp?> _migrarSesionLegacy() async {
    final legacyJson = await _secureStorage.read(key: _legacyUserKey);
    if (legacyJson == null) return null;
    try {
      return UsuarioApp.desdeJson(
        jsonDecode(legacyJson) as Map<String, dynamic>,
      );
    } catch (_) {
      await _secureStorage.delete(key: _legacyUserKey);
      return null;
    }
  }

  Future<void> _limpiarSesion({required bool preservarMfa}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_encryptedUserKey);
    await prefs.remove(_encryptedSessionTimestampKey);
    await prefs.remove(_encryptedServerSessionTokenKey);
    if (!preservarMfa) await prefs.remove(_encryptedMfaKey);
  }

  void _aplicarTokenSesionSupabase(String sessionToken) {
    try {
      final client = Supabase.instance.client;
      client.headers = {
        ...client.headers,
        _supabaseSessionHeader: sessionToken,
      };
    } catch (_) {
      // Supabase puede no estar inicializado en pruebas unitarias.
    }
  }

  void _limpiarTokenSesionSupabase() {
    try {
      final client = Supabase.instance.client;
      final headers = Map<String, String>.from(client.headers)
        ..remove(_supabaseSessionHeader);
      client.headers = headers;
    } catch (_) {
      // Supabase puede no estar inicializado en pruebas unitarias.
    }
  }

  String _legacyHash(String pw) {
    final bytes = utf8.encode(pw + _legacyGlobalSalt);
    return sha256.convert(bytes).toString();
  }

  Uint8List _derivePassword(String pw, Uint8List salt, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, _derivedKeyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(pw)));
  }

  Uint8List _randomBytes(int length) {
    final r = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => r.nextInt(256)),
    );
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
