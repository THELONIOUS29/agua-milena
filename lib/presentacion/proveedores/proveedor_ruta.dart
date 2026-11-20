import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/modelos/item_ruta.dart';
import '../../datos/modelos/ruta.dart';
import '../../datos/servicios/servicio_ruta.dart';
import '../../dominio/entidades/rol_usuario.dart';
import 'proveedor_autenticacion.dart';

final proveedorServicioRuta = Provider<ServicioRuta>((ref) => ServicioRuta());

class NotificadorRuta extends StateNotifier<AsyncValue<List<Ruta>>> {
  final ServicioRuta _servicio;
  final UsuarioApp? _usuario;

  NotificadorRuta(this._servicio, this._usuario) : super(const AsyncLoading()) {
    cargar();
  }

  void _exigirGestionOperativa(String accion) {
    final rol = _usuario?.rol;
    if (rol != RolUsuario.admin && rol != RolUsuario.planta) {
      throw StateError('El rol Vendedor no puede $accion.');
    }
  }

  Future<void> cargar() async {
    state = const AsyncLoading();
    try {
      List<Ruta> rutas;
      if (_usuario?.rol == RolUsuario.vendedor) {
        final vendedorId = _usuario?.vendedorId;
        if (vendedorId == null || vendedorId.isEmpty) {
          throw StateError(
            'El usuario Vendedor no esta vinculado a un vendedor.',
          );
        }
        rutas = await _servicio.obtenerPorVendedor(vendedorId);
      } else {
        rutas = await _servicio.obtenerTodas();
      }
      state = AsyncData(rutas);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<Ruta> crear({
    required String vendedorId,
    required List<ItemRutaBorrador> items,
    String? notas,
    int bidonesCargadosHoy = 0,
  }) async {
    _exigirGestionOperativa('crear despachos');
    final ruta = await _servicio.crearRuta(
      vendedorId: vendedorId,
      items: items,
      notas: notas,
      bidonesCargadosHoy: bidonesCargadosHoy,
    );
    await cargar();
    return ruta;
  }

  Future<Ruta> cerrarRuta({
    required String rutaId,
    required List<ItemRuta> itemsConRetorno,
  }) async {
    _exigirGestionOperativa('cerrar despachos');
    final ruta = await _servicio.cerrarRuta(
      rutaId: rutaId,
      itemsConRetorno: itemsConRetorno,
    );
    await cargar();
    return ruta;
  }

  Future<Ruta> registrarPagoConDescuento({
    required String rutaId,
    required double montoEfectivo,
    required double descuento,
    String? nota,
    double credito = 0,
    String? operacionId,
  }) async {
    _exigirGestionOperativa('registrar abonos');
    final ruta = await _servicio.registrarPagoConDescuento(
      rutaId: rutaId,
      montoEfectivo: montoEfectivo,
      descuento: descuento,
      nota: nota,
      credito: credito,
      operacionId: operacionId,
    );
    await cargar();
    return ruta;
  }

  Future<Ruta> registrarAbono({
    required String rutaId,
    required double monto,
    String? nota,
  }) async {
    _exigirGestionOperativa('registrar abonos');
    final ruta = await _servicio.registrarAbono(
      rutaId: rutaId,
      monto: monto,
      nota: nota,
    );
    await cargar();
    return ruta;
  }

  Future<void> eliminar(String id) async {
    if (_usuario?.rol != RolUsuario.admin) {
      throw StateError('Solo el administrador puede eliminar despachos.');
    }
    final previousState = state;
    if (state.hasValue) {
      final currentList = state.value!;
      state = AsyncData(currentList.where((r) => r.id != id).toList());
    }
    try {
      await _servicio.eliminar(id);
    } catch (e) {
      state = previousState;
      rethrow;
    }
  }

  Future<void> actualizarNota(String id, String? notas) async {
    _exigirGestionOperativa('editar despachos');
    await _servicio.actualizarNota(id, notas);
    await cargar();
  }
}

final proveedorNotificadorRuta =
    StateNotifierProvider<NotificadorRuta, AsyncValue<List<Ruta>>>(
      (ref) => NotificadorRuta(
        ref.watch(proveedorServicioRuta),
        ref.watch(proveedorNotificadorAuth.select((estado) => estado.usuario)),
      ),
    );
