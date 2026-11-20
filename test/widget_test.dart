import 'package:agua_milena_app/nucleo/constantes/colores_app.dart';
import 'package:agua_milena_app/nucleo/utilidades/utilidades_fecha.dart';
import 'package:agua_milena_app/presentacion/componentes/fondo_agua_ambiental.dart';
import 'package:agua_milena_app/presentacion/componentes/tarjeta_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weekdayInitial returns the real calendar day', () {
    expect(AppDateUtils.weekdayInitial(DateTime(2026, 4, 24)), 'V');
    expect(AppDateUtils.weekdayInitial(DateTime(2026, 4, 25)), 'S');
    expect(AppDateUtils.weekdayInitial(DateTime(2026, 4, 26)), 'D');
  });

  testWidgets('ambient background fills a stack without layout errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: FondoAguaAmbiental(
                  primary: AppColors.primary,
                  secondary: AppColors.teal,
                  accent: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(FondoAguaAmbiental), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('app card handles taps', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TarjetaApp(
              onTap: () => taps++,
              padding: const EdgeInsets.all(16),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pump();

    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
