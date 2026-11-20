import 'package:flutter_test/flutter_test.dart';
import 'package:agua_milena_app/datos/modelos/venta.dart';
import 'package:agua_milena_app/datos/modelos/ruta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_venta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_ruta.dart';
import 'package:agua_milena_app/presentacion/proveedores/proveedor_venta.dart';
import 'package:agua_milena_app/presentacion/proveedores/proveedor_ruta.dart';
import 'package:agua_milena_app/dominio/entidades/rol_usuario.dart';

// Las decisiones de permiso se ejecutan en los notificadores reales.
// Estas dependencias solo registran llamadas; no implementan autorización ni persistencia.
class VentasDependencia extends Fake implements ServicioVenta {
  int eliminaciones = 0;
  @override
  Future<List<Venta>> obtenerTodas() async => [];
  @override
  Future<void> eliminar(String id) async {
    eliminaciones++;
  }
}

class RutasDependencia extends Fake implements ServicioRuta {
  int eliminaciones = 0, abonos = 0;
  @override
  Future<List<Ruta>> obtenerTodas() async => [];
  @override
  Future<List<Ruta>> obtenerPorVendedor(String id) async => [];
  @override
  Future<void> eliminar(String id) async {
    eliminaciones++;
  }

  @override
  Future<Ruta> registrarAbono({
    required String rutaId,
    required double monto,
    String? nota,
  }) async {
    abonos++;
    return Ruta(
      id: rutaId,
      vendedorId: 'v1',
      nombreVendedor: 'Fixture',
      fecha: DateTime(2026),
      creadoEn: DateTime(2026),
      montoTotal: 100,
      montoCobrado: 0,
      estado: EstadoRuta.pendiente,
    );
  }
}

void main() {
  for (final rol in RolUsuario.values) {
    final usuario = UsuarioApp(
      id: 'u1',
      email: 'fixture@example.invalid',
      nombre: 'Fixture',
      rol: rol,
      vendedorId: 'v1',
    );
    test('OP_V01_${rol.name} - permiso real de eliminar venta', () async {
      final dependencia = VentasDependencia();
      final notificador = NotificadorVenta(dependencia, usuario);
      addTearDown(notificador.dispose);
      await notificador.cargar();
      if (rol == RolUsuario.admin) {
        await notificador.eliminar('venta1');
        expect(dependencia.eliminaciones, 1);
      } else {
        await expectLater(notificador.eliminar('venta1'), throwsStateError);
        expect(dependencia.eliminaciones, 0);
      }
    });
    test('OP_R01_${rol.name} - permiso real de eliminar ruta', () async {
      final dependencia = RutasDependencia();
      final notificador = NotificadorRuta(dependencia, usuario);
      addTearDown(notificador.dispose);
      await notificador.cargar();
      if (rol == RolUsuario.admin) {
        await notificador.eliminar('ruta1');
        expect(dependencia.eliminaciones, 1);
      } else {
        await expectLater(notificador.eliminar('ruta1'), throwsStateError);
        expect(dependencia.eliminaciones, 0);
      }
    });
    test('OP_R02_${rol.name} - permiso real de registrar abono', () async {
      final dependencia = RutasDependencia();
      final notificador = NotificadorRuta(dependencia, usuario);
      addTearDown(notificador.dispose);
      await notificador.cargar();
      if (rol == RolUsuario.vendedor) {
        await expectLater(
          notificador.registrarAbono(rutaId: 'r1', monto: 10),
          throwsStateError,
        );
        expect(dependencia.abonos, 0);
      } else {
        await notificador.registrarAbono(rutaId: 'r1', monto: 10);
        expect(dependencia.abonos, 1);
      }
    });
  }
}
