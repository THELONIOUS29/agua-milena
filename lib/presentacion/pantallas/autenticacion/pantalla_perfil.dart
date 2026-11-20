import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../datos/servicios/servicio_usuario.dart';
import '../../../dominio/entidades/rol_usuario.dart';
import '../../proveedores/proveedor_autenticacion.dart';
import '../../componentes/tarjeta_app.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  Uint8List? _avatarPendienteBytes;
  String? _avatarPendienteExtension;

  @override
  void initState() {
    super.initState();
    final user = ref.read(proveedorNotificadorAuth).usuario;
    if (user != null) {
      _hydrateForm(user);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _hydrateForm(UsuarioApp user) {
    _nameCtrl.text = user.nombre;
    _phoneCtrl.text = user.telefono ?? '';
  }

  void _showFeedback(String message, {required bool isError}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isError ? AppColors.error : AppColors.success,
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 88,
    );
    if (image == null) return;

    HapticFeedback.lightImpact();

    try {
      final bytes = await image.readAsBytes();
      final fileExt = image.name.contains('.')
          ? image.name.split('.').last.toLowerCase()
          : 'jpg';

      setState(() {
        _avatarPendienteBytes = bytes;
        _avatarPendienteExtension = fileExt;
      });

      _showFeedback(
        'Foto seleccionada. Toca Guardar cambios para actualizar tu perfil.',
        isError: false,
      );
    } catch (_) {
      _showFeedback('No se pudo leer la foto seleccionada.', isError: true);
    }
  }

  Future<String> _subirAvatar({
    required UsuarioApp user,
    required Uint8List bytes,
    required String extension,
  }) async {
    setState(() => _isUploadingAvatar = true);
    try {
      final fileName =
          '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final path = 'avatars/$fileName';

      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      return Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(proveedorNotificadorAuth).usuario;
    if (user == null) return;

    HapticFeedback.lightImpact();
    setState(() => _isSaving = true);

    try {
      final rawPhone = _phoneCtrl.text.trim();
      var avatarUrl = user.urlAvatar;

      if (_avatarPendienteBytes != null) {
        avatarUrl = await _subirAvatar(
          user: user,
          bytes: _avatarPendienteBytes!,
          extension: _avatarPendienteExtension ?? 'jpg',
        );
      }

      final updatedUser = await ServicioUsuario().actualizar(
        user.id,
        nombre: _nameCtrl.text.trim(),
        email: user.email,
        rol: user.rol.name,
        activo: true,
        telefono: rawPhone.isEmpty ? '' : rawPhone,
        urlAvatar: avatarUrl,
      );

      await ref
          .read(proveedorNotificadorAuth.notifier)
          .sincronizarUsuarioDesdeJson(updatedUser);

      if (mounted) {
        setState(() {
          _avatarPendienteBytes = null;
          _avatarPendienteExtension = null;
        });
      }

      _showFeedback('Tus cambios se guardaron con éxito.', isError: false);
    } catch (e) {
      _showFeedback(
        'No se pudieron guardar los cambios del perfil.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _logout() async {
    HapticFeedback.lightImpact();
    await ref.read(proveedorNotificadorAuth.notifier).cerrarSesion();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(proveedorNotificadorAuth).usuario;
    if (user == null) {
      return const Scaffold();
    }

    final firstName = user.nombre.trim().split(' ').first;
    final phoneLabel = (user.telefono == null || user.telefono!.trim().isEmpty)
        ? 'Sin teléfono'
        : user.telefono!;

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: Stack(
        children: [
          Positioned(
            top: -80,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accent.withAlpha(55),
                    AppColors.accent.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 100,
            left: -60,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.teal.withAlpha(55),
                    AppColors.teal.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              32 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary,
                        AppColors.primaryLight,
                        AppColors.teal.withAlpha(220),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withAlpha(36),
                        blurRadius: 28,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 360;

                          return Flex(
                            direction: compact
                                ? Axis.vertical
                                : Axis.horizontal,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ProfileAvatar(
                                avatarUrl: user.urlAvatar,
                                previewBytes: _avatarPendienteBytes,
                                isUploadingAvatar: _isUploadingAvatar,
                                onTap: _isSaving || _isUploadingAvatar
                                    ? null
                                    : _pickAvatar,
                              ),
                              SizedBox(
                                width: compact ? 0 : 16,
                                height: compact ? 14 : 0,
                              ),
                              Expanded(
                                flex: compact ? 0 : 1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Hola, $firstName',
                                      style: GoogleFonts.inter(
                                        color: Colors.white.withAlpha(220),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      user.nombre,
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: compact ? 22 : 24,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _HeroPill(
                                          icon: Icons.badge_rounded,
                                          label: user.rol.name.toUpperCase(),
                                        ),
                                        _HeroPill(
                                          icon: Icons.phone_rounded,
                                          label: phoneLabel,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TarjetaApp(
                  padding: const EdgeInsets.all(20),
                  borderRadius: BorderRadius.circular(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Datos personales',
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Edita tu nombre, teléfono y foto de perfil.',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary(context),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _nameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu nombre completo';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Teléfono',
                            prefixIcon: Icon(Icons.phone_rounded),
                            hintText: 'Ej. TELEFONO_DE_EJEMPLO',
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        _ReadOnlyField(
                          label: 'Correo electrónico',
                          value: user.email,
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 16),
                        _ReadOnlyField(
                          label: 'Rol en el sistema',
                          value: user.rol.name.toUpperCase(),
                          icon: Icons.verified_user_outlined,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _save,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(
                              _isSaving ? 'Guardando...' : 'Guardar cambios',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.push('/change-password?from=profile');
                    },
                    icon: const Icon(Icons.lock_reset_rounded),
                    label: const Text('Cambiar contraseña'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.error,
                    ),
                    label: const Text(
                      'Cerrar sesión',
                      style: TextStyle(color: AppColors.error),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String? avatarUrl;
  final Uint8List? previewBytes;
  final bool isUploadingAvatar;
  final VoidCallback? onTap;

  const _ProfileAvatar({
    required this.avatarUrl,
    required this.previewBytes,
    required this.isUploadingAvatar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ImageProvider<Object>? imageProvider = previewBytes != null
        ? MemoryImage(previewBytes!)
        : (avatarUrl != null && avatarUrl!.trim().isNotEmpty
              ? NetworkImage(avatarUrl!)
              : null);

    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(28),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withAlpha(90), width: 2),
            image: imageProvider != null
                ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
                : null,
          ),
          child: imageProvider == null
              ? const Icon(Icons.person_rounded, size: 44, color: Colors.white)
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: isUploadingAvatar
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        filled: true,
        fillColor: AppColors.surfaceVariant(context),
      ),
    );
  }
}
