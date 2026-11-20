class Abono {
  final String id;
  final String rutaId;
  final double monto;
  final DateTime fecha;
  final String? nota;

  const Abono({
    required this.id,
    required this.rutaId,
    required this.monto,
    required this.fecha,
    this.nota,
  });
}
