import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/modelos/producto.dart';
import '../../datos/servicios/servicio_producto.dart';

final proveedorServicioProducto = Provider<ServicioProducto>(
  (ref) => ServicioProducto(),
);

class NotificadorProducto extends StateNotifier<AsyncValue<List<Producto>>> {
  final ServicioProducto _servicio;

  NotificadorProducto(this._servicio) : super(const AsyncLoading()) {
    cargar();
  }

  Future<void> cargar() async {
    state = const AsyncLoading();
    try {
      final productos = await _servicio.obtenerTodos();
      state = AsyncData(productos);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> crearProducto(Map<String, dynamic> json) async {
    await _servicio.crear(json);
    await cargar();
  }

  Future<void> actualizarProducto(String id, Map<String, dynamic> json) async {
    await _servicio.actualizar(id, json);
    await cargar();
  }

  Future<void> eliminarProducto(String id) async {
    await _servicio.eliminar(id);
    await cargar();
  }

  Future<void> registrarMovimiento({
    required String productoId,
    required String tipo,
    required int cantidad,
    String? motivo,
  }) async {
    await _servicio.registrarMovimiento(
      productoId: productoId,
      tipo: tipo,
      cantidad: cantidad,
      motivo: motivo,
    );
    await cargar();
  }
}

final proveedorNotificadorProducto =
    StateNotifierProvider<NotificadorProducto, AsyncValue<List<Producto>>>(
      (ref) => NotificadorProducto(ref.watch(proveedorServicioProducto)),
    );
