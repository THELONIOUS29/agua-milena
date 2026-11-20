import 'package:agua_milena_app/presentacion/componentes/saldo_favor_despacho.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no consume crédito sin selección', () {
    final r = ResumenSaldoDespacho.calcular(
      saldo: 14.83,
      pendiente: 103.35,
      descuento: 0,
      aplicar: false,
    );
    expect(r.aplicado, 0);
    expect(r.pendiente, 103.35);
    expect(r.restante, 14.83);
  });
  test('aplica saldo parcial con precisión de centavos', () {
    final r = ResumenSaldoDespacho.calcular(
      saldo: 14.83,
      pendiente: 103.35,
      descuento: 3.52,
      aplicar: true,
    );
    expect(r.aplicado, 14.83);
    expect(r.pendiente, 85);
    expect(r.restante, 0);
  });
  test('limita el crédito al pendiente y conserva el excedente', () {
    final r = ResumenSaldoDespacho.calcular(
      saldo: 100,
      pendiente: 30,
      descuento: 5,
      aplicar: true,
    );
    expect(r.aplicado, 25);
    expect(r.pendiente, 0);
    expect(r.restante, 75);
  });
  testWidgets('permite seleccionar y revisar el saldo sin registrar efectivo', (
    tester,
  ) async {
    var seleccionado = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SaldoFavorDespacho(
              disponible: 20,
              resumen: ResumenSaldoDespacho.calcular(
                saldo: 20,
                pendiente: 50,
                descuento: 0,
                aplicar: seleccionado,
              ),
              seleccionado: seleccionado,
              onChanged: (value) => setState(() => seleccionado = value),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Pendiente tras aplicar'), findsNothing);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(seleccionado, isTrue);
    expect(find.textContaining('Pendiente tras aplicar'), findsOneWidget);
    expect(find.textContaining('No cuenta como efectivo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
