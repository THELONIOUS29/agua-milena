import 'abono.dart';
import 'item_ruta.dart';

enum EstadoRuta { sinCierre, pendiente, parcial, pagado }

extension EstadoRutaExt on EstadoRuta {
  String get etiqueta {
    switch (this) {
      case EstadoRuta.sinCierre:
        return 'Sin cierre';
      case EstadoRuta.pendiente:
        return 'Pendiente';
      case EstadoRuta.parcial:
        return 'Abono parcial';
      case EstadoRuta.pagado:
        return 'Pagado';
    }
  }

  static EstadoRuta desdeTexto(String s) {
    switch (s) {
      case 'pendiente':
        return EstadoRuta.pendiente;
      case 'parcial':
        return EstadoRuta.parcial;
      case 'pagado':
        return EstadoRuta.pagado;
      default:
        return EstadoRuta.sinCierre;
    }
  }

  String get valor {
    switch (this) {
      case EstadoRuta.sinCierre:
        return 'sin_cierre';
      case EstadoRuta.pendiente:
        return 'pendiente';
      case EstadoRuta.parcial:
        return 'parcial';
      case EstadoRuta.pagado:
        return 'pagado';
    }
  }
}

class Ruta {
  final String id;
  final String vendedorId;
  final String nombreVendedor;
  final int vendedorBidonesPropios;
  final int vendedorBidonesLlenosActuales;
  final int vendedorBidonesVaciosActuales;
  final DateTime fecha;
  final double montoTotal;
  final double montoCobrado;
  final EstadoRuta estado;
  final String? notas;
  final DateTime creadoEn;
  final List<ItemRuta> items;
  final List<Abono> abonos;

  final int bidonesLlenosIniciales;
  final int bidonesVaciosIniciales;
  final int bidonesCargadosHoy;

  const Ruta({
    required this.id,
    required this.vendedorId,
    required this.nombreVendedor,
    this.vendedorBidonesPropios = 0,
    this.vendedorBidonesLlenosActuales = 0,
    this.vendedorBidonesVaciosActuales = 0,
    required this.fecha,
    required this.montoTotal,
    required this.montoCobrado,
    required this.estado,
    this.notas,
    required this.creadoEn,
    this.items = const [],
    this.abonos = const [],
    this.bidonesLlenosIniciales = 0,
    this.bidonesVaciosIniciales = 0,
    this.bidonesCargadosHoy = 0,
  });

  double get saldoPendiente => montoTotal - montoCobrado;
  bool get tieneSaldoAFavor => saldoPendiente < 0;
  double get saldoAFavor => tieneSaldoAFavor ? saldoPendiente.abs() : 0;
  double get saldoPendienteVisible => saldoPendiente > 0 ? saldoPendiente : 0;

  bool get estaCerrada => items.isNotEmpty && items.every((i) => i.estaCerrado);

  int get totalProductosSalida => items.fold(0, (s, i) => s + i.cantidadSalida);

  int? get totalVendidos {
    if (!estaCerrada) return null;
    return items.fold<int>(0, (s, i) => s + (i.vendidos ?? 0));
  }

  int? get totalFaltantes {
    if (!estaCerrada) return null;
    return items.fold<int>(0, (s, i) => s + (i.faltantes ?? 0));
  }

  int get bidonesEnVehiculoIniciales =>
      bidonesLlenosIniciales + bidonesVaciosIniciales;

  int get bidonesVaciosRecogidos =>
      items.fold<int>(0, (s, i) => s + (i.cantidadRetornoVacio ?? 0));

  int? get bidonesVendidos => totalVendidos;

  int? get bidonesLlenosFinales {
    final vendidos = bidonesVendidos;
    if (vendidos == null) return null;
    final value = bidonesLlenosIniciales + bidonesCargadosHoy - vendidos;
    return value < 0 ? 0 : value;
  }

  int? get bidonesVaciosFinales {
    if (!estaCerrada) return null;
    return bidonesVaciosIniciales + bidonesVaciosRecogidos;
  }

  int get bidonesPrestadosIniciales {
    final excedente = bidonesEnVehiculoIniciales - vendedorBidonesPropios;
    return excedente > 0 ? excedente : 0;
  }

  int? get bidonesPrestadosFinales {
    final llenosFinales = bidonesLlenosFinales;
    final vaciosFinales = bidonesVaciosFinales;
    if (llenosFinales == null || vaciosFinales == null) return null;
    final excedente = llenosFinales + vaciosFinales - vendedorBidonesPropios;
    return excedente > 0 ? excedente : 0;
  }

  bool get tieneBidones =>
      bidonesEnVehiculoIniciales > 0 || bidonesCargadosHoy > 0;
}
