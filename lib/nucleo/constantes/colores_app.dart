import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ─── Paleta principal — diseño moderno y cálido ───────────────────
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryLight = Color(0xFF2D5F8A);
  static const Color primaryDark = Color(0xFF142A45);
  static const Color accent = Color(0xFFFF6B6B);
  static const Color accentSoft = Color(0xFFFF8E8E);
  static const Color teal = Color(0xFF2EC4B6);
  static const Color tealLight = Color(0xFF5DD9CD);

  // ─── Fondos (Light) ───────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF7F8FC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF0F2F8);
  static const Color cardLight = Color(0xFFFFFFFF);

  // ─── Fondos (Dark) ────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF121620);
  static const Color surfaceDark = Color(0xFF1C2030);
  static const Color surfaceVariantDark = Color(0xFF252A3A);
  static const Color cardDark = Color(0xFF1E2235);

  // ─── Texto (Light) ───────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF1A1D2E);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textHintLight = Color(0xFF9CA3AF);

  // ─── Texto (Dark) ────────────────────────────────────────────────
  static const Color textPrimaryDark = Color(0xFFF1F3F9);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);
  static const Color textHintDark = Color(0xFF6B7280);

  // ─── Bordes y sombras ─────────────────────────────────────────────
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderDark = Color(0xFF2D3348);
  static const Color shadowColor = Color(0x0F1A1D2E);

  // ─── Estados ──────────────────────────────────────────────────────
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // ─── Indicadores de stock ─────────────────────────────────────────
  static const Color stockOk = Color(0xFF22C55E);
  static const Color stockWarning = Color(0xFFF59E0B);
  static const Color stockCritical = Color(0xFFEF4444);

  // ─── Gradientes ───────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8A)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E8E)],
  );

  static const LinearGradient tealGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2EC4B6), Color(0xFF5DD9CD)],
  );

  static const LinearGradient splashGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8A), Color(0xFFF7F8FC)],
  );

  static const LinearGradient heroGradientLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x141E3A5F), Color(0x0A2EC4B6)],
  );

  static const LinearGradient heroGradientDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x331E3A5F), Color(0x222EC4B6)],
  );

  // ─── Helpers contextuales ─────────────────────────────────────────
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? backgroundDark
      : backgroundLight;

  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? surfaceDark
      : surfaceLight;

  static Color surfaceVariant(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? surfaceVariantDark
      : surfaceVariantLight;

  static Color card(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? cardDark : cardLight;

  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? textPrimaryDark
      : textPrimaryLight;

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? textSecondaryDark
      : textSecondaryLight;

  static Color textHint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? textHintDark
      : textHintLight;

  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? borderDark
      : borderLight;

  static LinearGradient heroGradient(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? heroGradientDark
      : heroGradientLight;
}
