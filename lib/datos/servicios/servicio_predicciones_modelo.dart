import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServicioPrediccionesModelo {
  static const _esquema = 'inventario';
  static const _tabla = 'predicciones_modelo_alertas';
  static const _columnas = [
    'clave',
    'tipo',
    'fecha_objetivo',
    'periodo_inicio',
    'periodo_fin',
    'titulo',
    'cuerpo',
    'demanda_bidones',
    'demanda_fundas',
    'carga_bidones',
    'carga_fundas',
    'riesgo_stock_bajo',
    'venta_alta_inesperada',
    'dia_pico',
    'temporada_nombre',
    'dias_restantes',
    'modelo_nombre',
    'origen',
    'actualizado_en',
  ];

  final _client = Supabase.instance.client;

  Future<void> guardarPredicciones(List<Map<String, dynamic>> filas) async {
    if (filas.isEmpty) return;

    try {
      final normalizadas = _normalizarFilas(filas);
      final actualizables = normalizadas
          .where((fila) => _sePuedeActualizar(fila['tipo'] as String?))
          .toList();
      final fijas = normalizadas
          .where((fila) => !_sePuedeActualizar(fila['tipo'] as String?))
          .toList();

      if (actualizables.isNotEmpty) {
        await _client
            .schema(_esquema)
            .from(_tabla)
            .upsert(actualizables, onConflict: 'clave');
      }

      final nuevasFijas = await _filtrarFijasNuevas(fijas);
      if (nuevasFijas.isNotEmpty) {
        await _client.schema(_esquema).from(_tabla).insert(nuevasFijas);
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudieron guardar predicciones TFLite: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  List<Map<String, dynamic>> _normalizarFilas(
    List<Map<String, dynamic>> filas,
  ) {
    return filas.map((fila) {
      return {for (final columna in _columnas) columna: fila[columna]};
    }).toList();
  }

  bool _sePuedeActualizar(String? tipo) {
    return tipo == 'diaria' ||
        tipo == 'temporada_mes' ||
        tipo == 'temporada_semana' ||
        tipo == 'temporada_dia';
  }

  Future<List<Map<String, dynamic>>> _filtrarFijasNuevas(
    List<Map<String, dynamic>> filas,
  ) async {
    if (filas.isEmpty) return const [];
    final tipos = filas
        .map((fila) => fila['tipo']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    final fechas = filas
        .map((fila) => fila['fecha_objetivo']?.toString())
        .whereType<String>()
        .toSet()
        .toList();
    if (tipos.isEmpty || fechas.isEmpty) return filas;

    final existentes = await _client
        .schema(_esquema)
        .from(_tabla)
        .select('tipo,fecha_objetivo,origen')
        .inFilter('tipo', tipos)
        .inFilter('fecha_objetivo', fechas)
        .eq('origen', 'tflite');
    final periodosExistentes = (existentes as List)
        .map((fila) => _llavePeriodo(fila as Map))
        .whereType<String>()
        .toSet();
    return filas
        .where((fila) => !periodosExistentes.contains(_llavePeriodo(fila)))
        .toList();
  }

  String? _llavePeriodo(Map<dynamic, dynamic> fila) {
    final tipo = fila['tipo']?.toString();
    final fecha = fila['fecha_objetivo']?.toString();
    final origen = fila['origen']?.toString() ?? 'tflite';
    if (tipo == null || fecha == null) return null;
    return '$origen|$tipo|$fecha';
  }
}
