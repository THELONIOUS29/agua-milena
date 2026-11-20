import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../datos/modelos/precio_producto.dart';
import '../../datos/servicios/servicio_precio.dart';

final proveedorServicioPrecio = Provider<ServicioPrecio>(
  (ref) => ServicioPrecio(),
);

final proveedorListaPrecios = FutureProvider<List<PrecioProducto>>((ref) async {
  return ref.watch(proveedorServicioPrecio).obtenerTodos();
});

class NotificadorPrecios
    extends StateNotifier<AsyncValue<List<PrecioProducto>>> {
  final ServicioPrecio _servicio;

  NotificadorPrecios(this._servicio) : super(const AsyncLoading()) {
    cargar();
  }

  Future<void> cargar() async {
    state = const AsyncLoading();
    try {
      final lista = await _servicio.obtenerTodos();
      state = AsyncData(lista);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> guardarPrecio({
    required String productoId,
    String? vendedorId,
    required double precio,
  }) async {
    await _servicio.guardarPrecio(
      productoId: productoId,
      vendedorId: vendedorId,
      precio: precio,
    );
    await cargar();
  }

  Future<void> eliminarPrecio(String id) async {
    await _servicio.eliminarPrecio(id);
    await cargar();
  }
}

final proveedorNotificadorPrecios =
    StateNotifierProvider<NotificadorPrecios, AsyncValue<List<PrecioProducto>>>(
      (ref) => NotificadorPrecios(ref.watch(proveedorServicioPrecio)),
    );
