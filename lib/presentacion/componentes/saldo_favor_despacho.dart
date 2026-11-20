import 'dart:math';
import 'package:flutter/material.dart';
import '../../nucleo/utilidades/utilidades_moneda.dart';

class ResumenSaldoDespacho {
  final double aplicado;
  final double pendiente;
  final double restante;

  factory ResumenSaldoDespacho.calcular({
    required double saldo,
    required double pendiente,
    required double descuento,
    required bool aplicar,
  }) {
    final disponible = max(0, (saldo * 100).round());
    final deuda = max(0, (pendiente * 100).round() - (descuento * 100).round());
    final credito = aplicar ? min(disponible, deuda) : 0;
    return ResumenSaldoDespacho._(
      credito / 100,
      (deuda - credito) / 100,
      (disponible - credito) / 100,
    );
  }

  const ResumenSaldoDespacho._(this.aplicado, this.pendiente, this.restante);
}

class SaldoFavorDespacho extends StatelessWidget {
  final double disponible;
  final ResumenSaldoDespacho resumen;
  final bool seleccionado;
  final ValueChanged<bool>? onChanged;

  const SaldoFavorDespacho({
    super.key,
    required this.disponible,
    required this.resumen,
    required this.seleccionado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Aplicar saldo a favor al despacho'),
        subtitle: Text('Disponible: ${CurrencyUtils.format(disponible)}'),
        value: seleccionado,
        onChanged: onChanged == null
            ? null
            : (value) => onChanged!(value ?? false),
      ),
      if (seleccionado) ...[
        Text(
          'Saldo a favor aplicado: ${CurrencyUtils.format(resumen.aplicado)}',
        ),
        Text(
          'Pendiente tras aplicar saldo: ${CurrencyUtils.format(resumen.pendiente)}',
        ),
        Text(
          'Saldo a favor restante: ${CurrencyUtils.format(resumen.restante)}',
        ),
        const Text(
          'El saldo se descontará al registrar el pago. No cuenta como efectivo cobrado.',
        ),
      ],
    ],
  );
}
