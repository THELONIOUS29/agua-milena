import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../proveedores/proveedor_autenticacion.dart';
import '../../proveedores/proveedor_usuario.dart';

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(proveedorUsuarios);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gesti\u00f3n de usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.refresh(proveedorUsuarios),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/users/add'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo usuario'),
      ),
      body: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _mensajeErrorUsuarios(error),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No hay usuarios registrados.',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: users.length,
            itemBuilder: (context, index) => _UserCard(
              key: ValueKey(users[index]['id']),
              user: users[index],
            ),
          );
        },
      ),
    );
  }

  String _mensajeErrorUsuarios(Object error) {
    final texto = error.toString();
    if (texto.contains('token_hash') || texto.contains('42702')) {
      return 'La base de datos tiene una funcion de usuarios pendiente de actualizar. Aplica el parche SQL de usuarios y vuelve a cargar.';
    }
    return 'No se pudo cargar la gestion de usuarios: $texto';
  }
}

class _UserCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> user;

  const _UserCard({super.key, required this.user});

  @override
  ConsumerState<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends ConsumerState<_UserCard> {
  bool _eliminando = false;

  Future<void> _eliminar() async {
    if (_eliminando) return;
    final id = widget.user['id'].toString();
    final messenger = ScaffoldMessenger.of(context);
    if (ref.read(proveedorNotificadorAuth).usuario?.id == id) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No puedes eliminar tu propia cuenta.')),
      );
      return;
    }
    final nombre =
        widget.user['name'] ?? widget.user['nombre'] ?? 'este usuario';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
          '¿Deseas eliminar a $nombre? Esta acción no se puede deshacer y el usuario dejará de tener acceso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _eliminando = true);
    try {
      await ref.read(proveedorServicioUsuario).eliminar(id);
      if (!mounted) return;
      ref.invalidate(proveedorUsuarios);
      messenger.showSnackBar(
        const SnackBar(content: Text('Usuario eliminado correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      final mensaje = error.toString().contains('23503')
          ? 'Este usuario tiene registros asociados. Puedes desactivarlo desde la edición de usuario.'
          : 'No se pudo eliminar el usuario. Inténtalo nuevamente.';
      messenger.showSnackBar(SnackBar(content: Text(mensaje)));
    } finally {
      if (mounted) setState(() => _eliminando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final role = (user['role'] ?? user['rol'] ?? 'planta').toString();
    final active = (user['active'] ?? user['activo'] ?? true) as bool;
    final name = (user['name'] ?? user['nombre'] ?? 'Sin nombre').toString();
    final email = (user['email'] ?? '').toString();
    final phone = (user['phone'] ?? user['telefono'])?.toString().trim();

    late final IconData roleIcon;
    late final Color roleColor;
    late final String roleLabel;

    if (role == 'admin') {
      roleIcon = Icons.admin_panel_settings_rounded;
      roleColor = Colors.purpleAccent;
      roleLabel = 'Administrador';
    } else if (role == 'vendedor') {
      roleIcon = Icons.local_shipping_rounded;
      roleColor = Colors.orangeAccent;
      roleLabel = 'Vendedor';
    } else {
      roleIcon = Icons.factory_rounded;
      roleColor = Colors.cyanAccent;
      roleLabel = 'Planta';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: AppColors.card(context),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _eliminando
            ? null
            : () => context.push('/users/edit/${user['id']}', extra: user),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: roleColor.withAlpha(48),
                        child: Icon(roleIcon, color: roleColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary(context),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                            if (phone != null && phone.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                phone,
                                style: GoogleFonts.inter(
                                  color: AppColors.textHint(context),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 12),
                        _StatusPill(activo: active),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _RolePill(
                        icon: roleIcon,
                        label: roleLabel,
                        color: roleColor,
                      ),
                      if (compact) _StatusPill(activo: active),
                      TextButton.icon(
                        onPressed: _eliminando ? null : _eliminar,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        icon: _eliminando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                        label: Text(_eliminando ? 'Eliminando…' : 'Eliminar'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RolePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool activo;

  const _StatusPill({required this.activo});

  @override
  Widget build(BuildContext context) {
    final color = activo ? AppColors.success : AppColors.error;
    final label = activo ? 'Activo' : 'Inactivo';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(32),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
