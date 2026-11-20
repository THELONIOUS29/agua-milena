import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../datos/modelos/vendedor.dart';
import '../../datos/servicios/servicio_vendedor.dart';

final proveedorServicioVendedor = Provider<ServicioVendedor>(
  (ref) => ServicioVendedor(),
);

class NotificadorVendedor extends StateNotifier<AsyncValue<List<Vendedor>>> {
  final ServicioVendedor _servicio;
  NotificadorVendedor(this._servicio) : super(const AsyncLoading()) {
    cargar();
  }

  Future<void> cargar() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(await _servicio.obtenerTodos());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<Vendedor> crear(
    String nombre,
    String? telefono, {
    int bidonesPropios = 0,
    int bidonesPrestados = 0,
    int bidonesLlenosActuales = 0,
    int bidonesVaciosActuales = 0,
  }) async {
    final v = await _servicio.crear(
      nombre,
      telefono,
      bidonesPropios: bidonesPropios,
      bidonesPrestados: bidonesPrestados,
      bidonesLlenosActuales: bidonesLlenosActuales,
      bidonesVaciosActuales: bidonesVaciosActuales,
    );
    await cargar();
    return v;
  }

  Future<void> actualizar(
    String id, {
    String? nombre,
    String? telefono,
    bool? activo,
    int? bidonesPropios,
    int? bidonesPrestados,
    int? bidonesLlenosActuales,
    int? bidonesVaciosActuales,
  }) async {
    await _servicio.actualizar(
      id,
      nombre: nombre,
      telefono: telefono,
      activo: activo,
      bidonesPropios: bidonesPropios,
      bidonesPrestados: bidonesPrestados,
      bidonesLlenosActuales: bidonesLlenosActuales,
      bidonesVaciosActuales: bidonesVaciosActuales,
    );
    await cargar();
  }

  Future<void> eliminar(String id) async {
    await _servicio.eliminar(id);
    await cargar();
  }
}

final proveedorNotificadorVendedor =
    StateNotifierProvider<NotificadorVendedor, AsyncValue<List<Vendedor>>>(
      (ref) => NotificadorVendedor(ref.watch(proveedorServicioVendedor)),
    );

final proveedorVendedoresActivos = Provider<AsyncValue<List<Vendedor>>>(
  (ref) => ref
      .watch(proveedorNotificadorVendedor)
      .whenData(
        (vendedores) => vendedores
            .where((vendedor) => vendedor.activo)
            .toList(growable: false),
      ),
);
