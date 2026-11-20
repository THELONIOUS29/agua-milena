import 'package:supabase_flutter/supabase_flutter.dart';
import '../modelos/precio_producto.dart';

class ServicioPrecio {
  final _client = Supabase.instance.client;
  static const _esquema = 'inventario';
  static const _tabla = 'precios_producto';

  SupabaseQueryBuilder _desde() => _client.schema(_esquema).from(_tabla);

  Future<List<PrecioProducto>> obtenerTodos() async {
    final data = await _desde().select();
    return (data as List).map((e) => PrecioProducto.desdeJson(e)).toList();
  }

  Future<List<PrecioProducto>> obtenerPorProducto(String productoId) async {
    final data = await _desde().select().eq('producto_id', productoId);
    return (data as List).map((e) => PrecioProducto.desdeJson(e)).toList();
  }

  Future<List<PrecioProducto>> obtenerPorVendedor(String? vendedorId) async {
    final query = _desde().select();
    final data = vendedorId == null || vendedorId.isEmpty
        ? await query.filter('vendedor_id', 'is', null)
        : await query.eq('vendedor_id', vendedorId);
    return (data as List).map((e) => PrecioProducto.desdeJson(e)).toList();
  }

  Future<PrecioProducto?> obtenerPrecioEspecifico(
    String productoId,
    String? vendedorId,
  ) async {
    final query = _desde().select().eq('producto_id', productoId);
    final data = vendedorId == null || vendedorId.isEmpty
        ? await query.filter('vendedor_id', 'is', null).maybeSingle()
        : await query.eq('vendedor_id', vendedorId).maybeSingle();

    if (data == null) return null;
    return PrecioProducto.desdeJson(data);
  }

  Future<PrecioProducto> guardarPrecio({
    required String productoId,
    String? vendedorId,
    required double precio,
  }) async {
    if (!precio.isFinite || precio < 0) {
      throw ArgumentError('Ingresa un precio mayor o igual a cero.');
    }
    final payload = {
      'producto_id': productoId,
      'vendedor_id': vendedorId != null && vendedorId.isNotEmpty
          ? vendedorId
          : null,
      'precio': precio,
      'actualizado_en': DateTime.now().toIso8601String(),
    };

    final data = await _desde()
        .upsert(payload, onConflict: 'producto_id,vendedor_id')
        .select()
        .single();

    return PrecioProducto.desdeJson(data);
  }

  Future<void> eliminarPrecio(String id) async {
    await _desde().delete().eq('id', id);
  }
}
