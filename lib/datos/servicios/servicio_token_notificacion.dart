import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'servicio_autenticacion.dart';

class ServicioTokenNotificacion {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final ServicioAutenticacion _servicioAutenticacion = ServicioAutenticacion();
  StreamSubscription<String>? _suscripcionCambioToken;

  Future<String?> registrarTokenActual() async {
    final tokenFirebase = kIsWeb
        ? await _firebaseMessaging.getToken(
            vapidKey:
                'BACdvuy9j9NyKB8dxNYAmBOz8GPYIn_qnenW9z2pVC_wTHSUwRjrVcIHE3iyTy-CU3XfqUIiy4m5oEV2s96LSZM',
          )
        : await _firebaseMessaging.getToken();
    if (tokenFirebase == null || tokenFirebase.trim().isEmpty) return null;

    await _registrarToken(tokenFirebase);
    _escucharCambiosToken();
    return tokenFirebase;
  }

  Future<void> desactivarTokenActual() async {
    final tokenFirebase = kIsWeb
        ? await _firebaseMessaging.getToken(
            vapidKey:
                'BACdvuy9j9NyKB8dxNYAmBOz8GPYIn_qnenW9z2pVC_wTHSUwRjrVcIHE3iyTy-CU3XfqUIiy4m5oEV2s96LSZM',
          )
        : await _firebaseMessaging.getToken();
    final tokenSesion = await _servicioAutenticacion.obtenerTokenSesion();
    if (tokenFirebase == null ||
        tokenFirebase.trim().isEmpty ||
        tokenSesion == null ||
        tokenSesion.trim().isEmpty) {
      return;
    }

    await Supabase.instance.client
        .schema('usuarios')
        .rpc(
          'fn_desactivar_token_dispositivo',
          params: {
            'p_session_token': tokenSesion,
            'p_token_firebase': tokenFirebase,
          },
        );
  }

  void cancelarEscucha() {
    _suscripcionCambioToken?.cancel();
    _suscripcionCambioToken = null;
  }

  void _escucharCambiosToken() {
    _suscripcionCambioToken ??= _firebaseMessaging.onTokenRefresh.listen((
      token,
    ) async {
      try {
        await _registrarToken(token);
      } catch (error, stackTrace) {
        debugPrint('No se pudo actualizar el token Firebase: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  Future<void> _registrarToken(String tokenFirebase) async {
    final tokenSesion = await _servicioAutenticacion.obtenerTokenSesion();
    if (tokenSesion == null || tokenSesion.trim().isEmpty) return;

    await Supabase.instance.client
        .schema('usuarios')
        .rpc(
          'fn_registrar_token_dispositivo',
          params: {
            'p_session_token': tokenSesion,
            'p_token_firebase': tokenFirebase,
            'p_plataforma': defaultTargetPlatform.name,
            'p_nombre_dispositivo': 'Agua Milena ${defaultTargetPlatform.name}',
          },
        );
  }
}
