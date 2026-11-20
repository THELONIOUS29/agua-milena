import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/constantes/textos_app.dart';
import '../../proveedores/proveedor_autenticacion.dart';
import '../../componentes/fondo_agua_ambiental.dart';
import '../../componentes/tarjeta_app.dart';
import '../../componentes/logo_app.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const _loginAlertTone = Color(0xFFD45C4F);
  static const _loginAlertSurface = Color(0xFFFFF4F1);
  static const _loginAlertBorder = Color(0xFFFFD8D0);

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocusNode = FocusNode();

  bool _obscurePass = true;
  bool _isLoading = false;
  bool _canUseBiometrics = false;
  bool _isBiometricLoading = false;
  String? _errorMsg;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
    _loadBiometricAccess();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _passFocusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _mostrarErrorLogin(String mensaje) {
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    setState(() => _errorMsg = mensaje);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _loginAlertTone.withAlpha(24),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.info_outline_rounded,
                    color: _loginAlertTone,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    mensaje,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.surface(context),
            behavior: SnackBarBehavior.floating,
            elevation: 14,
            showCloseIcon: true,
            closeIconColor: AppColors.textSecondary(context),
            margin: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewPaddingOf(context).bottom + 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: _loginAlertBorder),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      _mostrarErrorLogin('Ingresa un correo y contrasena validos.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final success = await ref
          .read(proveedorNotificadorAuth.notifier)
          .loginConContrasena(
            email: _emailCtrl.text.trim().toLowerCase(),
            contrasena: _passCtrl.text,
          );
      if (!mounted) return;

      if (success) {
        context.go('/');
      } else {
        final state = ref.read(proveedorNotificadorAuth);
        _mostrarErrorLogin(state.error ?? AppStrings.loginError);
      }
    } catch (_) {
      if (mounted) {
        _mostrarErrorLogin(AppStrings.loginError);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadBiometricAccess() async {
    final authService = ref.read(proveedorServicioAuth);
    final storedUser = await authService.obtenerSesionAlmacenada();
    final canUse = storedUser != null && await authService.puedeUsarBiometria();
    if (!mounted) return;
    setState(() => _canUseBiometrics = canUse);
  }

  Future<void> _loginWithBiometrics() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isBiometricLoading = true;
      _errorMsg = null;
    });

    try {
      final success = await ref
          .read(proveedorNotificadorAuth.notifier)
          .validarBiometria();
      if (!mounted) return;
      if (success) {
        context.go('/');
      } else {
        final state = ref.read(proveedorNotificadorAuth);
        setState(
          () => _errorMsg = state.error ?? 'No se pudo validar la biometría.',
        );
      }
    } finally {
      if (mounted) setState(() => _isBiometricLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _LoginBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.primaryDark,
                                AppColors.primary,
                                AppColors.primaryLight,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withAlpha(34),
                                blurRadius: 32,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const LogoApp(size: 64, showWordmark: false),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Text(
                                  'Agua Milena',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        TarjetaApp(
                          padding: const EdgeInsets.all(24),
                          borderRadius: BorderRadius.circular(28),
                          child: AutofillGroup(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Iniciar sesión',
                                    style: GoogleFonts.inter(
                                      color: AppColors.textPrimary(context),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: _errorMsg == null
                                        ? const SizedBox(height: 22)
                                        : Padding(
                                            key: ValueKey(_errorMsg),
                                            padding: const EdgeInsets.only(
                                              top: 14,
                                              bottom: 18,
                                            ),
                                            child: _LoginErrorNotice(
                                              mensaje: _errorMsg!,
                                            ),
                                          ),
                                  ),
                                  TextFormField(
                                    controller: _emailCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [
                                      AutofillHints.username,
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: AppStrings.email,
                                      hintText: 'operador@aguamilena.com',
                                      prefixIcon: Icon(
                                        Icons.alternate_email_rounded,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Ingresa tu correo';
                                      }
                                      if (!value.contains('@')) {
                                        return 'Correo inválido';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passCtrl,
                                    focusNode: _passFocusNode,
                                    obscureText: _obscurePass,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    onFieldSubmitted: (_) =>
                                        _isLoading ? null : _login(),
                                    decoration: InputDecoration(
                                      labelText: AppStrings.password,
                                      hintText: 'Tu contraseña',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                      ),
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                        onPressed: () => setState(
                                          () => _obscurePass = !_obscurePass,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Ingresa tu contraseña';
                                      }
                                      if (value.length < 6) {
                                        return 'Mínimo 6 caracteres';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 22),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: _isLoading ? null : _login,
                                      icon: _isLoading
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.login_rounded),
                                      label: Text(
                                        _isLoading
                                            ? 'Ingresando...'
                                            : 'Ingresar',
                                      ),
                                    ),
                                  ),
                                  if (_canUseBiometrics) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isBiometricLoading
                                            ? null
                                            : _loginWithBiometrics,
                                        icon: _isBiometricLoading
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.fingerprint_rounded,
                                              ),
                                        label: const Text(
                                          'Ingresar con biometría',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginErrorNotice extends StatelessWidget {
  final String mensaje;

  const _LoginErrorNotice({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: mensaje,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _LoginScreenState._loginAlertSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _LoginScreenState._loginAlertBorder),
          boxShadow: [
            BoxShadow(
              color: _LoginScreenState._loginAlertTone.withAlpha(12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: _LoginScreenState._loginAlertTone,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                mensaje,
                style: GoogleFonts.inter(
                  color: _LoginScreenState._loginAlertTone,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: FondoAguaAmbiental(
        primary: AppColors.primary,
        secondary: AppColors.teal,
        accent: AppColors.accent,
        opacity: 1.15,
      ),
    );
  }
}
