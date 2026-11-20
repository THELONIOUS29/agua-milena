import '../entidades/vendedor.dart';

abstract class RepositorioVendedor {
  Future<List<Vendedor>> obtenerTodos();
  Future<List<Vendedor>> obtenerActivos();
  Future<Vendedor> crear(
    String nombre,
    String? telefono, {
    int bidonesPropios = 0,
    int bidonesPrestados = 0,
    int bidonesLlenosActuales = 0,
    int bidonesVaciosActuales = 0,
  });
  Future<void> actualizar(
    String id, {
    String? nombre,
    String? telefono,
    bool? activo,
    int? bidonesPropios,
    int? bidonesPrestados,
    int? bidonesLlenosActuales,
    int? bidonesVaciosActuales,
  });
  Future<void> eliminar(String id);
}
