import 'dart:async';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../modelos/producto.dart';
import 'servicio_autenticacion.dart';
import 'servicio_alertas_automaticas.dart';

class ServicioProducto {
  final SupabaseClient _client;
  final ServicioAutenticacion _authService;
  ServicioProducto({
    SupabaseClient? client,
    ServicioAutenticacion? autenticacion,
  }) : _client = client ?? Supabase.instance.client,
       _authService = autenticacion ?? ServicioAutenticacion();
  static const _esquema = 'inventario';
  static const _tabla = 'productos';
  static const _movimientos = 'movimientos_inventario';
  static const _bucket = 'product-images';
  final _uuid = const Uuid();

  SupabaseQueryBuilder _desde(String tabla) =>
      _client.schema(_esquema).from(tabla);

  // ── Imágenes ──────────────────────────────────────────────────────────────

  Future<String> subirImagen(Uint8List bytes, String extension) async {
    final nombreArchivo = '${_uuid.v4()}.$extension';
    await _client.storage
        .from(_bucket)
        .uploadBinary(
          nombreArchivo,
          bytes,
          fileOptions: FileOptions(
            contentType: 'image/$extension',
            upsert: false,
          ),
        );
    return _client.storage.from(_bucket).getPublicUrl(nombreArchivo);
  }

  Future<void> eliminarImagen(String urlImagen) async {
    final uri = Uri.parse(urlImagen);
    final nombreArchivo = uri.pathSegments.last;
    await _client.storage.from(_bucket).remove([nombreArchivo]);
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  Future<List<Producto>> obtenerTodos() async {
    final data = await _desde(_tabla).select().order('nombre', ascending: true);
    return (data as List).map((e) => Producto.desdeJson(e)).toList();
  }

  Future<Producto> obtenerPorId(String id) async {
    final data = await _desde(_tabla).select().eq('id', id).single();
    return Producto.desdeJson(data);
  }

  Future<Producto> crear(Map<String, dynamic> json) async {
    final data = await _desde(_tabla).insert(json).select().single();
    return Producto.desdeJson(data);
  }

  Future<Producto> actualizar(String id, Map<String, dynamic> json) async {
    json['actualizado_en'] = DateTime.now().toIso8601String();
    final data = await _desde(
      _tabla,
    ).update(json).eq('id', id).select().single();
    return Producto.desdeJson(data);
  }

  Future<void> eliminar(String id) async {
    await _desde(_tabla).delete().eq('id', id);
  }

  // ── Movimientos ────────────────────────────────────────────────────────────

  Future<void> registrarMovimiento({
    required String productoId,
    required String tipo,
    required int cantidad,
    String? motivo,
  }) async {
    if (productoId.trim().isEmpty ||
        (tipo != 'entrada' && tipo != 'salida') ||
        cantidad <= 0) {
      throw ArgumentError(
        'Ingresa un producto, tipo y cantidad positivos validos.',
      );
    }
    if (await _registrarMovimientoSeguro(
      productoId: productoId,
      tipo: tipo,
      cantidad: cantidad,
      motivo: motivo,
    )) {
      unawaited(
        ServicioAlertasAutomaticas().solicitarRevision(
          motivo: 'movimiento_inventario',
        ),
      );
      return;
    }

    final producto = await obtenerPorId(productoId);
    if (tipo == 'salida' && producto.stock < cantidad) {
      throw StateError(
        'Stock insuficiente para ${producto.nombre}. Disponible: ${producto.stock}.',
      );
    }
    final nuevoStock = tipo == 'entrada'
        ? producto.stock + cantidad
        : producto.stock - cantidad;
    await _desde(_tabla)
        .update({
          'stock': nuevoStock,
          'actualizado_en': DateTime.now().toIso8601String(),
        })
        .eq('id', productoId);
    await _desde(_movimientos).insert({
      'producto_id': productoId,
      'tipo': tipo,
      'cantidad': cantidad,
      'motivo': motivo,
    });
    unawaited(
      ServicioAlertasAutomaticas().solicitarRevision(
        motivo: 'movimiento_inventario',
      ),
    );
  }

  Future<bool> _registrarMovimientoSeguro({
    required String productoId,
    required String tipo,
    required int cantidad,
    String? motivo,
  }) async {
    final sessionToken = await _authService.obtenerTokenSesion();
    if (sessionToken == null || sessionToken.trim().isEmpty) {
      throw StateError('Inicia sesion para registrar movimientos.');
    }

    try {
      await _client
          .schema(_esquema)
          .rpc(
            'fn_registrar_movimiento_seguro',
            params: {
              'p_session_token': sessionToken,
              'p_producto_id': productoId,
              'p_tipo': tipo,
              'p_cantidad': cantidad,
              'p_motivo': motivo,
            },
          );
      return true;
    } on PostgrestException catch (error) {
      if (_rpcNoDisponible(error)) {
        throw StateError('Falta aplicar el RPC seguro de inventario.');
      }
      rethrow;
    }
  }

  bool _rpcNoDisponible(PostgrestException error) {
    return error.code == 'PGRST202' ||
        error.code == 'PGRST204' ||
        error.code == '42883';
  }

  Future<List<Map<String, dynamic>>> obtenerMovimientos(
    String productoId, {
    int limite = 10,
  }) async {
    final limiteSeguro = limite.clamp(1, 50);
    final data = await _desde(_movimientos)
        .select('id, tipo, cantidad, motivo, creado_en')
        .eq('producto_id', productoId)
        .order('creado_en', ascending: false)
        .limit(limiteSeguro);
    return List<Map<String, dynamic>>.from(data as List);
  }

  Future<List<Producto>> obtenerStockCritico() async {
    final todos = await obtenerTodos();
    return todos.where((p) => p.esCritico).toList();
  }
}
