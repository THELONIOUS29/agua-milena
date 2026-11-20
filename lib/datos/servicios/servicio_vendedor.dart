import 'package:supabase_flutter/supabase_flutter.dart';
import '../modelos/vendedor.dart';

class ServicioVendedor {
  final _client = Supabase.instance.client;
  static const _esquema = 'vendedores';
  static const _tabla = 'vendedores';

  SupabaseQueryBuilder _desde(String tabla) =>
      _client.schema(_esquema).from(tabla);

  Future<List<Vendedor>> obtenerTodos() async {
    final data = await _desde(_tabla).select().order('nombre', ascending: true);
    return (data as List).map((e) => Vendedor.desdeJson(e)).toList();
  }

  Future<List<Vendedor>> obtenerActivos() async {
    final data = await _desde(
      _tabla,
    ).select().eq('activo', true).order('nombre', ascending: true);
    return (data as List).map((e) => Vendedor.desdeJson(e)).toList();
  }

  Future<Vendedor> crear(
    String nombre,
    String? telefono, {
    int bidonesPropios = 0,
    int bidonesPrestados = 0,
    int bidonesLlenosActuales = 0,
    int bidonesVaciosActuales = 0,
  }) async {
    final data = await _desde(_tabla)
        .insert({
          'nombre': nombre,
          if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
          'activo': true,
          'bidones_propios': bidonesPropios,
          'bidones_prestados': bidonesPrestados,
          'bidones_llenos_actuales': bidonesLlenosActuales,
          'bidones_vacios_actuales': bidonesVaciosActuales,
        })
        .select()
        .single();
    return Vendedor.desdeJson(data);
  }

  Future<void> actualizar(
    String id, {
    String? nombre,
    String? telefono,
    bool? activo,
    int? bidonesPropios,
    int? bidonesPrestados,
    int? bidonesLlenosActuales,
    int? bidonesVaciosActuales,
  }) async {
    final payload = <String, dynamic>{};
    if (nombre != null) payload['nombre'] = nombre;
    if (telefono != null) payload['telefono'] = telefono;
    if (activo != null) payload['activo'] = activo;
    if (bidonesPropios != null) payload['bidones_propios'] = bidonesPropios;
    if (bidonesPrestados != null) {
      payload['bidones_prestados'] = bidonesPrestados;
    }
    if (bidonesLlenosActuales != null) {
      payload['bidones_llenos_actuales'] = bidonesLlenosActuales;
    }
    if (bidonesVaciosActuales != null) {
      payload['bidones_vacios_actuales'] = bidonesVaciosActuales;
    }
    if (payload.isNotEmpty) {
      await _desde(_tabla).update(payload).eq('id', id);
    }
  }

  Future<void> eliminar(String id) async {
    await _desde(_tabla).delete().eq('id', id);
  }
}
