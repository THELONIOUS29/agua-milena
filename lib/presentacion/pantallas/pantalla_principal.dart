import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../nucleo/constantes/colores_app.dart';
import '../../dominio/entidades/rol_usuario.dart';
import '../proveedores/proveedor_autenticacion.dart';

class MainScreen extends ConsumerWidget {
  final Widget child;
  final GoRouterState state;

  const MainScreen({super.key, required this.child, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(proveedorNotificadorAuth);
    final role = authState.usuario?.rol;
    final destinations = _getDestinations(role);
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: child,
      bottomNavigationBar: isKeyboardOpen
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDark.withAlpha(245)
                      : AppColors.surfaceLight.withAlpha(245),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppColors.border(context),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 32 : 14),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: NavigationBar(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  selectedIndex: _currentIndex(role),
                  onDestinationSelected: (index) {
                    HapticFeedback.selectionClick();
                    _onTap(context, index, role);
                  },
                  animationDuration: const Duration(milliseconds: 300),
                  destinations: destinations.map((d) {
                    return NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    );
                  }).toList(),
                ),
              ),
            ),
    );
  }

  int _currentIndex(RolUsuario? role) {
    final loc = state.matchedLocation;

    switch (role) {
      case RolUsuario.vendedor:
        if (loc.startsWith('/rutas')) return 0;
        if (loc.startsWith('/alerts')) return 1;
        return 0;
      case RolUsuario.planta:
        if (loc.startsWith('/inventory')) return 1;
        if (loc.startsWith('/sales')) return 2;
        if (loc.startsWith('/rutas')) return 3;
        if (loc.startsWith('/alerts')) return 4;
        return 0;
      case RolUsuario.admin:
      default:
        if (loc.startsWith('/inventory')) return 1;
        if (loc.startsWith('/sales')) return 2;
        if (loc.startsWith('/rutas')) return 3;
        if (loc.startsWith('/alerts')) return 4;
        return 0;
    }
  }

  void _onTap(BuildContext context, int index, RolUsuario? role) {
    switch (role) {
      case RolUsuario.vendedor:
        switch (index) {
          case 0:
            context.go('/rutas');
          case 1:
            context.go('/alerts');
        }
        break;
      case RolUsuario.planta:
        switch (index) {
          case 0:
            context.go('/');
          case 1:
            context.go('/inventory');
          case 2:
            context.go('/sales');
          case 3:
            context.go('/rutas');
          case 4:
            context.go('/alerts');
        }
        break;
      case RolUsuario.admin:
      default:
        switch (index) {
          case 0:
            context.go('/');
          case 1:
            context.go('/inventory');
          case 2:
            context.go('/sales');
          case 3:
            context.go('/rutas');
          case 4:
            context.go('/alerts');
        }
        break;
    }
  }

  List<_NavDestination> _getDestinations(RolUsuario? role) {
    switch (role) {
      case RolUsuario.vendedor:
        return const [
          _NavDestination(
            icon: Icons.route_outlined,
            selectedIcon: Icons.route_rounded,
            label: 'Mi despacho',
          ),
          _NavDestination(
            icon: Icons.notifications_outlined,
            selectedIcon: Icons.notifications_rounded,
            label: 'Alertas',
          ),
        ];
      case RolUsuario.planta:
        return const [
          _NavDestination(
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard_rounded,
            label: 'Inicio',
          ),
          _NavDestination(
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2_rounded,
            label: 'Inventario',
          ),
          _NavDestination(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: 'Ventas',
          ),
          _NavDestination(
            icon: Icons.route_outlined,
            selectedIcon: Icons.route_rounded,
            label: 'Despacho',
          ),
          _NavDestination(
            icon: Icons.notifications_outlined,
            selectedIcon: Icons.notifications_rounded,
            label: 'Alertas',
          ),
        ];
      case RolUsuario.admin:
      default:
        return const [
          _NavDestination(
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard_rounded,
            label: 'Inicio',
          ),
          _NavDestination(
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2_rounded,
            label: 'Inventario',
          ),
          _NavDestination(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: 'Ventas',
          ),
          _NavDestination(
            icon: Icons.route_outlined,
            selectedIcon: Icons.route_rounded,
            label: 'Despacho',
          ),
          _NavDestination(
            icon: Icons.notifications_outlined,
            selectedIcon: Icons.notifications_rounded,
            label: 'Alertas',
          ),
        ];
    }
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
