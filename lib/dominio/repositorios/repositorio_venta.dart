import '../entidades/venta.dart';
import '../entidades/item_venta.dart';

abstract class RepositorioVenta {
  Future<List<Venta>> obtenerTodas();
  Future<Venta> obtenerPorId(String id);
  Future<Venta> crearVenta({
    required List<ItemCarrito> items,
    String? notas,
    String? vendedorId,
    int bidonesVaciosRecibidos = 0,
  });
  Future<void> eliminar(String id);
  Future<List<Venta>> obtenerVentasHoy();
  Future<double> obtenerTotalHoy();
  Future<double> obtenerSaldoAFavor(String vendedorId);
}
