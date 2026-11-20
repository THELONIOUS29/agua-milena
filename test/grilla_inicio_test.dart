import 'package:agua_milena_app/presentacion/componentes/grilla_inicio.dart';
import 'package:agua_milena_app/presentacion/componentes/tarjeta_estadistica.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final ancho in [320.0, 768.0, 1920.0]) {
    testWidgets('inicio distribuye sus métricas a $ancho px', (tester) async {
      tester.view.physicalSize = Size(ancho, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GrillaInicio(
                children: List.generate(
                  4,
                  (i) => TarjetaEstadistica(
                    title: 'Despachos abiertos',
                    value: '$i',
                    subtitle: 'operaciones registradas',
                    icon: Icons.receipt_long,
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tarjetas = find.byType(TarjetaEstadistica);
      expect(tarjetas, findsNWidgets(4));
      expect(tester.getSize(tarjetas.first).height, 216);
      final primera = tester.getTopLeft(tarjetas.at(0));
      final ultima = tester.getTopLeft(tarjetas.at(3));
      if (ancho >= 1000) {
        expect(ultima.dy, primera.dy);
      } else {
        expect(ultima.dy, greaterThan(primera.dy));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
