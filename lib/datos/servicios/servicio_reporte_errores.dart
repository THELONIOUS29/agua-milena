import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'servicio_autenticacion.dart';
import 'servicio_info_dispositivo.dart';

/// Servicio global de captura y reporte de errores.
class ServicioReporteErrores {
  static ServicioReporteErrores? _instance;
  static ServicioReporteErrores get instance =>
      _instance ??= ServicioReporteErrores._();
  ServicioReporteErrores._();

  String? _pantallaActual;

  void establecerUsuario(String? userId) {}
  void establecerPantalla(String? pantalla) => _pantallaActual = pantalla;

  Future<void> reportarErrorFlutter(FlutterErrorDetails details) async {
    await _enviarError(
      nivel: 'error',
      mensaje: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
      pantalla: _pantallaActual,
    );
    if (kDebugMode) FlutterError.dumpErrorToConsole(details);
  }

  Future<void> reportarError(Object error, StackTrace stack) async {
    await _enviarError(
      nivel: 'error',
      mensaje: error.toString(),
      stackTrace: stack.toString(),
      pantalla: _pantallaActual,
    );
    if (kDebugMode) debugPrint('ERROR: $error\n$stack');
  }

  Future<void> reportarFatal(Object error, StackTrace stack) async {
    await _enviarError(
      nivel: 'fatal',
      mensaje: error.toString(),
      stackTrace: stack.toString(),
      pantalla: _pantallaActual,
    );
  }

  Future<void> reportarAdvertencia(
    String mensaje, {
    String? pantalla,
    Map<String, dynamic>? metadata,
  }) async {
    await _enviarError(
      nivel: 'warning',
      mensaje: mensaje,
      pantalla: pantalla ?? _pantallaActual,
      metadata: metadata,
    );
  }

  Future<void> _enviarError({
    required String nivel,
    required String mensaje,
    String? stackTrace,
    String? pantalla,
    String? endpoint,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final device = ServicioInfoDispositivo.instance;
      final client = Supabase.instance.client;
      final sessionToken = await ServicioAutenticacion().obtenerTokenSesion();
      await client
          .schema('auditoria')
          .rpc(
            'fn_log_error_secure',
            params: {
              'p_session_token': sessionToken,
              'p_nivel': nivel,
              'p_mensaje': mensaje.length > 2000
                  ? mensaje.substring(0, 2000)
                  : mensaje,
              'p_stack_trace': stackTrace != null && stackTrace.length > 5000
                  ? stackTrace.substring(0, 5000)
                  : stackTrace,
              'p_pantalla': pantalla,
              'p_endpoint': endpoint,
              'p_dispositivo': device.nombreDispositivo,
              'p_os_version': device.versionOS,
              'p_app_version': device.versionApp,
              'p_metadata': metadata,
            },
          );
    } catch (_) {
      if (kDebugMode) {
        debugPrint('No se pudo enviar error al servidor: $mensaje');
      }
    }
  }
}
