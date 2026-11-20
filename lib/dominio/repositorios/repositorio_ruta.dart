import '../entidades/ruta.dart';
import '../entidades/item_ruta.dart';

abstract class RepositorioRuta {
  Future<List<Ruta>> obtenerTodas();
  Future<List<Ruta>> obtenerPorVendedor(String vendedorId);
  Future<Ruta> obtenerPorId(String id);
  Future<Ruta> crear({
    required String vendedorId,
    required List<dynamic> items,
    String? notas,
    int bidonesCargadosHoy = 0,
  });
  Future<Ruta> cerrarRuta({
    required String rutaId,
    required List<ItemRuta> itemsConRetorno,
  });
  Future<Ruta> registrarAbono({
    required String rutaId,
    required double monto,
    String? nota,
  });
  Future<void> eliminar(String id);
}
