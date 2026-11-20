import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

/// Cifrado local de variables sensibles con AES-GCM.
class ServicioCriptografia {
  ServicioCriptografia();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _encryptionKeyStorageKey = 'session_encryption_key';
  static const String _payloadVersion = 'v1';

  Future<String> encryptString(String plaintext) async {
    final key = await _getOrCreateKey();
    final iv = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final input = Uint8List.fromList(utf8.encode(plaintext));
    final encrypted = cipher.process(input);
    return '$_payloadVersion.${base64UrlEncode(iv)}.${base64UrlEncode(encrypted)}';
  }

  Future<String?> decryptString(String? payload) async {
    if (payload == null || payload.isEmpty) return null;
    if (!payload.startsWith('$_payloadVersion.')) return payload;
    final parts = payload.split('.');
    if (parts.length != 3) return null;
    try {
      final key = await _getOrCreateKey();
      final iv = base64Url.decode(parts[1]);
      final encrypted = base64Url.decode(parts[2]);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
      final decrypted = cipher.process(Uint8List.fromList(encrypted));
      return utf8.decode(decrypted);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _getOrCreateKey() async {
    final existing = await _secureStorage.read(key: _encryptionKeyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return Uint8List.fromList(base64Url.decode(existing));
    }
    final key = _randomBytes(32);
    await _secureStorage.write(
      key: _encryptionKeyStorageKey,
      value: base64UrlEncode(key),
    );
    return key;
  }

  Uint8List _randomBytes(int length) {
    final r = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => r.nextInt(256)),
    );
  }
}
