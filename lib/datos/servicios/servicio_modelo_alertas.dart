import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ejecutor_tflite.dart';
import 'servicio_predicciones_modelo.dart';

import '../modelos/producto.dart';
import '../modelos/ruta.dart';
import '../modelos/venta.dart';

class PrediccionModeloAlertas {
  final int demandaBidones;
  final int demandaFundas;
  final int demandaTotalUnidades;
  final int cargaRecomendadaBidones;
  final int cargaRecomendadaFundas;
  final double probabilidadStockBajo;
  final double probabilidadVentaAltaInesperada;

  const PrediccionModeloAlertas({
    required this.demandaBidones,
    required this.demandaFundas,
    required this.demandaTotalUnidades,
    required this.cargaRecomendadaBidones,
    required this.cargaRecomendadaFundas,
    required this.probabilidadStockBajo,
    required this.probabilidadVentaAltaInesperada,
  });
}

class PrediccionPeriodoAlertas {
  final String etiqueta;
  final DateTime desde;
  final DateTime hasta;
  final DateTime diaPico;
  final int demandaBidones;
  final int demandaFundas;
  final int cargaRecomendadaBidones;
  final int cargaRecomendadaFundas;
  final double probabilidadStockBajoMaxima;
  final double probabilidadVentaAltaMaxima;

  const PrediccionPeriodoAlertas({
    required this.etiqueta,
    required this.desde,
    required this.hasta,
    required this.diaPico,
    required this.demandaBidones,
    required this.demandaFundas,
    required this.cargaRecomendadaBidones,
    required this.cargaRecomendadaFundas,
    required this.probabilidadStockBajoMaxima,
    required this.probabilidadVentaAltaMaxima,
  });
}

class TemporadaVentasFuerte {
  final String nombre;
  final DateTime inicio;
  final int diasRestantes;
  final String explicacion;

  const TemporadaVentasFuerte({
    required this.nombre,
    required this.inicio,
    required this.diasRestantes,
    required this.explicacion,
  });
}

class EstadoModeloAlertas {
  final String nombre;
  final List<String> entradas;
  final List<String> salidas;
  final PrediccionModeloAlertas? prediccion;
  final PrediccionPeriodoAlertas? prediccionSemana;
  final PrediccionPeriodoAlertas? prediccionMes;
  final TemporadaVentasFuerte? temporadaProxima;

  const EstadoModeloAlertas({
    required this.nombre,
    required this.entradas,
    required this.salidas,
    this.prediccion,
    this.prediccionSemana,
    this.prediccionMes,
    this.temporadaProxima,
  });
}

class ServicioModeloAlertas {
  final Future<ResultadoInferenciaML?> Function({
    required String rutaModelo,
    required List<double> entradaNormalizada,
  })
  _inferir;

  ServicioModeloAlertas({
    Future<ResultadoInferenciaML?> Function({
      required String rutaModelo,
      required List<double> entradaNormalizada,
    })?
    inferir,
  }) : _inferir = inferir ?? ejecutarInferenciaML;
  static const _rutaModelo = 'assets/modelos/modelo_alertas_agua_milena.tflite';
  static const _rutaMetadatos =
      'assets/modelos/metadatos_alertas_agua_milena.json';

  Future<EstadoModeloAlertas> cargar() async {
    return predecir(productos: const [], rutas: const [], ventas: const []);
  }

  Future<EstadoModeloAlertas> predecir({
    required List<Producto> productos,
    required List<Ruta> rutas,
    required List<Venta> ventas,
    DateTime? fecha,
  }) async {
    try {
      final metadatosTexto = await rootBundle.loadString(_rutaMetadatos);
      final metadatos = jsonDecode(metadatosTexto) as Map<String, dynamic>;
      final fechaBase = fecha ?? DateTime.now();

      // Intentar ejecutar el modelo ML (solo disponible en móvil)
      final resultado = await _intentarPrediccionML(
        metadatos: metadatos,
        productos: productos,
        rutas: rutas,
        ventas: ventas,
        fecha: fechaBase,
      );

      if (resultado != null) {
        // Modelo ML disponible — usar predicciones del modelo
        final respaldoDiario = _prediccionEstadistica(
          productos: productos,
          ventas: ventas,
          fecha: fechaBase,
        );
        final prediccionSemana = await _ejecutarPrediccionPeriodoML(
          metadatos: metadatos,
          productos: productos,
          rutas: rutas,
          ventas: ventas,
          fechaInicio: fechaBase,
          dias: 7,
          etiqueta: 'Próximos 7 días',
        );
        final prediccionMes = await _ejecutarPrediccionPeriodoML(
          metadatos: metadatos,
          productos: productos,
          rutas: rutas,
          ventas: ventas,
          fechaInicio: fechaBase,
          dias: 30,
          etiqueta: 'Próximos 30 días',
        );

        final estado = EstadoModeloAlertas(
          nombre: metadatos['nombre_modelo'] as String? ?? 'Modelo de alertas',
          entradas: resultado.entradas,
          salidas: resultado.salidas,
          prediccion: calibrarPrediccionDiaria(
            prediccion: resultado.prediccion,
            respaldo: respaldoDiario,
            semana: prediccionSemana,
          ),
          prediccionSemana: prediccionSemana,
          prediccionMes: prediccionMes,
          temporadaProxima: _temporadaProxima(fechaBase),
        );
        if (productos.isNotEmpty || rutas.isNotEmpty || ventas.isNotEmpty) {
          await _guardarPrediccionesTflite(
            estado: estado,
            metadatos: metadatos,
            productos: productos,
            rutas: rutas,
            ventas: ventas,
            fecha: fechaBase,
          );
        }
        return estado;
      }

      // Fallback estadístico (web o modelo no disponible)
      final fallback = _prediccionEstadistica(
        productos: productos,
        ventas: ventas,
        fecha: fechaBase,
      );
      return EstadoModeloAlertas(
        nombre: 'Estimación estadística',
        entradas: const ['Datos históricos'],
        salidas: const ['Estimación basada en promedios'],
        prediccion: fallback,
        temporadaProxima: _temporadaProxima(fechaBase),
      );
    } catch (error, stackTrace) {
      debugPrint('Error al cargar modelo de alertas: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> _guardarPrediccionesTflite({
    required EstadoModeloAlertas estado,
    required Map<String, dynamic> metadatos,
    required List<Producto> productos,
    required List<Ruta> rutas,
    required List<Venta> ventas,
    required DateTime fecha,
  }) async {
    final filas = await construirFilasPrediccionesTflite(
      estado: estado,
      fecha: fecha,
      construirSemana: (inicio) => _ejecutarPrediccionPeriodoML(
        metadatos: metadatos,
        productos: productos,
        rutas: rutas,
        ventas: ventas,
        fechaInicio: inicio,
        dias: 7,
        etiqueta: 'Próximos 7 días',
      ),
      construirMes: (inicio) => _ejecutarPrediccionPeriodoML(
        metadatos: metadatos,
        productos: productos,
        rutas: rutas,
        ventas: ventas,
        fechaInicio: inicio,
        dias: 30,
        etiqueta: 'Próximos 30 días',
      ),
    );
    await ServicioPrediccionesModelo().guardarPredicciones(filas);
  }

  @visibleForTesting
  Future<List<Map<String, dynamic>>> construirFilasPrediccionesTflite({
    required EstadoModeloAlertas estado,
    required DateTime fecha,
    Future<PrediccionPeriodoAlertas> Function(DateTime inicio)? construirSemana,
    Future<PrediccionPeriodoAlertas> Function(DateTime inicio)? construirMes,
  }) async {
    final filas = <Map<String, dynamic>>[];
    final fechaBase = DateTime(fecha.year, fecha.month, fecha.day);
    final prediccion = estado.prediccion;
    if (prediccion != null) {
      filas.add(_filaDiaria(prediccion, estado.nombre, fechaBase));
    }

    final semanaActualInicio = _inicioSemana(fechaBase);
    final proximaSemanaInicio = semanaActualInicio.add(const Duration(days: 7));
    for (final inicio in [semanaActualInicio, proximaSemanaInicio]) {
      final semana = _periodoCoincide(estado.prediccionSemana, inicio)
          ? estado.prediccionSemana!
          : construirSemana == null
          ? null
          : await construirSemana(inicio);
      if (semana != null) {
        filas.add(_filaSemanal(semana, estado.nombre));
      }
    }

    final mesActualInicio = DateTime(fechaBase.year, fechaBase.month);
    final proximoMesInicio = DateTime(fechaBase.year, fechaBase.month + 1);
    for (final inicio in [mesActualInicio, proximoMesInicio]) {
      final mes = _periodoCoincide(estado.prediccionMes, inicio)
          ? estado.prediccionMes!
          : construirMes == null
          ? null
          : await construirMes(inicio);
      if (mes != null) {
        filas.add(_filaMensual(mes, estado.nombre));
      }
    }

    final temporada = estado.temporadaProxima;
    if (temporada != null) {
      filas.addAll(_filasTemporada(temporada, estado.nombre));
    }

    return filas;
  }

  Map<String, dynamic> _filaDiaria(
    PrediccionModeloAlertas prediccion,
    String modeloNombre,
    DateTime fecha,
  ) {
    return {
      'clave': 'diaria_${_fechaSql(fecha)}',
      'tipo': 'diaria',
      'fecha_objetivo': _fechaSql(fecha),
      'periodo_inicio': _fechaSql(fecha),
      'periodo_fin': _fechaSql(fecha),
      'titulo': 'Prediccion de hoy',
      'cuerpo':
          'Venta esperada: ${prediccion.demandaBidones} bidones y ${prediccion.demandaFundas} fundas. Preparacion sugerida: ${prediccion.cargaRecomendadaBidones} bidones y ${prediccion.cargaRecomendadaFundas} fundas.',
      'demanda_bidones': prediccion.demandaBidones,
      'demanda_fundas': prediccion.demandaFundas,
      'carga_bidones': prediccion.cargaRecomendadaBidones,
      'carga_fundas': prediccion.cargaRecomendadaFundas,
      'riesgo_stock_bajo': prediccion.probabilidadStockBajo,
      'venta_alta_inesperada': prediccion.probabilidadVentaAltaInesperada,
      'modelo_nombre': modeloNombre,
      'origen': 'tflite',
      'actualizado_en': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _filaSemanal(
    PrediccionPeriodoAlertas semana,
    String modeloNombre,
  ) {
    return {
      'clave': 'semanal_${_fechaSql(semana.desde)}',
      'tipo': 'semanal',
      'fecha_objetivo': _fechaSql(semana.desde),
      'periodo_inicio': _fechaSql(semana.desde),
      'periodo_fin': _fechaSql(semana.hasta),
      'titulo': 'Prediccion semanal',
      'cuerpo':
          '${semana.etiqueta}: venta esperada de ${semana.demandaBidones} bidones y ${semana.demandaFundas} fundas. Dia pico estimado: ${_fechaSql(semana.diaPico)}.',
      'demanda_bidones': semana.demandaBidones,
      'demanda_fundas': semana.demandaFundas,
      'carga_bidones': semana.cargaRecomendadaBidones,
      'carga_fundas': semana.cargaRecomendadaFundas,
      'riesgo_stock_bajo': semana.probabilidadStockBajoMaxima,
      'venta_alta_inesperada': semana.probabilidadVentaAltaMaxima,
      'dia_pico': _fechaSql(semana.diaPico),
      'modelo_nombre': modeloNombre,
      'origen': 'tflite',
      'actualizado_en': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _filaMensual(
    PrediccionPeriodoAlertas mes,
    String modeloNombre,
  ) {
    return {
      'clave': 'mensual_${_fechaSql(mes.desde)}',
      'tipo': 'mensual',
      'fecha_objetivo': _fechaSql(mes.desde),
      'periodo_inicio': _fechaSql(mes.desde),
      'periodo_fin': _fechaSql(mes.hasta),
      'titulo': 'Prediccion mensual',
      'cuerpo':
          '${mes.etiqueta}: venta esperada de ${mes.demandaBidones} bidones y ${mes.demandaFundas} fundas. Riesgo maximo de stock bajo: ${(mes.probabilidadStockBajoMaxima * 100).round()}%.',
      'demanda_bidones': mes.demandaBidones,
      'demanda_fundas': mes.demandaFundas,
      'carga_bidones': mes.cargaRecomendadaBidones,
      'carga_fundas': mes.cargaRecomendadaFundas,
      'riesgo_stock_bajo': mes.probabilidadStockBajoMaxima,
      'venta_alta_inesperada': mes.probabilidadVentaAltaMaxima,
      'dia_pico': _fechaSql(mes.diaPico),
      'modelo_nombre': modeloNombre,
      'origen': 'tflite',
      'actualizado_en': DateTime.now().toIso8601String(),
    };
  }

  List<Map<String, dynamic>> _filasTemporada(
    TemporadaVentasFuerte temporada,
    String modeloNombre,
  ) {
    final filas = <Map<String, dynamic>>[];
    final fechaObjetivo = _fechaSql(temporada.inicio);

    void agregar(String tipo, String titulo, String cuerpo) {
      filas.add({
        'clave':
            '${tipo}_${fechaObjetivo}_${_normalizarClave(temporada.nombre)}',
        'tipo': tipo,
        'fecha_objetivo': fechaObjetivo,
        'periodo_inicio': fechaObjetivo,
        'periodo_fin': fechaObjetivo,
        'titulo': titulo,
        'cuerpo': cuerpo,
        'temporada_nombre': temporada.nombre,
        'dias_restantes': temporada.diasRestantes,
        'modelo_nombre': modeloNombre,
        'origen': 'tflite',
        'actualizado_en': DateTime.now().toIso8601String(),
      });
    }

    if (temporada.diasRestantes <= 31) {
      agregar(
        'temporada_mes',
        'Temporada fuerte este mes',
        '${temporada.nombre} cae dentro de este mes, faltan ${temporada.diasRestantes} dias. Planifica compras e inventario.',
      );
    }
    if (temporada.diasRestantes <= 7) {
      agregar(
        'temporada_semana',
        'Temporada fuerte esta semana',
        '${temporada.nombre} entra esta semana, faltan ${temporada.diasRestantes} dias. Prepara inventario y rutas.',
      );
    }
    if (temporada.diasRestantes == 0) {
      agregar(
        'temporada_dia',
        'Temporada fuerte hoy',
        '${temporada.nombre} es hoy. Revisa inventario, despacho y cobros desde temprano.',
      );
    }

    return filas;
  }

  /// Resultado intermedio del modelo ML.
  Future<_ResultadoML?> _intentarPrediccionML({
    required Map<String, dynamic> metadatos,
    required List<Producto> productos,
    required List<Ruta> rutas,
    required List<Venta> ventas,
    required DateTime fecha,
  }) async {
    final normalizadas = _normalizarEntrada(
      metadatos: metadatos,
      productos: productos,
      rutas: rutas,
      ventas: ventas,
      fecha: fecha,
    );
    ResultadoInferenciaML? resultado;
    try {
      resultado = await _inferir(
        rutaModelo: _rutaModelo,
        entradaNormalizada: normalizadas,
      );
    } catch (error) {
      debugPrint(
        'Modelo ML no disponible; se usara estimacion estadistica: $error',
      );
      return null;
    }
    if (resultado == null) return null;

    final prediccion = _interpretarSalida(
      metadatos: metadatos,
      clasificacion: resultado.clasificacion,
      regresion: resultado.regresion,
    );
    return _ResultadoML(
      entradas: resultado.nombresEntrada,
      salidas: resultado.nombresSalida,
      prediccion: prediccion,
    );
  }

  /// Predicción estadística fallback cuando el modelo ML no está disponible.
  @visibleForTesting
  PrediccionModeloAlertas estimarPrediccionEstadistica({
    required List<Producto> productos,
    required List<Venta> ventas,
    required DateTime fecha,
  }) {
    return _prediccionEstadistica(
      productos: productos,
      ventas: ventas,
      fecha: fecha,
    );
  }

  PrediccionModeloAlertas _prediccionEstadistica({
    required List<Producto> productos,
    required List<Venta> ventas,
    required DateTime fecha,
  }) {
    final fechaBase = DateTime(fecha.year, fecha.month, fecha.day);
    final base = _demandaBaseOperativa(fechaBase);
    final ventasPrevias = ventas.where(
      (v) => DateTime(
        v.fecha.year,
        v.fecha.month,
        v.fecha.day,
      ).isBefore(fechaBase),
    );
    final promedio7 = _promedioVentas(ventasPrevias, fechaBase, 7);
    final promedio30 = _promedioVentas(ventasPrevias, fechaBase, 30);
    final tieneHistorial =
        promedio7.tieneHistorial || promedio30.tieneHistorial;

    final promBidones = _proyectarDemanda(
      base: base.bidones,
      promedio7: promedio7.bidones,
      promedio30: promedio30.bidones,
      tieneHistorial: tieneHistorial,
    );
    final promFundas = _proyectarDemanda(
      base: base.fundas,
      promedio7: promedio7.fundas,
      promedio30: promedio30.fundas,
      tieneHistorial: tieneHistorial,
    );

    final stockBidones = productos
        .where((p) => _esBidon(p.nombre))
        .fold<int>(0, (s, p) => s + p.stock);
    final stockFundas = productos
        .where((p) => _esFunda(p.nombre))
        .fold<int>(0, (s, p) => s + p.stock);

    return PrediccionModeloAlertas(
      demandaBidones: promBidones.round(),
      demandaFundas: promFundas.round(),
      demandaTotalUnidades: (promBidones + promFundas).round(),
      cargaRecomendadaBidones: (promBidones * 1.2).round(),
      cargaRecomendadaFundas: (promFundas * 1.2).round(),
      probabilidadStockBajo: stockBidones < 10 || stockFundas < 20 ? 0.7 : 0.2,
      probabilidadVentaAltaInesperada: 0.15,
    );
  }

  @visibleForTesting
  PrediccionModeloAlertas calibrarPrediccionDiaria({
    required PrediccionModeloAlertas prediccion,
    required PrediccionModeloAlertas respaldo,
    PrediccionPeriodoAlertas? semana,
  }) {
    final diasSemana = semana == null
        ? null
        : max(1, semana.hasta.difference(semana.desde).inDays + 1);
    final promedioBidonesSemana = semana == null
        ? null
        : semana.demandaBidones / diasSemana!;
    final promedioFundasSemana = semana == null
        ? null
        : semana.demandaFundas / diasSemana!;

    var demandaBidones = _calibrarDemandaDiaria(
      modelo: prediccion.demandaBidones,
      respaldo: respaldo.demandaBidones,
      promedioSemana: promedioBidonesSemana,
      permitirMinimoUno: false,
    );
    var demandaFundas = _calibrarDemandaDiaria(
      modelo: prediccion.demandaFundas,
      respaldo: respaldo.demandaFundas,
      promedioSemana: promedioFundasSemana,
      permitirMinimoUno: true,
      limitarExceso: true,
    );

    if (respaldo.demandaBidones > respaldo.demandaFundas) {
      final bidonesConMargen = (demandaFundas * 1.65).ceil();
      if (demandaBidones < bidonesConMargen) {
        demandaBidones = min(
          max(max(demandaBidones, respaldo.demandaBidones), bidonesConMargen),
          max(respaldo.demandaBidones, (demandaFundas * 1.90).ceil()),
        );
      }
      demandaFundas = min(
        demandaFundas,
        max(respaldo.demandaFundas, (demandaBidones * 0.65).round()),
      );
    }

    return PrediccionModeloAlertas(
      demandaBidones: demandaBidones,
      demandaFundas: demandaFundas,
      demandaTotalUnidades: max(
        prediccion.demandaTotalUnidades,
        demandaBidones + demandaFundas,
      ),
      cargaRecomendadaBidones: max(
        prediccion.cargaRecomendadaBidones,
        (demandaBidones * 1.15).ceil(),
      ),
      cargaRecomendadaFundas: _calibrarCargaRecomendada(
        modelo: prediccion.cargaRecomendadaFundas,
        demanda: demandaFundas,
      ),
      probabilidadStockBajo: prediccion.probabilidadStockBajo,
      probabilidadVentaAltaInesperada:
          prediccion.probabilidadVentaAltaInesperada,
    );
  }

  int _calibrarDemandaDiaria({
    required int modelo,
    required int respaldo,
    required double? promedioSemana,
    required bool permitirMinimoUno,
    bool limitarExceso = false,
  }) {
    if (modelo <= 0) {
      return max(
        respaldo,
        max(
          permitirMinimoUno ? 1 : 0,
          promedioSemana != null && promedioSemana >= 0.5
              ? promedioSemana.round()
              : 0,
        ),
      );
    }

    if (respaldo >= 8 && modelo < respaldo) {
      return max(modelo, respaldo);
    }

    if (promedioSemana != null &&
        promedioSemana >= 2 &&
        modelo < promedioSemana * 0.35) {
      final techoRazonable = respaldo > 0
          ? min(respaldo, (promedioSemana * 1.15).round())
          : promedioSemana.round();
      return max(modelo, techoRazonable);
    }

    if (limitarExceso && respaldo > 0) {
      final techoOperativo = (respaldo * 1.25).ceil();
      final techoHistorico = promedioSemana != null && promedioSemana >= 2
          ? (promedioSemana * 1.35).ceil()
          : 0;
      final techo = max(techoOperativo, techoHistorico);
      if (modelo > techo) return techo;
    }

    return modelo;
  }

  int _calibrarCargaRecomendada({required int modelo, required int demanda}) {
    final minima = (demanda * 1.15).ceil();
    final maxima = (demanda * 1.35).ceil();
    if (modelo <= 0) return minima;
    return modelo.clamp(minima, max(minima, maxima));
  }

  _DemandaBase _demandaBaseOperativa(DateTime fecha) {
    final porDia = switch (fecha.weekday) {
      DateTime.monday => const _DemandaBase(115, 52),
      DateTime.tuesday => const _DemandaBase(70, 40),
      DateTime.wednesday => const _DemandaBase(104, 54),
      DateTime.thursday => const _DemandaBase(70, 38),
      DateTime.friday => const _DemandaBase(74, 42),
      DateTime.saturday => const _DemandaBase(127, 66),
      DateTime.sunday => const _DemandaBase(46, 24),
      _ => const _DemandaBase(75, 40),
    };

    var factor = 1.0;
    if ({6, 7, 8, 9}.contains(fecha.month)) factor *= 1.10;
    if (fecha.month == 12 && fecha.day >= 15 && fecha.day <= 25) {
      factor *= 1.35;
    }
    if ((fecha.month == 4 && fecha.day <= 15) ||
        (fecha.month == 9 && fecha.day <= 15)) {
      factor *= 1.14;
    }
    if (fecha.month == 6 && fecha.day >= 14 && fecha.day <= 20) {
      factor *= 1.16;
    }
    if (_esFeriadoNacional(fecha)) factor *= 0.94;

    return _DemandaBase(porDia.bidones * factor, porDia.fundas * factor);
  }

  _PromedioDemanda _promedioVentas(
    Iterable<Venta> ventas,
    DateTime fechaBase,
    int dias,
  ) {
    final inicio = fechaBase.subtract(Duration(days: dias));
    var bidones = 0;
    var fundas = 0;
    for (final venta in ventas.where(
      (v) => !v.fecha.isBefore(inicio) && v.fecha.isBefore(fechaBase),
    )) {
      for (final item in venta.items) {
        if (_esBidon(item.nombreProducto)) bidones += item.cantidad;
        if (_esFunda(item.nombreProducto)) fundas += item.cantidad;
      }
    }

    return _PromedioDemanda(
      bidones: bidones / dias,
      fundas: fundas / dias,
      tieneHistorial: bidones > 0 || fundas > 0,
    );
  }

  double _proyectarDemanda({
    required double base,
    required double promedio7,
    required double promedio30,
    required bool tieneHistorial,
  }) {
    if (!tieneHistorial) return base;
    final promedioReciente = promedio7 > 0 && promedio30 > 0
        ? promedio7 * 0.7 + promedio30 * 0.3
        : max(promedio7, promedio30);
    final pisoOperativo = base * 0.55;
    return max(promedioReciente, max(promedio30 * 0.9, pisoOperativo));
  }

  /// Normaliza las características de entrada para el modelo.
  List<double> _normalizarEntrada({
    required Map<String, dynamic> metadatos,
    required List<Producto> productos,
    required List<Ruta> rutas,
    required List<Venta> ventas,
    required DateTime fecha,
  }) {
    final entrada = metadatos['entrada'] as Map<String, dynamic>;
    final nombres = List<String>.from(entrada['nombres_caracteristicas']);
    final normalizacion = entrada['normalizacion'] as Map<String, dynamic>;
    final medias = List<num>.from(normalizacion['media']);
    final desviaciones = List<num>.from(normalizacion['desviacion']);
    final caracteristicas = _construirCaracteristicas(
      nombres: nombres,
      medias: medias,
      productos: productos,
      rutas: rutas,
      ventas: ventas,
      fecha: fecha,
    );
    final normalizadas = <double>[];
    for (var i = 0; i < nombres.length; i++) {
      final std = desviaciones[i].toDouble() == 0
          ? 1.0
          : desviaciones[i].toDouble();
      normalizadas.add((caracteristicas[i] - medias[i].toDouble()) / std);
    }
    return normalizadas;
  }

  /// Interpreta las salidas crudas del modelo ML.
  PrediccionModeloAlertas _interpretarSalida({
    required Map<String, dynamic> metadatos,
    required List<double> clasificacion,
    required List<double> regresion,
  }) {
    final salidaRegresion =
        (metadatos['salidas'] as Map<String, dynamic>)['salida_regresion']
            as Map<String, dynamic>;
    final desnormalizacion =
        salidaRegresion['desnormalizacion'] as Map<String, dynamic>;
    final mediaSalida = List<num>.from(desnormalizacion['media']);
    final desviacionSalida = List<num>.from(desnormalizacion['desviacion']);
    final valores = <double>[];
    for (var i = 0; i < regresion.length; i++) {
      valores.add(
        max(
          0,
          regresion[i] * desviacionSalida[i].toDouble() +
              mediaSalida[i].toDouble(),
        ),
      );
    }

    final demandaBidones = _normalizarDemandaDesdeModelo(
      demanda: valores[0],
      cargaRecomendada: valores[3],
    );
    final demandaFundas = _normalizarDemandaDesdeModelo(
      demanda: valores[1],
      cargaRecomendada: valores[4],
    );
    final demandaTotal = max(valores[2], demandaBidones + demandaFundas);

    return PrediccionModeloAlertas(
      demandaBidones: demandaBidones.round(),
      demandaFundas: demandaFundas.round(),
      demandaTotalUnidades: demandaTotal.round(),
      cargaRecomendadaBidones: valores[3].round(),
      cargaRecomendadaFundas: valores[4].round(),
      probabilidadStockBajo: clasificacion[0].clamp(0, 1).toDouble(),
      probabilidadVentaAltaInesperada: clasificacion[1].clamp(0, 1).toDouble(),
    );
  }

  double _normalizarDemandaDesdeModelo({
    required double demanda,
    required double cargaRecomendada,
  }) {
    if (cargaRecomendada <= 0) return demanda;
    final demandaSegunCarga = cargaRecomendada / 1.12;
    if (demanda < 1) return demandaSegunCarga;
    if (cargaRecomendada > demanda * 1.45) return demandaSegunCarga;
    return demanda;
  }

  Future<PrediccionPeriodoAlertas> _ejecutarPrediccionPeriodoML({
    required Map<String, dynamic> metadatos,
    required List<Producto> productos,
    required List<Ruta> rutas,
    required List<Venta> ventas,
    required DateTime fechaInicio,
    required int dias,
    required String etiqueta,
  }) async {
    var demandaBidones = 0;
    var demandaFundas = 0;
    var cargaBidones = 0;
    var cargaFundas = 0;
    var riesgoStockMaximo = 0.0;
    var probabilidadVentaAltaMaxima = 0.0;
    var demandaDiaPico = -1;
    var diaPico = DateTime(
      fechaInicio.year,
      fechaInicio.month,
      fechaInicio.day,
    );

    for (var indice = 0; indice < dias; indice++) {
      final fecha = DateTime(
        fechaInicio.year,
        fechaInicio.month,
        fechaInicio.day + indice,
      );
      final normalizadas = _normalizarEntrada(
        metadatos: metadatos,
        productos: productos,
        rutas: rutas,
        ventas: ventas,
        fecha: fecha,
      );
      final resultado = await _inferir(
        rutaModelo: _rutaModelo,
        entradaNormalizada: normalizadas,
      );
      if (resultado == null) continue;
      final prediccionModelo = _interpretarSalida(
        metadatos: metadatos,
        clasificacion: resultado.clasificacion,
        regresion: resultado.regresion,
      );
      final respaldoDiario = _prediccionEstadistica(
        productos: productos,
        ventas: ventas,
        fecha: fecha,
      );
      final prediccion = calibrarPrediccionDiaria(
        prediccion: prediccionModelo,
        respaldo: respaldoDiario,
      );
      demandaBidones += prediccion.demandaBidones;
      demandaFundas += prediccion.demandaFundas;
      cargaBidones += prediccion.cargaRecomendadaBidones;
      cargaFundas += prediccion.cargaRecomendadaFundas;
      riesgoStockMaximo = max(
        riesgoStockMaximo,
        prediccion.probabilidadStockBajo,
      );
      probabilidadVentaAltaMaxima = max(
        probabilidadVentaAltaMaxima,
        prediccion.probabilidadVentaAltaInesperada,
      );

      final demandaDia = prediccion.demandaBidones + prediccion.demandaFundas;
      if (demandaDia > demandaDiaPico) {
        demandaDiaPico = demandaDia;
        diaPico = fecha;
      }
    }

    return PrediccionPeriodoAlertas(
      etiqueta: etiqueta,
      desde: DateTime(fechaInicio.year, fechaInicio.month, fechaInicio.day),
      hasta: DateTime(
        fechaInicio.year,
        fechaInicio.month,
        fechaInicio.day + dias - 1,
      ),
      diaPico: diaPico,
      demandaBidones: demandaBidones,
      demandaFundas: demandaFundas,
      cargaRecomendadaBidones: cargaBidones,
      cargaRecomendadaFundas: cargaFundas,
      probabilidadStockBajoMaxima: riesgoStockMaximo,
      probabilidadVentaAltaMaxima: probabilidadVentaAltaMaxima,
    );
  }

  TemporadaVentasFuerte? _temporadaProxima(DateTime fecha) {
    final hoy = DateTime(fecha.year, fecha.month, fecha.day);
    final candidatas = <TemporadaVentasFuerte>[];

    for (final anio in [hoy.year, hoy.year + 1]) {
      void agregar({
        required String nombre,
        required int mes,
        required int dia,
        required String explicacion,
      }) {
        final inicio = DateTime(anio, mes, dia);
        final diasRestantes = inicio.difference(hoy).inDays;
        if (diasRestantes >= 0 && diasRestantes <= 45) {
          candidatas.add(
            TemporadaVentasFuerte(
              nombre: nombre,
              inicio: inicio,
              diasRestantes: diasRestantes,
              explicacion: explicacion,
            ),
          );
        }
      }

      agregar(
        nombre: 'Inicio de clases',
        mes: 4,
        dia: 1,
        explicacion:
            'La demanda suele subir por movimiento de familias y aulas.',
      );
      agregar(
        nombre: 'Fiestas de Lago Agrio',
        mes: 6,
        dia: 14,
        explicacion: 'Temporada local con mayor rotación de agua.',
      );
      agregar(
        nombre: 'Pedidos grandes de septiembre',
        mes: 9,
        dia: 1,
        explicacion: 'Mes asociado a pedidos externos grandes de fundas.',
      );
      agregar(
        nombre: 'Pedidos grandes de octubre',
        mes: 10,
        dia: 1,
        explicacion: 'Históricamente aparecen compras grandes de fundas.',
      );
      agregar(
        nombre: 'Navidad',
        mes: 12,
        dia: 8,
        explicacion: 'La venta aumenta antes de Navidad.',
      );
    }

    candidatas.sort((a, b) => a.diasRestantes.compareTo(b.diasRestantes));
    return candidatas.isEmpty ? null : candidatas.first;
  }

  List<double> _construirCaracteristicas({
    required List<String> nombres,
    required List<num> medias,
    required List<Producto> productos,
    required List<Ruta> rutas,
    required List<Venta> ventas,
    required DateTime fecha,
  }) {
    final fechaBase = DateTime(fecha.year, fecha.month, fecha.day);
    final diaSemana = fechaBase.weekday;
    final ventasPrevias = ventas
        .where(
          (venta) => DateTime(
            venta.fecha.year,
            venta.fecha.month,
            venta.fecha.day,
          ).isBefore(fechaBase),
        )
        .toList();
    final tieneHistorial = ventasPrevias.isNotEmpty;

    double mediaCaracteristica(String nombre) =>
        medias[nombres.indexOf(nombre)].toDouble();

    double valorHistorico(String nombre, double valor) {
      return tieneHistorial ? valor : mediaCaracteristica(nombre);
    }

    double sumaBidones(DateTime desde, DateTime hasta) => ventasPrevias
        .where(
          (venta) =>
              !venta.fecha.isBefore(desde) && venta.fecha.isBefore(hasta),
        )
        .fold<double>(
          0,
          (s, venta) =>
              s +
              venta.items
                  .where((item) => _esBidon(item.nombreProducto))
                  .fold<int>(0, (x, item) => x + item.cantidad),
        );

    double sumaFundas(DateTime desde, DateTime hasta) => ventasPrevias
        .where(
          (venta) =>
              !venta.fecha.isBefore(desde) && venta.fecha.isBefore(hasta),
        )
        .fold<double>(
          0,
          (s, venta) =>
              s +
              venta.items
                  .where((item) => _esFunda(item.nombreProducto))
                  .fold<int>(0, (x, item) => x + item.cantidad),
        );

    double sumaIngreso(DateTime desde, DateTime hasta) => ventasPrevias
        .where(
          (venta) =>
              !venta.fecha.isBefore(desde) && venta.fecha.isBefore(hasta),
        )
        .fold<double>(0, (s, venta) => s + venta.totalEfectivo);

    final ayer = fechaBase.subtract(const Duration(days: 1));
    final inicio7 = fechaBase.subtract(const Duration(days: 7));
    final inicio30 = fechaBase.subtract(const Duration(days: 30));
    final ultimoDiaMes = DateTime(fechaBase.year, fechaBase.month + 1, 0).day;
    final stockBidones = productos
        .where((p) => _esBidon(p.nombre))
        .fold<int>(0, (s, p) => s + p.stock);
    final stockFundas = productos
        .where((p) => _esFunda(p.nombre))
        .fold<int>(0, (s, p) => s + p.stock);

    final valores = <String, double>{
      'anio': fechaBase.year.toDouble(),
      'mes': fechaBase.month.toDouble(),
      'dia_mes': fechaBase.day.toDouble(),
      'dia_semana_num': diaSemana.toDouble(),
      'es_lunes': diaSemana == 1 ? 1 : 0,
      'es_miercoles': diaSemana == 3 ? 1 : 0,
      'es_sabado': diaSemana == 6 ? 1 : 0,
      'es_domingo': diaSemana == 7 ? 1 : 0,
      'es_fin_semana': diaSemana >= 6 ? 1 : 0,
      'temporada_verano': {6, 7, 8, 9}.contains(fechaBase.month) ? 1 : 0,
      'temporada_navidad':
          fechaBase.month == 12 && fechaBase.day >= 15 && fechaBase.day <= 25
          ? 1
          : 0,
      'temporada_inicio_clases':
          (fechaBase.month == 4 && fechaBase.day <= 15) ||
              (fechaBase.month == 9 && fechaBase.day <= 15)
          ? 1
          : 0,
      'temporada_fiesta_lago_agrio':
          fechaBase.month == 6 && fechaBase.day >= 14 && fechaBase.day <= 20
          ? 1
          : 0,
      'feriado_nacional': _esFeriadoNacional(fechaBase) ? 1 : 0,
      'fin_mes': fechaBase.day >= ultimoDiaMes - 3 ? 1 : 0,
      'vendedores_planificados': _vendedoresPlanificados(fechaBase).toDouble(),
      'paisa_etapa_baja_frecuencia': fechaBase.year >= 2025 ? 1 : 0,
      'bidones_vendidos_total_lag_1': valorHistorico(
        'bidones_vendidos_total_lag_1',
        sumaBidones(ayer, fechaBase),
      ),
      'bidones_vendidos_total_prom_7d': valorHistorico(
        'bidones_vendidos_total_prom_7d',
        sumaBidones(inicio7, fechaBase) / 7,
      ),
      'bidones_vendidos_total_prom_30d': valorHistorico(
        'bidones_vendidos_total_prom_30d',
        sumaBidones(inicio30, fechaBase) / 30,
      ),
      'fundas_vendidas_total_lag_1': valorHistorico(
        'fundas_vendidas_total_lag_1',
        sumaFundas(ayer, fechaBase),
      ),
      'fundas_vendidas_total_prom_7d': valorHistorico(
        'fundas_vendidas_total_prom_7d',
        sumaFundas(inicio7, fechaBase) / 7,
      ),
      'fundas_vendidas_total_prom_30d': valorHistorico(
        'fundas_vendidas_total_prom_30d',
        sumaFundas(inicio30, fechaBase) / 30,
      ),
      'ingreso_total_lag_1': valorHistorico(
        'ingreso_total_lag_1',
        sumaIngreso(ayer, fechaBase),
      ),
      'ingreso_total_prom_7d': valorHistorico(
        'ingreso_total_prom_7d',
        sumaIngreso(inicio7, fechaBase) / 7,
      ),
      'ingreso_total_prom_30d': valorHistorico(
        'ingreso_total_prom_30d',
        sumaIngreso(inicio30, fechaBase) / 30,
      ),
      'stock_bidones_inicio_estimado': stockBidones > 0
          ? stockBidones.toDouble()
          : medias[nombres.indexOf('stock_bidones_inicio_estimado')].toDouble(),
      'stock_fundas_inicio_estimado': stockFundas > 0
          ? stockFundas.toDouble()
          : medias[nombres.indexOf('stock_fundas_inicio_estimado')].toDouble(),
    };

    return nombres.map((nombre) => valores[nombre] ?? 0).toList();
  }

  bool _esFeriadoNacional(DateTime fecha) {
    const feriados = {
      '1-1',
      '5-1',
      '5-24',
      '8-10',
      '10-9',
      '11-2',
      '11-3',
      '12-25',
    };
    return feriados.contains('${fecha.month}-${fecha.day}');
  }

  int _vendedoresPlanificados(DateTime fecha) {
    var count = 1;
    if ({1, 2, 4, 6}.contains(fecha.weekday)) count += 1;
    if (fecha.year < 2025) {
      if ({1, 2, 4, 6}.contains(fecha.weekday)) count += 1;
    } else if ({2, 4, 6}.contains(fecha.weekday)) {
      count += 1;
    }
    return count;
  }

  String _textoBusqueda(String valor) {
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    return valor.toLowerCase().split('').map((caracter) {
      return acentos[caracter] ?? caracter;
    }).join();
  }

  String _fechaSql(DateTime fecha) {
    final normalizada = DateTime(fecha.year, fecha.month, fecha.day);
    return normalizada.toIso8601String().substring(0, 10);
  }

  DateTime _inicioSemana(DateTime fecha) {
    final normalizada = DateTime(fecha.year, fecha.month, fecha.day);
    return normalizada.subtract(Duration(days: normalizada.weekday - 1));
  }

  bool _periodoCoincide(PrediccionPeriodoAlertas? periodo, DateTime inicio) {
    if (periodo == null) return false;
    return _fechaSql(periodo.desde) == _fechaSql(inicio);
  }

  String _normalizarClave(String valor) {
    return _textoBusqueda(valor).replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  bool _esBidon(String nombre) {
    final texto = _textoBusqueda(nombre);
    return texto.contains('bidon') || texto.contains('botellon');
  }

  bool _esFunda(String nombre) {
    return _textoBusqueda(nombre).contains('funda');
  }
}

class _ResultadoML {
  final List<String> entradas;
  final List<String> salidas;
  final PrediccionModeloAlertas prediccion;

  const _ResultadoML({
    required this.entradas,
    required this.salidas,
    required this.prediccion,
  });
}

class _DemandaBase {
  final double bidones;
  final double fundas;

  const _DemandaBase(this.bidones, this.fundas);
}

class _PromedioDemanda {
  final double bidones;
  final double fundas;
  final bool tieneHistorial;

  const _PromedioDemanda({
    required this.bidones,
    required this.fundas,
    required this.tieneHistorial,
  });
}
