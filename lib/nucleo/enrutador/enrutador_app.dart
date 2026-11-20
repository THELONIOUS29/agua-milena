import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../dominio/entidades/rol_usuario.dart';
import '../../presentacion/proveedores/proveedor_autenticacion.dart';

// Pantallas
import '../../presentacion/pantallas/pantalla_splash.dart';
import '../../presentacion/pantallas/pantalla_principal.dart';
import '../../presentacion/pantallas/autenticacion/pantalla_login.dart';
import '../../presentacion/pantallas/autenticacion/pantalla_mfa.dart';
import '../../presentacion/pantallas/autenticacion/pantalla_cambiar_contrasena.dart';
import '../../presentacion/pantallas/autenticacion/pantalla_perfil.dart';
import '../../presentacion/pantallas/panel/pantalla_panel.dart';
import '../../presentacion/pantallas/inventario/pantalla_inventario.dart';
import '../../presentacion/pantallas/inventario/pantalla_formulario_producto.dart';
import '../../presentacion/pantallas/inventario/pantalla_detalle_producto.dart';
import '../../presentacion/pantallas/ventas/pantalla_ventas.dart';
import '../../presentacion/pantallas/ventas/pantalla_nueva_venta.dart';
import '../../presentacion/pantallas/ventas/pantalla_detalle_venta.dart';
import '../../presentacion/pantallas/vendedores/pantalla_vendedores.dart';
import '../../presentacion/pantallas/rutas/pantalla_rutas.dart';
import '../../presentacion/pantallas/rutas/pantalla_nueva_ruta.dart';
import '../../presentacion/pantallas/rutas/pantalla_detalle_ruta.dart';
import '../../presentacion/pantallas/alertas/pantalla_alertas.dart';
import '../../presentacion/pantallas/usuarios/pantalla_usuarios.dart';
import '../../presentacion/pantallas/usuarios/pantalla_formulario_usuario.dart';
import '../../datos/modelos/producto.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final proveedorEnrutador = Provider<GoRouter>((ref) {
  final refreshListenable = ValueNotifier<int>(0);
  ref.onDispose(refreshListenable.dispose);
  ref.listen(proveedorNotificadorAuth, (_, _) {
    refreshListenable.value++;
  });

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final authState = ref.read(proveedorNotificadorAuth);
      return redirigirAutenticacion(authState, state.matchedLocation);
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/mfa', builder: (_, _) => const MfaScreen()),
      GoRoute(
        path: '/change-password',
        builder: (_, state) => ChangePasswordScreen(
          fromProfile: state.uri.queryParameters['from'] == 'profile',
        ),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (_, state, child) => MainScreen(state: state, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          GoRoute(
            path: '/inventory',
            builder: (_, _) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/inventory/add',
            builder: (_, _) => const ProductFormScreen(),
          ),
          GoRoute(
            path: '/inventory/edit/:id',
            builder: (_, state) =>
                ProductFormScreen(producto: state.extra as Producto?),
          ),
          GoRoute(
            path: '/inventory/detail/:id',
            builder: (_, state) =>
                ProductDetailScreen(productoId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/sales', builder: (_, _) => const SalesScreen()),
          GoRoute(
            path: '/sales/new',
            builder: (_, state) => NewSaleScreen(
              preselectedSellerId: state.uri.queryParameters['sellerId'],
            ),
          ),
          GoRoute(
            path: '/sales/detail/:id',
            builder: (_, state) =>
                SaleDetailScreen(saleId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/sellers', builder: (_, _) => const SellersScreen()),
          GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
          GoRoute(
            path: '/users/add',
            builder: (_, state) => UserFormScreen(
              crearVendedor: state.uri.queryParameters['rol'] == 'vendedor',
            ),
          ),
          GoRoute(
            path: '/users/edit/:id',
            builder: (_, state) =>
                UserFormScreen(user: state.extra as Map<String, dynamic>?),
          ),
          GoRoute(path: '/rutas', builder: (_, _) => const RutasScreen()),
          GoRoute(
            path: '/rutas/new',
            builder: (_, state) => NewRutaScreen(
              preselectedSellerId: state.uri.queryParameters['sellerId'],
            ),
          ),
          GoRoute(
            path: '/rutas/detail/:id',
            builder: (_, state) => RutaDetailScreen(
              rutaId: state.pathParameters['id']!,
              showAbonoOnOpen: state.uri.queryParameters['showAbono'] == '1',
            ),
          ),
          GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
        ],
      ),
    ],
  );
});

// Compartida por GoRouter y sus pruebas; no sustituye permisos del servidor.
String? redirigirAutenticacion(
  EstadoAutenticacion authState,
  String ubicacion,
) {
  final isSplash = ubicacion == '/splash';
  final isLogin = ubicacion == '/login';
  final isMfa = ubicacion == '/mfa';

  if (authState.cargando && isSplash) return null;

  if (!authState.autenticado && !authState.requiereMfa) {
    return isLogin ? null : '/login';
  }

  if (authState.requiereMfa) {
    return isMfa ? null : '/mfa';
  }

  if (authState.autenticado) {
    if (isLogin || isSplash || isMfa) {
      if (authState.debeCambiarContrasena) return '/change-password';
      return '/';
    }

    if (authState.debeCambiarContrasena && ubicacion != '/change-password') {
      return '/change-password';
    }

    final role = authState.usuario?.rol;
    final loc = ubicacion;

    if (role == RolUsuario.vendedor) {
      if (loc == '/rutas/new' ||
          (!loc.startsWith('/rutas') &&
              !loc.startsWith('/alerts') &&
              loc != '/' &&
              loc != '/change-password' &&
              loc != '/profile')) {
        return '/rutas';
      }
      if (loc == '/') return '/rutas';
    } else if (role == RolUsuario.planta) {
      if (loc.startsWith('/sellers') || loc.startsWith('/users')) {
        return '/';
      }
    }
  }

  return null;
}
