import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../datos/modelos/notificacion_app.dart';
import '../../datos/servicios/servicio_notificacion.dart';

final proveedorServicioNotificacion = Provider<ServicioNotificacion>(
  (ref) => ServicioNotificacion(),
);

class NotificadorHistorialNotificaciones
    extends StateNotifier<List<NotificacionApp>> {
  NotificadorHistorialNotificaciones() : super([]);

  void agregar(String titulo, String cuerpo) {
    state = [NotificacionApp(titulo: titulo, cuerpo: cuerpo), ...state];
  }

  void marcarComoLeida(String id) {
    state = [
      for (final n in state)
        if (n.id == id) n.copiarCon(leida: true) else n,
    ];
  }

  void limpiarTodo() => state = [];
}

final proveedorHistorialNotificaciones =
    StateNotifierProvider<
      NotificadorHistorialNotificaciones,
      List<NotificacionApp>
    >((ref) => NotificadorHistorialNotificaciones());

class ServicioNotificacionApp {
  final ServicioNotificacion _servicio;
  final NotificadorHistorialNotificaciones _historial;
  ServicioNotificacionApp(this._servicio, this._historial);

  Future<void> mostrarNotificacionLocal({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    await _servicio.mostrarNotificacionLocal(
      id: id,
      titulo: titulo,
      cuerpo: cuerpo,
      payload: payload,
    );
    _historial.agregar(titulo, cuerpo);
  }

  Future<String?> obtenerToken() => _servicio.obtenerToken();
}

final proveedorServicioNotificacionApp = Provider<ServicioNotificacionApp>(
  (ref) => ServicioNotificacionApp(
    ref.watch(proveedorServicioNotificacion),
    ref.watch(proveedorHistorialNotificaciones.notifier),
  ),
);

final proveedorInicializarNotificaciones = FutureProvider<void>((ref) async {
  final servicio = ref.watch(proveedorServicioNotificacion);
  await servicio.inicializar(
    alRecibirMensaje: (titulo, cuerpo) {
      ref
          .read(proveedorHistorialNotificaciones.notifier)
          .agregar(titulo, cuerpo);
    },
  );
});
