import 'package:agua_milena_app/datos/servicios/servicio_modelo_alertas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calibracion de prediccion diaria', () {
    test(
      'corrige outliers diarios incompatibles con la prediccion semanal',
      () {
        final servicio = ServicioModeloAlertas();

        final calibrada = servicio.calibrarPrediccionDiaria(
          prediccion: const PrediccionModeloAlertas(
            demandaBidones: 6,
            demandaFundas: 0,
            demandaTotalUnidades: 6,
            cargaRecomendadaBidones: 7,
            cargaRecomendadaFundas: 0,
            probabilidadStockBajo: 0,
            probabilidadVentaAltaInesperada: 0,
          ),
          respaldo: const PrediccionModeloAlertas(
            demandaBidones: 74,
            demandaFundas: 42,
            demandaTotalUnidades: 116,
            cargaRecomendadaBidones: 89,
            cargaRecomendadaFundas: 50,
            probabilidadStockBajo: 0.2,
            probabilidadVentaAltaInesperada: 0.15,
          ),
          semana: PrediccionPeriodoAlertas(
            etiqueta: 'Proximos 7 dias',
            desde: DateTime(2026, 5, 22),
            hasta: DateTime(2026, 5, 28),
            diaPico: DateTime(2026, 5, 23),
            demandaBidones: 247,
            demandaFundas: 11,
            cargaRecomendadaBidones: 276,
            cargaRecomendadaFundas: 12,
            probabilidadStockBajoMaxima: 0,
            probabilidadVentaAltaMaxima: 0,
          ),
        );

        expect(calibrada.demandaBidones, 74);
        expect(calibrada.demandaFundas, 42);
        expect(
          calibrada.cargaRecomendadaBidones,
          greaterThanOrEqualTo((calibrada.demandaBidones * 1.15).ceil()),
        );
        expect(
          calibrada.cargaRecomendadaFundas,
          greaterThanOrEqualTo((calibrada.demandaFundas * 1.15).ceil()),
        );
      },
    );

    test('conserva predicciones diarias plausibles del modelo', () {
      final servicio = ServicioModeloAlertas();

      final calibrada = servicio.calibrarPrediccionDiaria(
        prediccion: const PrediccionModeloAlertas(
          demandaBidones: 82,
          demandaFundas: 45,
          demandaTotalUnidades: 127,
          cargaRecomendadaBidones: 95,
          cargaRecomendadaFundas: 52,
          probabilidadStockBajo: 0.1,
          probabilidadVentaAltaInesperada: 0.2,
        ),
        respaldo: const PrediccionModeloAlertas(
          demandaBidones: 74,
          demandaFundas: 42,
          demandaTotalUnidades: 116,
          cargaRecomendadaBidones: 89,
          cargaRecomendadaFundas: 50,
          probabilidadStockBajo: 0.2,
          probabilidadVentaAltaInesperada: 0.15,
        ),
        semana: PrediccionPeriodoAlertas(
          etiqueta: 'Proximos 7 dias',
          desde: DateTime(2026, 5, 22),
          hasta: DateTime(2026, 5, 28),
          diaPico: DateTime(2026, 5, 23),
          demandaBidones: 247,
          demandaFundas: 11,
          cargaRecomendadaBidones: 276,
          cargaRecomendadaFundas: 12,
          probabilidadStockBajoMaxima: 0,
          probabilidadVentaAltaMaxima: 0,
        ),
      );

      expect(calibrada.demandaBidones, 82);
      expect(calibrada.demandaFundas, 45);
    });

    test('limita fundas infladas que no tienen respaldo operativo', () {
      final servicio = ServicioModeloAlertas();

      final calibrada = servicio.calibrarPrediccionDiaria(
        prediccion: const PrediccionModeloAlertas(
          demandaBidones: 82,
          demandaFundas: 140,
          demandaTotalUnidades: 222,
          cargaRecomendadaBidones: 95,
          cargaRecomendadaFundas: 180,
          probabilidadStockBajo: 0.1,
          probabilidadVentaAltaInesperada: 0.2,
        ),
        respaldo: const PrediccionModeloAlertas(
          demandaBidones: 74,
          demandaFundas: 42,
          demandaTotalUnidades: 116,
          cargaRecomendadaBidones: 89,
          cargaRecomendadaFundas: 50,
          probabilidadStockBajo: 0.2,
          probabilidadVentaAltaInesperada: 0.15,
        ),
      );

      expect(calibrada.demandaBidones, 88);
      expect(calibrada.demandaFundas, 53);
      expect(calibrada.cargaRecomendadaFundas, 72);
    });

    test('corrige predicciones invertidas cuando bidones debe ser mayor', () {
      final servicio = ServicioModeloAlertas();

      final calibrada = servicio.calibrarPrediccionDiaria(
        prediccion: const PrediccionModeloAlertas(
          demandaBidones: 24,
          demandaFundas: 46,
          demandaTotalUnidades: 70,
          cargaRecomendadaBidones: 28,
          cargaRecomendadaFundas: 53,
          probabilidadStockBajo: 0.1,
          probabilidadVentaAltaInesperada: 0.2,
        ),
        respaldo: const PrediccionModeloAlertas(
          demandaBidones: 46,
          demandaFundas: 24,
          demandaTotalUnidades: 70,
          cargaRecomendadaBidones: 55,
          cargaRecomendadaFundas: 29,
          probabilidadStockBajo: 0.2,
          probabilidadVentaAltaInesperada: 0.15,
        ),
      );

      expect(calibrada.demandaBidones, greaterThan(calibrada.demandaFundas));
      expect(calibrada.demandaBidones, 50);
      expect(calibrada.demandaFundas, 30);
    });

    test(
      'usa la base operativa como piso aunque el modelo solo baje un poco',
      () {
        final servicio = ServicioModeloAlertas();

        final calibrada = servicio.calibrarPrediccionDiaria(
          prediccion: const PrediccionModeloAlertas(
            demandaBidones: 60,
            demandaFundas: 30,
            demandaTotalUnidades: 90,
            cargaRecomendadaBidones: 67,
            cargaRecomendadaFundas: 34,
            probabilidadStockBajo: 0.1,
            probabilidadVentaAltaInesperada: 0.2,
          ),
          respaldo: const PrediccionModeloAlertas(
            demandaBidones: 74,
            demandaFundas: 42,
            demandaTotalUnidades: 116,
            cargaRecomendadaBidones: 89,
            cargaRecomendadaFundas: 50,
            probabilidadStockBajo: 0.2,
            probabilidadVentaAltaInesperada: 0.15,
          ),
        );

        expect(calibrada.demandaBidones, 74);
        expect(calibrada.demandaFundas, 42);
      },
    );
  });

  group('respaldo estadistico diario', () {
    test('respeta la base operativa completa para cada dia de la semana', () {
      final servicio = ServicioModeloAlertas();
      final casos = <DateTime, (int, int)>{
        DateTime(2026, 5, 18): (115, 52),
        DateTime(2026, 5, 19): (70, 40),
        DateTime(2026, 5, 20): (104, 54),
        DateTime(2026, 5, 21): (70, 38),
        DateTime(2026, 5, 22): (74, 42),
        DateTime(2026, 5, 23): (127, 66),
        DateTime(2026, 5, 24): (43, 23),
      };

      for (final MapEntry(key: fecha, value: esperado) in casos.entries) {
        final prediccion = servicio.estimarPrediccionEstadistica(
          productos: const [],
          ventas: const [],
          fecha: fecha,
        );

        expect(prediccion.demandaBidones, esperado.$1);
        expect(prediccion.demandaFundas, esperado.$2);
      }
    });
  });

  group('guardado de predicciones push', () {
    test('prepara semana y mes aunque no sea lunes ni dia 1', () async {
      final servicio = ServicioModeloAlertas();
      final estado = EstadoModeloAlertas(
        nombre: 'modelo_tflite',
        entradas: const [],
        salidas: const [],
        prediccion: const PrediccionModeloAlertas(
          demandaBidones: 74,
          demandaFundas: 42,
          demandaTotalUnidades: 116,
          cargaRecomendadaBidones: 89,
          cargaRecomendadaFundas: 50,
          probabilidadStockBajo: 0.2,
          probabilidadVentaAltaInesperada: 0.15,
        ),
        prediccionSemana: PrediccionPeriodoAlertas(
          etiqueta: 'Proximos 7 dias',
          desde: DateTime(2026, 5, 20),
          hasta: DateTime(2026, 5, 26),
          diaPico: DateTime(2026, 5, 23),
          demandaBidones: 520,
          demandaFundas: 260,
          cargaRecomendadaBidones: 598,
          cargaRecomendadaFundas: 299,
          probabilidadStockBajoMaxima: 0.2,
          probabilidadVentaAltaMaxima: 0.15,
        ),
        prediccionMes: PrediccionPeriodoAlertas(
          etiqueta: 'Proximos 30 dias',
          desde: DateTime(2026, 5, 20),
          hasta: DateTime(2026, 6, 18),
          diaPico: DateTime(2026, 5, 23),
          demandaBidones: 2200,
          demandaFundas: 1100,
          cargaRecomendadaBidones: 2530,
          cargaRecomendadaFundas: 1265,
          probabilidadStockBajoMaxima: 0.2,
          probabilidadVentaAltaMaxima: 0.15,
        ),
      );

      final filas = await servicio.construirFilasPrediccionesTflite(
        estado: estado,
        fecha: DateTime(2026, 5, 20),
        construirSemana: (inicio) async => _periodo(
          inicio: inicio,
          dias: 7,
          etiqueta: 'Proximos 7 dias',
          bidones: 520,
          fundas: 260,
        ),
        construirMes: (inicio) async => _periodo(
          inicio: inicio,
          dias: 30,
          etiqueta: 'Proximos 30 dias',
          bidones: 2200,
          fundas: 1100,
        ),
      );

      expect(filas.map((fila) => fila['tipo']), [
        'diaria',
        'semanal',
        'semanal',
        'mensual',
        'mensual',
      ]);
      expect(filas.map((fila) => fila['fecha_objetivo']), [
        '2026-05-20',
        '2026-05-18',
        '2026-05-25',
        '2026-05-01',
        '2026-06-01',
      ]);
    });

    test('prepara los periodos actuales y futuros desde lunes dia 1', () async {
      final servicio = ServicioModeloAlertas();
      final estado = EstadoModeloAlertas(
        nombre: 'modelo_tflite',
        entradas: const [],
        salidas: const [],
        prediccion: const PrediccionModeloAlertas(
          demandaBidones: 74,
          demandaFundas: 42,
          demandaTotalUnidades: 116,
          cargaRecomendadaBidones: 89,
          cargaRecomendadaFundas: 50,
          probabilidadStockBajo: 0.2,
          probabilidadVentaAltaInesperada: 0.15,
        ),
        prediccionSemana: PrediccionPeriodoAlertas(
          etiqueta: 'Proximos 7 dias',
          desde: DateTime(2026, 6, 1),
          hasta: DateTime(2026, 6, 7),
          diaPico: DateTime(2026, 6, 6),
          demandaBidones: 520,
          demandaFundas: 260,
          cargaRecomendadaBidones: 598,
          cargaRecomendadaFundas: 299,
          probabilidadStockBajoMaxima: 0.2,
          probabilidadVentaAltaMaxima: 0.15,
        ),
        prediccionMes: PrediccionPeriodoAlertas(
          etiqueta: 'Proximos 30 dias',
          desde: DateTime(2026, 6, 1),
          hasta: DateTime(2026, 6, 30),
          diaPico: DateTime(2026, 6, 6),
          demandaBidones: 2200,
          demandaFundas: 1100,
          cargaRecomendadaBidones: 2530,
          cargaRecomendadaFundas: 1265,
          probabilidadStockBajoMaxima: 0.2,
          probabilidadVentaAltaMaxima: 0.15,
        ),
      );

      final filas = await servicio.construirFilasPrediccionesTflite(
        estado: estado,
        fecha: DateTime(2026, 6, 1),
        construirSemana: (inicio) async => _periodo(
          inicio: inicio,
          dias: 7,
          etiqueta: 'Proximos 7 dias',
          bidones: 520,
          fundas: 260,
        ),
        construirMes: (inicio) async => _periodo(
          inicio: inicio,
          dias: 30,
          etiqueta: 'Proximos 30 dias',
          bidones: 2200,
          fundas: 1100,
        ),
      );

      expect(filas.map((fila) => fila['tipo']), [
        'diaria',
        'semanal',
        'semanal',
        'mensual',
        'mensual',
      ]);
      expect(filas.map((fila) => fila['fecha_objetivo']), [
        '2026-06-01',
        '2026-06-01',
        '2026-06-08',
        '2026-06-01',
        '2026-07-01',
      ]);
    });
  });
}

PrediccionPeriodoAlertas _periodo({
  required DateTime inicio,
  required int dias,
  required String etiqueta,
  required int bidones,
  required int fundas,
}) {
  return PrediccionPeriodoAlertas(
    etiqueta: etiqueta,
    desde: inicio,
    hasta: inicio.add(Duration(days: dias - 1)),
    diaPico: inicio,
    demandaBidones: bidones,
    demandaFundas: fundas,
    cargaRecomendadaBidones: (bidones * 1.15).ceil(),
    cargaRecomendadaFundas: (fundas * 1.15).ceil(),
    probabilidadStockBajoMaxima: 0.2,
    probabilidadVentaAltaMaxima: 0.15,
  );
}
