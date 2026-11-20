import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../nucleo/constantes/colores_app.dart';

class TarjetaApp extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final Color? color;
  final Border? border;

  const TarjetaApp({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        color ?? (isDark ? AppColors.cardDark : AppColors.cardLight);
    final effectiveBorder =
        border ??
        Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 0.5,
        );

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: radius,
        border: effectiveBorder,
        boxShadow: isDark
            ? null
            : [
                const BoxShadow(
                  color: AppColors.shadowColor,
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    if (onTap == null) {
      return RepaintBoundary(child: content);
    }

    return RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap?.call();
          },
          child: content,
        ),
      ),
    );
  }
}
