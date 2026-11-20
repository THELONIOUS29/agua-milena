import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../datos/modelos/venta.dart';
import '../../datos/modelos/item_venta.dart';
import '../../datos/servicios/servicio_venta.dart';
import '../../dominio/entidades/rol_usuario.dart';
import 'proveedor_autenticacion.dart';

final proveedorServicioVenta = Provider<ServicioVenta>(
  (ref) => ServicioVenta(),
);

class NotificadorVenta extends StateNotifier<AsyncValue<List<Venta>>> {
  final ServicioVenta _servicio;
  final UsuarioApp? _usuario;

  NotificadorVenta(this._servicio, this._usuario)
    : super(const AsyncLoading()) {
    cargar();
  }

  Future<void> cargar() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _servicio.obtenerTodas());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<Venta> crearVenta({
    required List<ItemCarrito> items,
    String? notas,
    String? vendedorId,
    int bidonesLlenosEnCarro = 0,
    int bidonesVaciosRecibidos = 0,
    bool aplicarSaldoAFavor = false,
  }) async {
    final venta = await _servicio.crearVenta(
      items: items,
      notas: notas,
      vendedorId: vendedorId,
      bidonesLlenosEnCarro: bidonesLlenosEnCarro,
      bidonesVaciosRecibidos: bidonesVaciosRecibidos,
      aplicarSaldoAFavor: aplicarSaldoAFavor,
    );
    await cargar();
    return venta;
  }

  Future<void> eliminar(String id) async {
    if (_usuario?.rol != RolUsuario.admin) {
      throw StateError('Solo el administrador puede eliminar ventas.');
    }
    final previousState = state;
    if (state.hasValue) {
      final currentList = state.value!;
      state = AsyncData(currentList.where((v) => v.id != id).toList());
    }
    try {
      await _servicio.eliminar(id);
    } catch (e) {
      state = previousState;
      rethrow;
    }
  }

  Future<void> actualizarNota(String id, String? notas) async {
    await _servicio.actualizarNota(id, notas);
    await cargar();
  }
}

final proveedorNotificadorVenta =
    StateNotifierProvider<NotificadorVenta, AsyncValue<List<Venta>>>(
      (ref) => NotificadorVenta(
        ref.watch(proveedorServicioVenta),
        ref.watch(proveedorNotificadorAuth.select((estado) => estado.usuario)),
      ),
    );

// ── Carrito ──────────────────────────────────────────────────────────────────

class NotificadorCarrito extends StateNotifier<List<ItemCarrito>> {
  NotificadorCarrito() : super([]);

  void agregarProducto(ItemCarrito item) {
    final idx = state.indexWhere((i) => i.productoId == item.productoId);
    if (idx >= 0) {
      final u = [...state];
      u[idx].cantidad += item.cantidad;
      state = u;
    } else {
      state = [...state, item];
    }
  }

  void actualizarCantidad(String productoId, int cantidad) {
    if (cantidad <= 0) {
      // Si tiene devoluciones, mantener el item solo con devolución
      final existing = state.firstWhere(
        (i) => i.productoId == productoId,
        orElse: () => ItemCarrito(
          productoId: '',
          nombreProducto: '',
          precioUnitario: 0,
          unidad: '',
        ),
      );
      if (existing.devolucion > 0) {
        state = state
            .map(
              (i) => i.productoId == productoId
                  ? (ItemCarrito(
                      productoId: i.productoId,
                      nombreProducto: i.nombreProducto,
                      precioUnitario: i.precioUnitario,
                      unidad: i.unidad,
                      cantidad: 0,
                      devolucion: i.devolucion,
                    ))
                  : i,
            )
            .toList();
        return;
      }
      eliminarProducto(productoId);
      return;
    }
    state = state
        .map(
          (i) => i.productoId == productoId
              ? (ItemCarrito(
                  productoId: i.productoId,
                  nombreProducto: i.nombreProducto,
                  precioUnitario: i.precioUnitario,
                  unidad: i.unidad,
                  cantidad: cantidad,
                  devolucion: i.devolucion,
                ))
              : i,
        )
        .toList();
  }

  void actualizarDevolucion(
    String productoId,
    int devolucion, {
    required String nombreProducto,
    required double precioUnitario,
    required String unidad,
  }) {
    final idx = state.indexWhere((i) => i.productoId == productoId);
    if (idx >= 0) {
      state = state
          .map(
            (i) => i.productoId == productoId
                ? (ItemCarrito(
                    productoId: i.productoId,
                    nombreProducto: i.nombreProducto,
                    precioUnitario: i.precioUnitario,
                    unidad: i.unidad,
                    cantidad: i.cantidad,
                    devolucion: devolucion,
                  ))
                : i,
          )
          .toList();
      // Si cantidad y devolucion son 0, eliminar
      final updated = state.firstWhere((i) => i.productoId == productoId);
      if (updated.cantidad <= 0 && updated.devolucion <= 0) {
        eliminarProducto(productoId);
      }
    } else if (devolucion > 0) {
      // Item no existía, agregarlo solo con devolución
      state = [
        ...state,
        ItemCarrito(
          productoId: productoId,
          nombreProducto: nombreProducto,
          precioUnitario: precioUnitario,
          unidad: unidad,
          cantidad: 0,
          devolucion: devolucion,
        ),
      ];
    }
  }

  void eliminarProducto(String productoId) =>
      state = state.where((i) => i.productoId != productoId).toList();
  void limpiar() => state = [];
  double get total => state.fold(0.0, (s, i) => s + i.subtotal);
  double get totalDevoluciones =>
      state.fold(0.0, (s, i) => s + i.creditoDevolucion);
}

final proveedorCarrito =
    StateNotifierProvider<NotificadorCarrito, List<ItemCarrito>>(
      (ref) => NotificadorCarrito(),
    );
final proveedorTotalCarrito = Provider<double>(
  (ref) => ref.watch(proveedorCarrito).fold(0.0, (s, i) => s + i.subtotal),
);
final proveedorTotalDevoluciones = Provider<double>(
  (ref) =>
      ref.watch(proveedorCarrito).fold(0.0, (s, i) => s + i.creditoDevolucion),
);
