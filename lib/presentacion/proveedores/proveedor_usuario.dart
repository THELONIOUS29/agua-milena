import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'proveedor_autenticacion.dart';

final proveedorUsuarios = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final userService = ref.read(proveedorServicioUsuario);
  return await userService.obtenerTodos();
});
