class Vendedor {
  final String id;
  final String nombre;
  final String? telefono;
  final bool activo;
  final int bidonesPropios;
  final int bidonesPrestados;
  final int bidonesLlenosActuales;
  final int bidonesVaciosActuales;
  final DateTime creadoEn;

  const Vendedor({
    required this.id,
    required this.nombre,
    this.telefono,
    required this.activo,
    this.bidonesPropios = 0,
    this.bidonesPrestados = 0,
    this.bidonesLlenosActuales = 0,
    this.bidonesVaciosActuales = 0,
    required this.creadoEn,
  });

  /// Opción especial para ventas desde la distribuidora
  static Vendedor get distribuidora => Vendedor(
    id: '',
    nombre: 'Distribuidora',
    creadoEn: DateTime(2000),
    activo: true,
  );

  bool get esDistribuidora => id.isEmpty;

  Vendedor copiarCon({
    String? nombre,
    String? telefono,
    bool? activo,
    int? bidonesPropios,
    int? bidonesPrestados,
    int? bidonesLlenosActuales,
    int? bidonesVaciosActuales,
  }) => Vendedor(
    id: id,
    nombre: nombre ?? this.nombre,
    telefono: telefono ?? this.telefono,
    activo: activo ?? this.activo,
    bidonesPropios: bidonesPropios ?? this.bidonesPropios,
    bidonesPrestados: bidonesPrestados ?? this.bidonesPrestados,
    bidonesLlenosActuales: bidonesLlenosActuales ?? this.bidonesLlenosActuales,
    bidonesVaciosActuales: bidonesVaciosActuales ?? this.bidonesVaciosActuales,
    creadoEn: creadoEn,
  );
}
