import 'package:flutter/foundation.dart';

import 'servicio_push_remoto.dart';

class ServicioAlertasAutomaticas {
  static final ServicioAlertasAutomaticas _instancia =
      ServicioAlertasAutomaticas._();

  factory ServicioAlertasAutomaticas({ServicioPushRemoto? push}) =>
      push == null ? _instancia : ServicioAlertasAutomaticas._(push);

  final ServicioPushRemoto? _push;
  ServicioPushRemoto get _servicioPush => _push ?? ServicioPushRemoto();

  ServicioAlertasAutomaticas._([this._push]);

  bool _revisionEnCurso = false;

  Future<Set<String>?> capturarEstadoActual() async {
    try {
      final avisos = await _servicioPush.obtenerResumenRevisionOperativa();
      return avisos.map((aviso) => aviso.clave).toSet();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('No se pudo capturar estado de alertas: $error');
      }
      return null;
    }
  }

  Future<void> notificarAlertasNuevas({
    required String motivo,
    required Set<String>? estadoPrevio,
  }) async {
    if (estadoPrevio == null) return;
    if (_revisionEnCurso) return;

    _revisionEnCurso = true;
    try {
      final avisosActuales = await _servicioPush
          .obtenerResumenRevisionOperativa();
      final avisosNuevos = avisosActuales
          .where((aviso) => !estadoPrevio.contains(aviso.clave))
          .toList();
      if (avisosNuevos.isEmpty) return;

      final push = _servicioPush;
      for (final aviso in avisosNuevos) {
        await push.enviarNotificacion(
          titulo: aviso.titulo,
          cuerpo: aviso.cuerpo,
          rol: 'admin',
          datos: aviso.datos,
        );
        await push.enviarNotificacion(
          titulo: aviso.titulo,
          cuerpo: aviso.cuerpo,
          rol: 'planta',
          datos: aviso.datos,
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('No se pudo ejecutar revision automatica ($motivo): $error');
      }
    } finally {
      _revisionEnCurso = false;
    }
  }

  Future<void> solicitarRevision({
    required String motivo,
    bool forzar = false,
  }) async {
    if (kDebugMode) {
      debugPrint(
        'Revision automatica omitida ($motivo): se requiere estado previo.',
      );
    }
  }
}
