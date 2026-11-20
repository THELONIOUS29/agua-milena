class ItemVenta {
  final String id;
  final String ventaId;
  final String productoId;
  final String nombreProducto;
  final int cantidad;
  final double precioUnitario;
  final double subtotal;

  const ItemVenta({
    required this.id,
    required this.ventaId,
    required this.productoId,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
  });
}

/// Modelo temporal para el carrito de nueva venta (no persiste en BD)
class ItemCarrito {
  final String productoId;
  final String nombreProducto;
  final double precioUnitario;
  final String unidad;
  int cantidad;

  ItemCarrito({
    required this.productoId,
    required this.nombreProducto,
    required this.precioUnitario,
    required this.unidad,
    this.cantidad = 1,
  });

  double get subtotal => precioUnitario * cantidad;

  Map<String, dynamic> aJsonItemVenta(String ventaId) => {
    'venta_id': ventaId,
    'producto_id': productoId,
    'cantidad': cantidad,
    'precio_unitario': precioUnitario,
    'subtotal': subtotal,
  };
}
