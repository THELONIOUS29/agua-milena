import 'dart:typed_data';
import '../entidades/producto.dart';

abstract class RepositorioProducto {
  Future<List<Producto>> obtenerTodos();
  Future<Producto> obtenerPorId(String id);
  Future<Producto> crear(Map<String, dynamic> datos);
  Future<Producto> actualizar(String id, Map<String, dynamic> datos);
  Future<void> eliminar(String id);
  Future<List<Producto>> obtenerStockCritico();
  Future<String> subirImagen(Uint8List bytes, String extension);
  Future<void> eliminarImagen(String urlImagen);
  Future<void> registrarMovimiento({
    required String productoId,
    required String tipo,
    required int cantidad,
    String? motivo,
  });
  Future<List<Map<String, dynamic>>> obtenerMovimientos(
    String productoId, {
    int limite = 10,
  });
}
