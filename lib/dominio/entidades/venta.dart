import 'item_venta.dart';

class Venta {
  final String id;
  final DateTime fecha;
  final double total;
  final String? notas;
  final String? vendedorId;
  final String? nombreVendedor;
  final double creditoAplicado;
  final DateTime creadoEn;
  final List<ItemVenta> items;

  const Venta({
    required this.id,
    required this.fecha,
    required this.total,
    this.notas,
    this.vendedorId,
    this.nombreVendedor,
    this.creditoAplicado = 0,
    required this.creadoEn,
    this.items = const [],
  });

  /// Nombre a mostrar: vendedor asignado o "Distribuidora"
  String get mostrarVendedor => nombreVendedor ?? 'Distribuidora';

  /// Total efectivo después de aplicar crédito
  double get totalEfectivo =>
      (total - creditoAplicado).clamp(0, double.infinity);
}
