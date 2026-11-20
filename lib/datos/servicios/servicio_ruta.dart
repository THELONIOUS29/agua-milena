import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../modelos/ruta.dart';
import '../modelos/item_ruta.dart';
import 'servicio_alertas_automaticas.dart';
import 'servicio_notificacion.dart';
import 'servicio_autenticacion.dart';

class ServicioRuta {
  final SupabaseClient _client;
  ServicioRuta({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  static const _esquemaRutas = 'rutas';
  static const _esquemaVendedores = 'vendedores';
  static const _esquemaInventario = 'inventario';

  SupabaseQueryBuilder _desde(String esquema, String tabla) =>
      _client.schema(esquema).from(tabla);

  // ── Consultas ──────────────────────────────────────────────────────────────

  Future<List<Ruta>> obtenerTodas() async {
    final data = await _desde(
      _esquemaRutas,
      'v_rutas',
    ).select().order('creado_en', ascending: false);
    return (data as List).map((e) => Ruta.desdeJson(e)).toList();
  }

  Future<Ruta> obtenerPorId(String id) async {
    final data = await _desde(
      _esquemaRutas,
      'v_rutas',
    ).select().eq('id', id).single();
    return Ruta.desdeJson(data);
  }

  Future<List<Ruta>> obtenerPorVendedor(String vendedorId) async {
    final data = await _desde(
      _esquemaRutas,
      'v_rutas',
    ).select().eq('vendedor_id', vendedorId).order('fecha', ascending: false);
    return (data as List).map((e) => Ruta.desdeJson(e)).toList();
  }

  // ── Crear ruta ─────────────────────────────────────────────────────────────

  Future<Ruta> crearRuta({
    required String vendedorId,
    required List<ItemRutaBorrador> items,
    String? notas,
    int bidonesCargadosHoy = 0,
  }) async {
    final hoy = DateTime.now().toIso8601String().substring(0, 10);
    final rutaAbiertaId = await _buscarRutaActiva(vendedorId: vendedorId);
    if (rutaAbiertaId != null) {
      await _actualizarRutaExistente(
        rutaId: rutaAbiertaId,
        items: items,
        notas: notas,
        bidonesCargadosHoy: bidonesCargadosHoy,
      );
      return obtenerPorId(rutaAbiertaId);
    }

    // Obtener estado actual del vendedor
    final vendedorData = await _desde(
      _esquemaVendedores,
      'vendedores',
    ).select().eq('id', vendedorId).single();

    final llenosActuales = vendedorData['bidones_llenos_actuales'] as int? ?? 0;
    final vaciosActuales = vendedorData['bidones_vacios_actuales'] as int? ?? 0;

    // 1. Crear la ruta
    final rutaData = await _desde(_esquemaRutas, 'rutas')
        .insert({
          'vendedor_id': vendedorId,
          'fecha': hoy,
          'estado': 'sin_cierre',
          if (notas != null && notas.isNotEmpty) 'notas': notas,
          'bidones_llenos_iniciales': llenosActuales,
          'bidones_vacios_iniciales': vaciosActuales,
          'bidones_cargados_hoy': bidonesCargadosHoy,
        })
        .select()
        .single();

    final rutaId = rutaData['id'] as String;

    // 2. Insertar items
    final itemsConCantidad = items.where((i) => i.cantidadSalida > 0).toList();
    if (itemsConCantidad.isNotEmpty) {
      await _desde(_esquemaRutas, 'items_ruta').insert(
        itemsConCantidad
            .map(
              (i) => {
                'ruta_id': rutaId,
                'producto_id': i.productoId,
                'nombre_producto': i.nombreProducto,
                'unidad': i.unidad,
                'precio_unitario': i.precioUnitario,
                'cantidad_salida': i.cantidadSalida,
              },
            )
            .toList(),
      );

      // 3. Descontar stock de inventario
      for (final item in itemsConCantidad) {
        final producto = await _desde(
          _esquemaInventario,
          'productos',
        ).select('stock').eq('id', item.productoId).single();
        final stockActual = producto['stock'] as int;
        await _desde(_esquemaInventario, 'productos')
            .update({
              'stock': stockActual - item.cantidadSalida,
              'actualizado_en': DateTime.now().toIso8601String(),
            })
            .eq('id', item.productoId);
      }
    }

    return obtenerPorId(rutaId);
  }

  Future<String?> _buscarRutaActiva({required String vendedorId}) async {
    final rutas = await _desde(_esquemaRutas, 'rutas')
        .select('id')
        .eq('vendedor_id', vendedorId)
        .inFilter('estado', ['sin_cierre', 'pendiente', 'parcial'])
        .order('fecha', ascending: true)
        .order('creado_en', ascending: true)
        .limit(1);

    if ((rutas as List).isEmpty) return null;
    return rutas.first['id'] as String;
  }

  Future<void> _actualizarRutaExistente({
    required String rutaId,
    required List<ItemRutaBorrador> items,
    String? notas,
    int bidonesCargadosHoy = 0,
  }) async {
    final ruta = await _desde(
      _esquemaRutas,
      'rutas',
    ).select('bidones_cargados_hoy, notas').eq('id', rutaId).single();
    final cargadosActuales = ruta['bidones_cargados_hoy'] as int? ?? 0;
    final notasActuales = ruta['notas'] as String?;

    await _desde(_esquemaRutas, 'rutas')
        .update({
          'bidones_cargados_hoy': cargadosActuales + bidonesCargadosHoy,
          if (notas != null && notas.trim().isNotEmpty)
            'notas': [
              if (notasActuales != null && notasActuales.trim().isNotEmpty)
                notasActuales.trim(),
              notas.trim(),
            ].join('\n'),
        })
        .eq('id', rutaId);

    final itemsConCantidad = items.where((i) => i.cantidadSalida > 0).toList();
    if (itemsConCantidad.isEmpty) return;

    await _desde(_esquemaRutas, 'items_ruta').insert(
      itemsConCantidad
          .map(
            (i) => {
              'ruta_id': rutaId,
              'producto_id': i.productoId,
              'nombre_producto': i.nombreProducto,
              'unidad': i.unidad,
              'precio_unitario': i.precioUnitario,
              'cantidad_salida': i.cantidadSalida,
            },
          )
          .toList(),
    );

    for (final item in itemsConCantidad) {
      final producto = await _desde(
        _esquemaInventario,
        'productos',
      ).select('stock').eq('id', item.productoId).single();
      final stockActual = producto['stock'] as int;
      await _desde(_esquemaInventario, 'productos')
          .update({
            'stock': stockActual - item.cantidadSalida,
            'actualizado_en': DateTime.now().toIso8601String(),
          })
          .eq('id', item.productoId);
    }
  }

  // ── Cerrar ruta ────────────────────────────────────────────────────────────

  Future<Ruta> cerrarRuta({
    required String rutaId,
    required List<ItemRuta> itemsConRetorno,
  }) async {
    // Actualizar items con cantidades de retorno
    for (final item in itemsConRetorno) {
      await _desde(_esquemaRutas, 'items_ruta')
          .update({
            'cantidad_sin_vender': item.cantidadSinVender,
            'cantidad_retorno_vacio': item.cantidadRetornoVacio,
          })
          .eq('id', item.id);
    }

    // Recalcular ruta
    await _recalcularRuta(rutaId);
    unawaited(
      ServicioAlertasAutomaticas().solicitarRevision(motivo: 'ruta_cerrada'),
    );
    return obtenerPorId(rutaId);
  }

  Future<void> _recalcularRuta(String rutaId) async {
    final ruta = await obtenerPorId(rutaId);
    if (!ruta.estaCerrada) return;

    // Calcular monto total basado en vendidos
    double montoTotal = 0;
    for (final item in ruta.items) {
      montoTotal += item.subtotal;
    }

    // Determinar estado
    String estado;
    if (ruta.montoCobrado >= montoTotal) {
      estado = 'pagado';
    } else if (ruta.montoCobrado > 0) {
      estado = 'parcial';
    } else {
      estado = 'pendiente';
    }

    await _desde(
      _esquemaRutas,
      'rutas',
    ).update({'monto_total': montoTotal, 'estado': estado}).eq('id', rutaId);

    // Actualizar bidones del vendedor
    final vendedorData = await _desde(
      _esquemaVendedores,
      'vendedores',
    ).select().eq('id', ruta.vendedorId).single();
    final propios = vendedorData['bidones_propios'] as int? ?? 0;

    final llenosFinales = ruta.bidonesLlenosFinales ?? 0;
    final vaciosFinales = ruta.bidonesVaciosFinales ?? 0;
    final prestados = ((llenosFinales + vaciosFinales) - propios).clamp(
      0,
      999999,
    );

    await _desde(_esquemaVendedores, 'vendedores')
        .update({
          'bidones_llenos_actuales': llenosFinales,
          'bidones_vacios_actuales': vaciosFinales,
          'bidones_prestados': prestados,
        })
        .eq('id', ruta.vendedorId);
  }

  // ── Abonos ─────────────────────────────────────────────────────────────────

  Future<double> obtenerSaldoAFavorDisponible(Ruta destino) async {
    final data = await _desde(_esquemaRutas, 'rutas')
        .select('monto_total, monto_cobrado')
        .eq('vendedor_id', destino.vendedorId)
        .neq('id', destino.id);
    return (data as List).fold<double>(0, (suma, fila) {
      final exceso =
          (fila['monto_cobrado'] as num).toDouble() -
          (fila['monto_total'] as num).toDouble();
      return suma + (exceso > 0 ? exceso : 0);
    });
  }

  Future<Ruta> registrarPagoConDescuento({
    required String rutaId,
    required double montoEfectivo,
    required double descuento,
    String? nota,
    double credito = 0,
    String? operacionId,
  }) async {
    if (!montoEfectivo.isFinite ||
        !descuento.isFinite ||
        !credito.isFinite ||
        credito < 0 ||
        montoEfectivo < 0 ||
        descuento < 0 ||
        montoEfectivo + descuento + credito <= 0 ||
        (credito > 0 && operacionId == null)) {
      throw ArgumentError('Ingresa un pago o descuento valido.');
    }
    final token = await ServicioAutenticacion().obtenerTokenSesion();
    if (token == null || token.isEmpty) {
      throw StateError('Inicia sesion para registrar el pago.');
    }
    try {
      await _client
          .schema(_esquemaRutas)
          .rpc(
            credito > 0
                ? 'fn_registrar_pago_con_saldo'
                : 'fn_registrar_pago_con_descuento',
            params: {
              'p_session_token': token,
              'p_ruta_id': rutaId,
              'p_monto': montoEfectivo,
              'p_descuento': descuento,
              'p_nota': nota,
              if (credito > 0) 'p_credito': credito,
              if (credito > 0) 'p_operacion_id': operacionId,
            },
          );
    } on PostgrestException catch (error) {
      if (credito > 0 && error.code == 'PGRST202') {
        throw StateError(
          'Falta aplicar el parche SQL de saldo a favor en despachos.',
        );
      }
      if (error.message.contains('credit balance changed') ||
          error.message.contains('exceeds pending balance')) {
        throw StateError(
          'El saldo cambió. Actualiza el despacho y revisa los importes antes de confirmar.',
        );
      }
      rethrow;
    }
    final ruta = await obtenerPorId(rutaId);
    if (ruta.estado == EstadoRuta.pagado) {
      await ServicioNotificacion().cancelarNotificacion(
        _idNotificacionRuta(rutaId),
      );
    }
    unawaited(
      ServicioAlertasAutomaticas().solicitarRevision(motivo: 'abono_ruta'),
    );
    return ruta;
  }

  Future<Ruta> registrarAbono({
    required String rutaId,
    required double monto,
    String? nota,
  }) async {
    if (!monto.isFinite || monto <= 0 || rutaId.trim().isEmpty) {
      throw ArgumentError('Ingresa una ruta y un abono positivo valido.');
    }
    await _desde(_esquemaRutas, 'abonos').insert({
      'ruta_id': rutaId,
      'monto': monto,
      'fecha': DateTime.now().toIso8601String(),
      if (nota != null && nota.isNotEmpty) 'nota': nota,
    });

    // Actualizar monto cobrado
    final ruta = await obtenerPorId(rutaId);
    final nuevoCobrado = ruta.abonos.fold<double>(0, (s, a) => s + a.monto);

    String estado;
    if (nuevoCobrado >= ruta.montoTotal) {
      estado = 'pagado';
    } else if (nuevoCobrado > 0) {
      estado = 'parcial';
    } else {
      estado = 'pendiente';
    }

    await _desde(_esquemaRutas, 'rutas')
        .update({'monto_cobrado': nuevoCobrado, 'estado': estado})
        .eq('id', rutaId);

    if (estado == 'pagado') {
      await ServicioNotificacion().cancelarNotificacion(
        _idNotificacionRuta(rutaId),
      );
    }
    unawaited(
      ServicioAlertasAutomaticas().solicitarRevision(motivo: 'abono_ruta'),
    );

    return obtenerPorId(rutaId);
  }

  int _idNotificacionRuta(String rutaId) {
    var valor = 17;
    for (final codigo in rutaId.codeUnits) {
      valor = (valor * 31 + codigo) & 0x7fffffff;
    }
    return valor;
  }

  Future<void> eliminar(String id) async {
    await _desde(_esquemaRutas, 'rutas').delete().eq('id', id);
    await ServicioNotificacion().cancelarNotificacion(_idNotificacionRuta(id));
  }

  Future<void> actualizarNota(String id, String? notas) async {
    await _desde(_esquemaRutas, 'rutas').update({'notas': notas}).eq('id', id);
  }
}
