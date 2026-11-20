class Producto {
  final String id;
  final String nombre;
  final String? descripcion;
  final String unidad;
  final double precio;
  final int stock;
  final int stockMinimo;
  final int? stockBajoCalculado;
  final String? urlImagen;
  final CatalogoProducto catalogo;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  const Producto({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.unidad,
    required this.precio,
    required this.stock,
    required this.stockMinimo,
    this.stockBajoCalculado,
    this.urlImagen,
    this.catalogo = CatalogoProducto.distribuidora,
    required this.creadoEn,
    required this.actualizadoEn,
  });

  int get limiteStockBajo {
    if (stockBajoCalculado != null && stockBajoCalculado! >= stockMinimo) {
      return stockBajoCalculado!;
    }
    final margen = (stock * 0.10).ceil();
    return stockMinimo + (margen < 1 ? 1 : margen);
  }

  bool get esCritico => stock <= stockMinimo;
  bool get esBajo => stock <= limiteStockBajo && stock > stockMinimo;

  Producto copiarCon({
    String? id,
    String? nombre,
    String? descripcion,
    String? unidad,
    double? precio,
    int? stock,
    int? stockMinimo,
    int? stockBajoCalculado,
    String? urlImagen,
    CatalogoProducto? catalogo,
    DateTime? creadoEn,
    DateTime? actualizadoEn,
  }) => Producto(
    id: id ?? this.id,
    nombre: nombre ?? this.nombre,
    descripcion: descripcion ?? this.descripcion,
    unidad: unidad ?? this.unidad,
    precio: precio ?? this.precio,
    stock: stock ?? this.stock,
    stockMinimo: stockMinimo ?? this.stockMinimo,
    stockBajoCalculado: stockBajoCalculado ?? this.stockBajoCalculado,
    urlImagen: urlImagen ?? this.urlImagen,
    catalogo: catalogo ?? this.catalogo,
    creadoEn: creadoEn ?? this.creadoEn,
    actualizadoEn: actualizadoEn ?? this.actualizadoEn,
  );
}

enum CatalogoProducto { distribuidora, vendedor }

extension CatalogoProductoX on CatalogoProducto {
  String get valor {
    switch (this) {
      case CatalogoProducto.distribuidora:
        return 'distribuidora';
      case CatalogoProducto.vendedor:
        return 'vendedor';
    }
  }

  static CatalogoProducto desdeTexto(String? v) {
    switch (v) {
      case 'vendedor':
        return CatalogoProducto.vendedor;
      case 'distribuidora':
      default:
        return CatalogoProducto.distribuidora;
    }
  }
}
