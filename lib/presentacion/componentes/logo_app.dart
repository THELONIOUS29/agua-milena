import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../nucleo/constantes/colores_app.dart';

/// Logo moderno de Agua Milena.
/// Gota de agua en círculo con degradado azul, sin animaciones de órbitas.
class LogoApp extends StatefulWidget {
  final double size;
  final bool showWordmark;
  final String? caption;

  const LogoApp({
    super.key,
    this.size = 120,
    this.showWordmark = false,
    this.caption,
  });

  @override
  State<LogoApp> createState() => _LogoAppState();
}

class _LogoAppState extends State<LogoApp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logo = FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withAlpha(40),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.water_drop_rounded,
              size: widget.size * 0.42,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );

    if (!widget.showWordmark) return logo;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          logo,
          const SizedBox(height: 20),
          Text(
            'Agua Milena',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontSize: widget.size * 0.18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (widget.caption != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.caption!,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary(context),
                fontSize: widget.size * 0.09,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
