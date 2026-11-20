class ItemRuta {
  final String id;
  final String rutaId;
  final String productoId;
  final String nombreProducto;
  final String unidad;
  final double precioUnitario;
  final int cantidadSalida;
  final int? cantidadSinVender;
  final int? cantidadRetornoVacio;

  const ItemRuta({
    required this.id,
    required this.rutaId,
    required this.productoId,
    required this.nombreProducto,
    required this.unidad,
    required this.precioUnitario,
    required this.cantidadSalida,
    this.cantidadSinVender,
    this.cantidadRetornoVacio,
  });

  int? get vendidos {
    if (cantidadSinVender == null) return null;
    return cantidadSalida - cantidadSinVender!;
  }

  int? get faltantes {
    if (cantidadSinVender == null || cantidadRetornoVacio == null) return null;
    return cantidadSalida - cantidadSinVender! - cantidadRetornoVacio!;
  }

  double get subtotal => (vendidos ?? 0) * precioUnitario;
  bool get estaCerrado => cantidadSinVender != null;
}
