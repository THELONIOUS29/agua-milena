import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../nucleo/constantes/colores_app.dart';

class FondoAguaAmbiental extends StatefulWidget {
  final Color primary;
  final Color secondary;
  final Color accent;
  final double opacity;

  const FondoAguaAmbiental({
    super.key,
    this.primary = AppColors.primary,
    this.secondary = AppColors.teal,
    this.accent = AppColors.accent,
    this.opacity = 1,
  });

  @override
  State<FondoAguaAmbiental> createState() => _FondoAguaAmbientalState();
}

class _FondoAguaAmbientalState extends State<FondoAguaAmbiental>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = MediaQuery.disableAnimationsOf(context);

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _AmbientWaterPainter(
                progress: disabled ? 0 : _controller.value,
                primary: widget.primary,
                secondary: widget.secondary,
                accent: widget.accent,
                opacity: widget.opacity,
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              size: Size.infinite,
            );
          },
        ),
      ),
    );
  }
}

class _AmbientWaterPainter extends CustomPainter {
  final double progress;
  final Color primary;
  final Color secondary;
  final Color accent;
  final double opacity;
  final bool isDark;

  const _AmbientWaterPainter({
    required this.progress,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.opacity,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress * math.pi * 2;
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF121620), const Color(0xFF1C2030)]
            : [const Color(0xFFF7F8FC), const Color(0xFFFFFFFF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, base);

    _drawWave(
      canvas,
      size,
      y: size.height * 0.10,
      height: size.height * 0.16,
      color: secondary.withAlpha((24 * opacity).round()),
      phase: phase,
      reverse: false,
    );
    _drawWave(
      canvas,
      size,
      y: size.height * 0.68,
      height: size.height * 0.18,
      color: primary.withAlpha((18 * opacity).round()),
      phase: phase * 0.8,
      reverse: true,
    );

    _drawRibbon(
      canvas,
      size,
      offset: Offset(size.width * 0.76, size.height * 0.08),
      color: accent.withAlpha((26 * opacity).round()),
      phase: phase,
      angle: -0.42,
    );
    _drawRibbon(
      canvas,
      size,
      offset: Offset(size.width * 0.16, size.height * 0.44),
      color: secondary.withAlpha((24 * opacity).round()),
      phase: phase + 1.4,
      angle: 0.35,
    );

    final droplets = <_DropSpec>[
      _DropSpec(0.12, 0.15, 18, primary),
      _DropSpec(0.86, 0.28, 24, secondary),
      _DropSpec(0.72, 0.78, 20, accent),
      _DropSpec(0.28, 0.82, 16, primary),
      _DropSpec(0.48, 0.34, 12, secondary),
    ];

    for (var i = 0; i < droplets.length; i++) {
      final spec = droplets[i];
      final bob = math.sin(phase + i) * 6;
      _drawDrop(
        canvas,
        center: Offset(size.width * spec.dx, size.height * spec.dy + bob),
        radius: spec.radius,
        color: spec.color.withAlpha((34 * opacity).round()),
      );
    }
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required double y,
    required double height,
    required Color color,
    required double phase,
    required bool reverse,
  }) {
    final path = Path()..moveTo(0, y);
    final direction = reverse ? -1 : 1;
    for (var x = 0.0; x <= size.width; x += size.width / 5) {
      final nextX = x + size.width / 5;
      final controlY =
          y +
          math.sin((x / size.width * math.pi * 2) + phase * direction) *
              height *
              0.24;
      path.quadraticBezierTo(x + size.width / 10, controlY, nextX, y);
    }
    path
      ..lineTo(size.width, y + height)
      ..lineTo(0, y + height * 0.55)
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawRibbon(
    Canvas canvas,
    Size size, {
    required Offset offset,
    required Color color,
    required double phase,
    required double angle,
  }) {
    final width = size.width * 0.46;
    final height = 34.0 + math.sin(phase) * 4;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.rotate(angle);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: width, height: height),
      const Radius.circular(999),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.restore();
  }

  void _drawDrop(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius * 1.3)
      ..cubicTo(
        center.dx + radius,
        center.dy - radius * 0.25,
        center.dx + radius * 0.82,
        center.dy + radius * 0.92,
        center.dx,
        center.dy + radius * 1.18,
      )
      ..cubicTo(
        center.dx - radius * 0.82,
        center.dy + radius * 0.92,
        center.dx - radius,
        center.dy - radius * 0.25,
        center.dx,
        center.dy - radius * 1.3,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AmbientWaterPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.accent != accent ||
        oldDelegate.opacity != opacity ||
        oldDelegate.isDark != isDark;
  }
}

class _DropSpec {
  final double dx;
  final double dy;
  final double radius;
  final Color color;

  const _DropSpec(this.dx, this.dy, this.radius, this.color);
}
