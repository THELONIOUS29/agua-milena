import 'package:agua_milena_app/datos/modelos/vendedor.dart';
import 'package:agua_milena_app/datos/servicios/servicio_vendedor.dart';
import 'package:agua_milena_app/presentacion/pantallas/usuarios/pantalla_formulario_usuario.dart';
import 'package:agua_milena_app/presentacion/proveedores/proveedor_usuario.dart';
import 'package:agua_milena_app/presentacion/proveedores/proveedor_vendedor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class _Vendedores extends Fake implements ServicioVendedor {
  @override
  Future<List<Vendedor>> obtenerTodos() async => [
    Vendedor(
      id: 'v1',
      nombre: 'Nelson',
      telefono: 'TELEFONO_DE_EJEMPLO',
      activo: true,
      creadoEn: DateTime(2026),
    ),
  ];
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final tieneCuenta in [false, true]) {
    testWidgets('vincular vendedor con cuenta: $tieneCuenta', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cuenta = <String, dynamic>{
        'id': 'u1',
        'name': 'Nelson Usuario',
        'role': 'vendedor',
        'email': 'nelson@example.com',
        'phone': 'TELEFONO_DE_EJEMPLO',
        'seller_id': 'v1',
      };
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const UserFormScreen(crearVendedor: true),
          ),
          GoRoute(
            path: '/users/edit/:id',
            builder: (_, state) =>
                UserFormScreen(user: state.extra as Map<String, dynamic>),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            proveedorServicioVendedor.overrideWithValue(_Vendedores()),
            proveedorUsuarios.overrideWith(
              (ref) async => tieneCuenta ? [cuenta] : [],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Guardar y crear perfil'), findsOneWidget);
      await tester.tap(find.text('Vincular existente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Asociar a un perfil de vendedor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nelson').last);
      await tester.pumpAndSettle();
      final campos = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(
        campos[0].controller!.text,
        tieneCuenta ? 'Nelson Usuario' : 'Nelson',
      );
      expect(
        campos[1].controller!.text,
        tieneCuenta ? 'nelson@example.com' : '',
      );
      expect(campos[2].controller!.text, 'TELEFONO_DE_EJEMPLO');
      expect(campos[3].controller!.text, isEmpty);
      if (tieneCuenta) expect(find.text('Editar Usuario'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
