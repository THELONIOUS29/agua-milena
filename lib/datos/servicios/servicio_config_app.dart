import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../modelos/config_app.dart';

/// Servicio que consulta la configuración remota de la app.
/// Verifica mantenimiento y versión mínima requerida por plataforma.
class ServicioConfigApp {
  final _client = Supabase.instance.client;

  static const _esquema = 'inventario';
  static const _tabla = 'versiones_aplicacion';

  /// Obtiene la configuración actual desde Supabase según la plataforma.
  Future<ConfigApp> obtener() async {
    final plataforma = plataformaActual();

    try {
      final data = await _obtenerDesdeConfiguracion(plataforma);
      if (data == null) return ConfigApp(plataforma: plataforma);
      return ConfigApp.desdeJson(data);
    } catch (e) {
      debugPrint('Error al obtener configuración de app: $e');
      return ConfigApp(plataforma: plataforma);
    }
  }

  Future<Map<String, dynamic>?> _obtenerDesdeConfiguracion(
    String plataforma,
  ) async {
    try {
      return await _client
          .schema(_esquema)
          .from(_tabla)
          .select()
          .eq('plataforma', plataforma)
          .eq('activa', true)
          .maybeSingle();
    } catch (e) {
      debugPrint('No se pudo leer inventario.versiones_aplicacion: $e');
      return null;
    }
  }

  /// Verifica si la versión actual de la app es menor que la mínima requerida.
  Future<bool> requiereActualizacion() async {
    final config = await obtener();
    final packageInfo = await PackageInfo.fromPlatform();
    return requiereActualizar(packageInfo, config);
  }

  static bool requiereActualizar(PackageInfo packageInfo, ConfigApp config) {
    final compilacionInstalada = int.tryParse(packageInfo.buildNumber) ?? 0;

    if (compilacionInstalada > 0 && config.numeroCompilacionMinima > 0) {
      return compilacionInstalada < config.numeroCompilacionMinima;
    }

    return compararVersiones(packageInfo.version, config.versionMinima) < 0;
  }

  static String plataformaActual() {
    if (kIsWeb) return 'web';

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => defaultTargetPlatform.name,
    };
  }

  /// Compara dos versiones semánticas (ej: "1.0.0" vs "1.0.1").
  /// Retorna negativo si v1 < v2, 0 si son iguales, positivo si v1 > v2.
  static int compararVersiones(String v1, String v2) {
    final partes1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final partes2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final largo = partes1.length > partes2.length
        ? partes1.length
        : partes2.length;

    for (var i = 0; i < largo; i++) {
      final p1 = i < partes1.length ? partes1[i] : 0;
      final p2 = i < partes2.length ? partes2[i] : 0;
      if (p1 != p2) return p1 - p2;
    }

    return 0;
  }
}
