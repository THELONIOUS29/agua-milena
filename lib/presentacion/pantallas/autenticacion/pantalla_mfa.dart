import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../nucleo/constantes/colores_app.dart';
import '../../../presentacion/proveedores/proveedor_autenticacion.dart';

class MfaScreen extends ConsumerStatefulWidget {
  const MfaScreen({super.key});

  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen>
    with SingleTickerProviderStateMixin {
  bool _isTrying = false;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptBiometrics();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _promptBiometrics() async {
    if (_isTrying) return;
    setState(() => _isTrying = true);
    HapticFeedback.mediumImpact();

    final success = await ref
        .read(proveedorNotificadorAuth.notifier)
        .validarBiometria();

    if (mounted) {
      if (success) {
        context.go('/');
      } else {
        setState(() => _isTrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(proveedorNotificadorAuth);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withAlpha(40),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      size: 50,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verificación de Identidad',
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary(context),
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Valida tu identidad para acceder a la aplicación.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary(context),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 48),
                  if (authState.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.error.withAlpha(40),
                          ),
                        ),
                        child: Text(
                          authState.error!,
                          style: GoogleFonts.inter(
                            color: AppColors.error,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isTrying ? null : _promptBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(
                        'Usar Biometría',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        await ref
                            .read(proveedorNotificadorAuth.notifier)
                            .cerrarSesion();
                        if (context.mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.password_rounded),
                      label: Text(
                        'Usar Contraseña',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
