import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:agua_milena_app/datos/modelos/item_venta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_autenticacion.dart';
import 'package:agua_milena_app/datos/servicios/servicio_venta.dart';

class SesionAislada extends ServicioAutenticacion {
  @override
  Future<String?> obtenerTokenSesion() async => 'fixture-admin-local';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const habilitada = bool.fromEnvironment('RUN_SUPABASE_INTEGRATION');
  const url = String.fromEnvironment('TEST_SUPABASE_URL');
  const anon = String.fromEnvironment('TEST_SUPABASE_ANON_KEY');
  const servicio = String.fromEnvironment('TEST_SUPABASE_SERVICE_KEY');
  const confirmacion = String.fromEnvironment('TEST_ISOLATED_CONFIRM');
  const producto = '00000000-0000-4000-8000-000000000001';
  late SupabaseClient cliente, administrador;
  group(
    'Supabase local desechable (sin mocks)',
    () {
      setUpAll(() {
        final uri = Uri.parse(url);
        if (!['127.0.0.1', 'localhost', '::1'].contains(uri.host) ||
            confirmacion != 'PROYECTO_DESECHABLE' ||
            anon.isEmpty ||
            servicio.isEmpty) {
          throw StateError(
            'Solo se permite un Supabase local desechable con claves de pruebas.',
          );
        }
        cliente = SupabaseClient(url, anon);
        administrador = SupabaseClient(url, servicio);
      });
      tearDownAll(() async {
        await cliente.dispose();
        await administrador.dispose();
      });
      setUp(() async {
        // Exclusivamente en el proyecto local desechable dedicado a estas pruebas.
        await administrador
            .schema('inventario')
            .from('productos')
            .update({'stock': 100})
            .eq('id', producto);
      });
      Future<int> stock() async {
        final fila = await administrador
            .schema('inventario')
            .from('productos')
            .select('stock')
            .eq('id', producto)
            .single();
        return fila['stock'] as int;
      }

      ItemCarrito item(int cantidad) => ItemCarrito(
        productoId: producto,
        nombreProducto: 'Fixture agua',
        precioUnitario: 3,
        unidad: 'unidad',
        cantidad: cantidad,
      );
      test(
        'DB_V01 - persistencia de venta, total y stock via servicio real',
        () async {
          final venta = await ServicioVenta(
            client: cliente,
            autenticacion: SesionAislada(),
          ).crearVenta(items: [item(2)]);
          final fila = await administrador
              .schema('ventas')
              .from('ventas')
              .select('total')
              .eq('id', venta.id)
              .single();
          expect((fila['total'] as num).toDouble(), 6);
          expect(await stock(), 98);
        },
      );
      test(
        'DB_V02 - fallo de stock conserva las cuatro tablas reales',
        () async {
          Future<List<Object>> snapshot() async => [
            await administrador
                .schema('ventas')
                .from('ventas')
                .select()
                .order('id'),
            await administrador
                .schema('ventas')
                .from('items_venta')
                .select()
                .order('id'),
            await administrador
                .schema('inventario')
                .from('productos')
                .select()
                .order('id'),
            await administrador
                .schema('inventario')
                .from('movimientos_inventario')
                .select()
                .order('id'),
          ];
          final antes = await snapshot();
          await expectLater(
            ServicioVenta(
              client: cliente,
              autenticacion: SesionAislada(),
            ).crearVenta(items: [item(101)]),
            throwsA(isA<PostgrestException>()),
          );
          expect(await snapshot(), antes);
        },
      );
      test('DB_P01 - RPC rechaza vendedor y conserva inventario', () async {
        await expectLater(
          cliente
              .schema('inventario')
              .rpc(
                'fn_registrar_movimiento_seguro',
                params: {
                  'p_session_token': 'fixture-vendedor-local',
                  'p_producto_id': producto,
                  'p_tipo': 'entrada',
                  'p_cantidad': 1,
                  'p_motivo': 'prueba local',
                },
              ),
          throwsA(isA<PostgrestException>()),
        );
        expect(await stock(), 100);
      });
      test('DB_P02 - escritura directa anonima bloqueada por BD', () async {
        // RLS puede rechazar con error o afectar cero filas: comprobar siempre el estado.
        try {
          await cliente
              .schema('inventario')
              .from('productos')
              .update({'stock': 999})
              .eq('id', producto);
        } on PostgrestException {
          /* Rechazo del servidor esperado. */
        }
        expect(await stock(), 100);
      });
    },
    skip: habilitada
        ? false
        : 'No hay Supabase local aislado y credenciales de pruebas configurados. Ver docs/auditoria_pruebas/INFORME.md.',
  );
}
