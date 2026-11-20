import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../datos/servicios/servicio_autenticacion.dart';
import '../../../datos/servicios/servicio_usuario.dart';
import '../../../datos/modelos/vendedor.dart';
import '../../proveedores/proveedor_vendedor.dart';
import '../../proveedores/proveedor_usuario.dart';

enum _SellerProfileMode { autoCreate, linkExisting }

class UserFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? user;
  final bool crearVendedor;

  const UserFormScreen({super.key, this.user, this.crearVendedor = false});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String _role = 'planta';
  bool _active = true;
  String? _sellerId;
  bool _isLoading = false;
  bool _vinculando = false;
  _SellerProfileMode _sellerProfileMode = _SellerProfileMode.autoCreate;

  bool get _isVendorRole => _role == 'vendedor';

  @override
  void initState() {
    super.initState();
    if (widget.crearVendedor) _role = 'vendedor';
    if (widget.user == null) return;

    _nameCtrl.text = (widget.user!['name'] ?? widget.user!['nombre'] ?? '')
        .toString();
    _emailCtrl.text = (widget.user!['email'] ?? '').toString();
    _phoneCtrl.text = (widget.user!['phone'] ?? widget.user!['telefono'] ?? '')
        .toString();
    _role = (widget.user!['role'] ?? widget.user!['rol'] ?? 'planta')
        .toString();
    _active =
        (widget.user!['active'] ?? widget.user!['activo'] ?? true) as bool;
    _sellerId =
        (widget.user!['seller_id'] ?? widget.user!['vendedor_id']) as String?;
    if (_sellerId != null) {
      _sellerProfileMode = _SellerProfileMode.linkExisting;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_vinculando || _isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    if (_isVendorRole &&
        _sellerProfileMode == _SellerProfileMode.linkExisting &&
        _sellerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un perfil de vendedor para vincular.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    String? createdSellerId;

    try {
      final userService = ServicioUsuario();
      final authService = ServicioAutenticacion();
      if (widget.user == null || _passwordCtrl.text.isNotEmpty) {
        _validarContrasenaSegura(authService, _passwordCtrl.text);
      }
      final trimmedPhone = _phoneCtrl.text.trim();
      String? resolvedSellerId = _sellerId;

      if (_isVendorRole &&
          _sellerProfileMode == _SellerProfileMode.autoCreate) {
        final createdSeller = await ref
            .read(proveedorNotificadorVendedor.notifier)
            .crear(
              _nameCtrl.text.trim(),
              trimmedPhone.isEmpty ? null : trimmedPhone,
            );
        createdSellerId = createdSeller.id;
        resolvedSellerId = createdSeller.id;
      }

      if (widget.user == null) {
        final hash = authService.hashContrasena(_passwordCtrl.text);
        await userService.crear(
          email: _emailCtrl.text.trim().toLowerCase(),
          nombre: _nameCtrl.text.trim(),
          hashContrasena: hash,
          rol: _role,
          vendedorId: resolvedSellerId,
          telefono: trimmedPhone,
        );
      } else {
        String? newHash;
        if (_passwordCtrl.text.isNotEmpty) {
          newHash = authService.hashContrasena(_passwordCtrl.text);
        }

        await userService.actualizar(
          widget.user!['id'],
          nombre: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim().toLowerCase(),
          hashContrasena: newHash,
          rol: _role,
          activo: _active,
          vendedorId: _isVendorRole ? resolvedSellerId : null,
          debeCambiarContrasena: newHash != null ? true : null,
          telefono: trimmedPhone,
        );
      }

      ref.invalidate(proveedorUsuarios);
      if (mounted) context.pop();
    } catch (e) {
      if (createdSellerId != null) {
        try {
          await ref
              .read(proveedorNotificadorVendedor.notifier)
              .eliminar(createdSellerId);
        } catch (_) {}
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _seleccionarVendedor(String? sellerId) async {
    if (sellerId == null || _vinculando) return;
    setState(() => _vinculando = true);
    try {
      final usuarios = await ref.read(proveedorUsuarios.future);
      if (!mounted) return;
      final vinculados = usuarios.where(
        (u) => (u['seller_id'] ?? u['vendedor_id']) == sellerId,
      );
      if (vinculados.isNotEmpty &&
          vinculados.first['id'] != widget.user?['id']) {
        if (widget.user == null) {
          context.pushReplacement(
            '/users/edit/${vinculados.first['id']}',
            extra: vinculados.first,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este vendedor ya tiene una cuenta. Edítala desde Gestión de usuarios.',
              ),
            ),
          );
        }
        return;
      }
      final vendedor = ref
          .read(proveedorNotificadorVendedor)
          .asData!
          .value
          .firstWhere((v) => v.id == sellerId);
      setState(() {
        _sellerId = sellerId;
        _nameCtrl.text = vendedor.nombre;
        _phoneCtrl.text = vendedor.telefono ?? '';
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudieron cargar los datos del vendedor. Inténtalo nuevamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _vinculando = false);
    }
  }

  void _validarContrasenaSegura(
    ServicioAutenticacion authService,
    String contrasena,
  ) {
    if (!authService.esContrasenaValida(contrasena)) {
      throw Exception(
        'La contraseña debe tener al menos 8 caracteres, un número y un carácter especial',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellersAsync = ref.watch(proveedorNotificadorVendedor);
    final isEdit = widget.user != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Editar Usuario' : 'Nuevo Usuario')),
      body: _isLoading || _vinculando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  24 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(Icons.person_rounded),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          helperText:
                              'Este correo será el usuario para iniciar sesión.',
                          prefixIcon: Icon(Icons.email_rounded),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Requerido';
                          }
                          if (!value.contains('@')) return 'Correo inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          prefixIcon: Icon(Icons.phone_rounded),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordCtrl,
                        decoration: InputDecoration(
                          labelText: isEdit
                              ? 'Contraseña (dejar en blanco para mantener)'
                              : 'Contraseña temporal',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          helperText:
                              'El usuario deberá cambiarla al iniciar sesión.',
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (!isEdit && (value == null || value.isEmpty)) {
                            return 'La contraseña es requerida al crear usuario';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        initialValue: _role,
                        decoration: const InputDecoration(
                          labelText: 'Rol del usuario',
                          prefixIcon: Icon(Icons.badge_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Administrador'),
                          ),
                          DropdownMenuItem(
                            value: 'planta',
                            child: Text('Planta (Producción/Caja)'),
                          ),
                          DropdownMenuItem(
                            value: 'vendedor',
                            child: Text('Vendedor en despacho'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _role = value!;
                            if (!_isVendorRole) {
                              _sellerId = null;
                              _sellerProfileMode =
                                  _SellerProfileMode.autoCreate;
                            }
                          });
                        },
                      ),
                      if (_isVendorRole) ...[
                        const SizedBox(height: 20),
                        _SellerProfileSection(
                          mode: _sellerProfileMode,
                          onModeChanged: (mode) {
                            setState(() {
                              _sellerProfileMode = mode;
                              if (mode == _SellerProfileMode.autoCreate) {
                                _sellerId = null;
                              }
                            });
                          },
                          sellersAsync: sellersAsync,
                          selectedSellerId: _sellerId,
                          onSellerChanged: (sellerId) {
                            _seleccionarVendedor(sellerId);
                          },
                        ),
                        if (_vinculando) const LinearProgressIndicator(),
                        if (_sellerProfileMode ==
                            _SellerProfileMode.linkExisting)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Se completan el nombre y teléfono guardados. Si el vendedor aún no tiene cuenta, registra su correo y contraseña temporal. Si ya tiene acceso, se abrirá su cuenta para editarla.',
                            ),
                          ),
                      ],
                      if (isEdit &&
                          widget.user!['email'] != 'admin@aguamilena.com') ...[
                        const SizedBox(height: 24),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Usuario activo',
                            style: GoogleFonts.inter(),
                          ),
                          subtitle: const Text(
                            'Si se inactiva, no podrá ingresar al sistema.',
                          ),
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                          activeThumbColor: AppColors.primaryLight,
                        ),
                      ],
                      const SizedBox(height: 32),
                      FilledButton(
                        onPressed: _vinculando ? null : _save,
                        child: Text(
                          _isVendorRole &&
                                  _sellerProfileMode ==
                                      _SellerProfileMode.autoCreate
                              ? 'Guardar y crear perfil'
                              : 'Guardar usuario',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SellerProfileSection extends StatelessWidget {
  final _SellerProfileMode mode;
  final ValueChanged<_SellerProfileMode> onModeChanged;
  final AsyncValue<List<Vendedor>> sellersAsync;
  final String? selectedSellerId;
  final ValueChanged<String?> onSellerChanged;

  const _SellerProfileSection({
    required this.mode,
    required this.onModeChanged,
    required this.sellersAsync,
    required this.selectedSellerId,
    required this.onSellerChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Perfil del vendedor',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Puedes crearlo automáticamente al guardar o vincular uno existente.',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 420) {
                return SegmentedButton<_SellerProfileMode>(
                  segments: const [
                    ButtonSegment<_SellerProfileMode>(
                      value: _SellerProfileMode.autoCreate,
                      icon: Icon(Icons.auto_awesome_rounded),
                      label: Text('Crear automático'),
                    ),
                    ButtonSegment<_SellerProfileMode>(
                      value: _SellerProfileMode.linkExisting,
                      icon: Icon(Icons.link_rounded),
                      label: Text('Vincular existente'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) =>
                      onModeChanged(selection.first),
                );
              }

              return Column(
                children: [
                  _SellerModeTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Crear automático',
                    subtitle:
                        'Genera el perfil del vendedor al guardar el usuario.',
                    selected: mode == _SellerProfileMode.autoCreate,
                    onTap: () => onModeChanged(_SellerProfileMode.autoCreate),
                  ),
                  const SizedBox(height: 10),
                  _SellerModeTile(
                    icon: Icons.link_rounded,
                    title: 'Vincular existente',
                    subtitle: 'Asocia el usuario a un vendedor que ya existe.',
                    selected: mode == _SellerProfileMode.linkExisting,
                    onTap: () => onModeChanged(_SellerProfileMode.linkExisting),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (mode == _SellerProfileMode.autoCreate)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Al guardar, se crea el perfil del vendedor usando el mismo nombre y tel\u00e9fono.',
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary(context),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            sellersAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Error cargando vendedores: $err'),
              data: (sellers) {
                final validSellers = sellers
                    .where((v) => v.activo && !v.esDistribuidora)
                    .toList();

                return DropdownButtonFormField<String>(
                  key: ValueKey(selectedSellerId),
                  initialValue: selectedSellerId,
                  decoration: const InputDecoration(
                    labelText: 'Asociar a un perfil de vendedor',
                    prefixIcon: Icon(Icons.airport_shuttle_rounded),
                  ),
                  items: validSellers
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.id,
                          child: Text(
                            v.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: onSellerChanged,
                  validator: (value) =>
                      value == null ? 'Vendedor requerido' : null,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SellerModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SellerModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primary
        : AppColors.border(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withAlpha(18)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? AppColors.primary
                  : AppColors.textSecondary(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? AppColors.primary : AppColors.textHint(context),
            ),
          ],
        ),
      ),
    );
  }
}
