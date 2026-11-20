import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../modelos/venta.dart';
import '../modelos/item_venta.dart';
import 'servicio_autenticacion.dart';
import 'servicio_alertas_automaticas.dart';
import 'servicio_notificacion.dart';

class ResumenVentas {
  final int cantidad;
  final double total;

  const ResumenVentas({required this.cantidad, required this.total});

  static const vacio = ResumenVentas(cantidad: 0, total: 0);
}

class ServicioVenta {
  final SupabaseClient _client;
  final ServicioAutenticacion _authService;
  final ServicioAlertasAutomaticas _alertas;
  ServicioVenta({
    SupabaseClient? client,
    ServicioAutenticacion? autenticacion,
    ServicioAlertasAutomaticas? alertas,
  }) : _client = client ?? Supabase.instance.client,
       _authService = autenticacion ?? ServicioAutenticacion(),
       _alertas = alertas ?? ServicioAlertasAutomaticas();
  static const _esquemaVentas = 'ventas';
  static const _esquemaVendedores = 'vendedores';
  static const _esquemaRutas = 'rutas';
  static const _esquemaInventario = 'inventario';

  SupabaseQueryBuilder _desde(String esquema, String tabla) =>
      _client.schema(esquema).from(tabla);

  // ── Consultas ──────────────────────────────────────────────────────────────

  Future<List<Venta>> obtenerTodas() async {
    final data = await _desde(
      _esquemaVentas,
      'v_ventas',
    ).select().order('creado_en', ascending: false);
    return (data as List).map((e) => Venta.desdeJson(e)).toList();
  }

  Future<List<Venta>> obtenerRecientes({int limite = 30}) async {
    final limiteSeguro = limite.clamp(1, 100);
    final data = await _desde(
      _esquemaVentas,
      'v_ventas',
    ).select().order('creado_en', ascending: false).limit(limiteSeguro);
    return (data as List).map((e) => Venta.desdeJson(e)).toList();
  }

  Future<List<Venta>> consultarPorFiltros({
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? vendedorId,
    int limite = 300,
  }) async {
    final limiteSeguro = limite.clamp(1, 500);
    var query = _desde(_esquemaVentas, 'v_ventas')
        .select()
        .gte('fecha', _fechaSql(fechaInicio))
        .lte('fecha', _fechaSql(fechaFin));

    if (vendedorId != null) {
      query = vendedorId.isEmpty
          ? query.isFilter('vendedor_id', null)
          : query.eq('vendedor_id', vendedorId);
    }

    final data = await query
        .order('fecha', ascending: false)
        .order('creado_en', ascending: false)
        .limit(limiteSeguro);
    return (data as List).map((e) => Venta.desdeJson(e)).toList();
  }

  Future<ResumenVentas> resumirPorFiltros({
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? vendedorId,
  }) async {
    try {
      final data = await _client
          .schema(_esquemaVentas)
          .rpc(
            'fn_resumen_ventas',
            params: {
              'p_fecha_inicio': _fechaSql(fechaInicio),
              'p_fecha_fin': _fechaSql(fechaFin),
              'p_vendedor_id': vendedorId?.isEmpty == true ? null : vendedorId,
              'p_solo_distribuidora': vendedorId?.isEmpty == true,
            },
          );
      return _parseResumenVentas(data);
    } catch (_) {
      return _resumirPorFiltrosLocal(
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        vendedorId: vendedorId,
      );
    }
  }

  Future<Venta> obtenerPorId(String id) async {
    final data = await _desde(
      _esquemaVentas,
      'v_ventas',
    ).select().eq('id', id).single();
    return Venta.desdeJson(data);
  }

  Future<void> actualizarNota(String id, String? notas) async {
    await _desde(
      _esquemaVentas,
      'ventas',
    ).update({'notas': notas}).eq('id', id);
  }

  Future<List<Venta>> obtenerVentasHoy() async {
    final hoy = _fechaSql(DateTime.now());
    final data = await _desde(
      _esquemaVentas,
      'v_ventas',
    ).select().eq('fecha', hoy).order('creado_en', ascending: false);
    return (data as List).map((e) => Venta.desdeJson(e)).toList();
  }

  Future<double> obtenerTotalHoy() async {
    final hoy = _fechaSql(DateTime.now());
    final data = await _desde(
      _esquemaVentas,
      'ventas',
    ).select('total').eq('fecha', hoy);
    return (data as List).fold<double>(
      0,
      (s, e) => s + (e['total'] as num).toDouble(),
    );
  }

  // ── Saldo a favor ─────────────────────────────────────────────────────────

  /// Obtiene el saldo a favor total de un vendedor (de rutas donde pagó de más)
  Future<double> obtenerSaldoAFavor(String vendedorId) async {
    final data = await _desde(
      _esquemaRutas,
      'rutas',
    ).select('monto_total, monto_cobrado').eq('vendedor_id', vendedorId);

    double saldoAFavor = 0;
    for (final ruta in data as List) {
      final total = (ruta['monto_total'] as num).toDouble();
      final cobrado = (ruta['monto_cobrado'] as num).toDouble();
      if (cobrado > total) {
        saldoAFavor += cobrado - total;
      }
    }
    return saldoAFavor;
  }

  /// Consume saldo a favor de las rutas del vendedor
  Future<void> _consumirSaldoAFavor(
    String vendedorId,
    double montoAConsumir,
  ) async {
    if (montoAConsumir <= 0) return;

    final data = await _desde(_esquemaRutas, 'rutas')
        .select('id, monto_total, monto_cobrado')
        .eq('vendedor_id', vendedorId)
        .order('creado_en', ascending: true);

    double restante = montoAConsumir;
    for (final ruta in data as List) {
      if (restante <= 0) break;
      final total = (ruta['monto_total'] as num).toDouble();
      final cobrado = (ruta['monto_cobrado'] as num).toDouble();
      final excedente = cobrado - total;
      if (excedente > 0) {
        final consumir = excedente < restante ? excedente : restante;
        await _desde(
          _esquemaRutas,
          'rutas',
        ).update({'monto_cobrado': cobrado - consumir}).eq('id', ruta['id']);
        restante -= consumir;
      }
    }
  }

  // ── Crear venta ────────────────────────────────────────────────────────────

  Future<Venta> crearVenta({
    required List<ItemCarrito> items,
    String? notas,
    String? vendedorId,
    int bidonesLlenosEnCarro = 0,
    int bidonesVaciosRecibidos = 0,
    bool aplicarSaldoAFavor = false,
  }) async {
    if (items.isEmpty ||
        bidonesLlenosEnCarro < 0 ||
        bidonesVaciosRecibidos < 0 ||
        items.any(
          (i) =>
              i.productoId.trim().isEmpty ||
              i.cantidad < 0 ||
              i.devolucion < 0 ||
              (i.cantidad == 0 && i.devolucion == 0) ||
              !i.precioUnitario.isFinite ||
              i.precioUnitario < 0,
        )) {
      throw ArgumentError('La venta necesita productos y cantidades validas.');
    }
    final estadoAlertasPrevio = await _alertas.capturarEstadoActual();
    final ventaSeguraId = await _crearVentaSegura(
      items: items,
      notas: notas,
      vendedorId: vendedorId,
      bidonesLlenosEnCarro: bidonesLlenosEnCarro,
      bidonesVaciosRecibidos: bidonesVaciosRecibidos,
      aplicarSaldoAFavor: aplicarSaldoAFavor,
    );
    if (ventaSeguraId != null) {
      final venta = await obtenerPorId(ventaSeguraId);
      unawaited(
        _alertas.notificarAlertasNuevas(
          motivo: 'venta_registrada',
          estadoPrevio: estadoAlertasPrevio,
        ),
      );
      return venta;
    }

    // These operations require the atomic RPC and its current validations.
    if (aplicarSaldoAFavor || items.any((item) => item.devolucion > 0)) {
      throw StateError(
        'Actualiza el parche SQL antes de registrar esta venta.',
      );
    }

    final total = items.fold<double>(0, (s, item) => s + item.subtotal);
    final totalDevoluciones = items.fold<double>(
      0,
      (s, item) => s + item.creditoDevolucion,
    );
    final totalNeto = (total - totalDevoluciones).clamp(0.0, double.infinity);
    final bidonesCargados = items
        .where((item) => item.esBidon)
        .fold<int>(0, (s, item) => s + item.cantidad);
    final bidonesPrestadosEmpresa = (bidonesCargados - bidonesVaciosRecibidos)
        .clamp(0, 999999)
        .toInt();
    final esVentaVendedor = vendedorId != null && vendedorId.isNotEmpty;
    String? rutaId;

    // Calcular crédito a aplicar si hay vendedor
    double creditoAplicado = 0;
    if (esVentaVendedor && aplicarSaldoAFavor) {
      final saldoAFavor = await obtenerSaldoAFavor(vendedorId);
      if (saldoAFavor > 0) {
        creditoAplicado = saldoAFavor > totalNeto ? totalNeto : saldoAFavor;
      }
    }

    if (esVentaVendedor) {
      rutaId = await _obtenerOCrearRutaDelDia(
        vendedorId: vendedorId,
        bidonesLlenosEnCarro: bidonesLlenosEnCarro,
      );
    }

    final stockPorProducto = await _validarStockDisponible(items);

    // 1. Insertar la venta
    final ventaData = await _desde(_esquemaVentas, 'ventas')
        .insert({
          'fecha': _fechaSql(DateTime.now()),
          'total': totalNeto,
          if (notas != null && notas.isNotEmpty) 'notas': notas,
          'vendedor_id': vendedorId?.isEmpty == true ? null : vendedorId,
          'ruta_id': rutaId,
          'credito_aplicado': creditoAplicado,
          'bidones_llenos_en_carro': esVentaVendedor ? bidonesLlenosEnCarro : 0,
          'bidones_vacios_recibidos': !esVentaVendedor
              ? 0
              : bidonesVaciosRecibidos,
          'bidones_prestados_empresa': !esVentaVendedor
              ? 0
              : bidonesPrestadosEmpresa,
        })
        .select()
        .single();

    final ventaId = ventaData['id'] as String;

    // 2. Insertar items
    if (items.isNotEmpty) {
      await _desde(
        _esquemaVentas,
        'items_venta',
      ).insert(items.map((item) => item.aJsonItemVenta(ventaId)).toList());
      await _descontarInventarioPorVenta(
        items: items,
        stockPorProducto: stockPorProducto,
      );
    }

    // 3. Actualizar bidones del vendedor (LÓGICA CORREGIDA)
    if (esVentaVendedor) {
      final vendedorData = await _desde(
        _esquemaVendedores,
        'vendedores',
      ).select().eq('id', vendedorId).single();

      final propios = vendedorData['bidones_propios'] as int? ?? 0;

      final nuevosLlenos = bidonesLlenosEnCarro + bidonesCargados;
      const nuevosVacios = 0;
      final nuevosPrestados = (nuevosLlenos - propios).clamp(0, 999999).toInt();

      await _desde(_esquemaVendedores, 'vendedores')
          .update({
            'bidones_llenos_actuales': nuevosLlenos,
            'bidones_vacios_actuales': nuevosVacios,
            'bidones_prestados': nuevosPrestados,
          })
          .eq('id', vendedorId);

      if (rutaId != null) {
        final totalPendienteVenta = totalNeto - creditoAplicado;
        await _sumarVentaARuta(
          rutaId: rutaId,
          totalVenta: totalPendienteVenta,
          bidonesCargados: bidonesCargados,
        );
        if (totalPendienteVenta > 0.009) {
          await _programarRecordatorioCobro(
            rutaId: rutaId,
            vendedorId: vendedorId,
          );
        }
      }

      // 4. Consumir saldo a favor si se aplicó crédito
      if (creditoAplicado > 0) {
        await _consumirSaldoAFavor(vendedorId, creditoAplicado);
      }
    }

    unawaited(
      _alertas.notificarAlertasNuevas(
        motivo: 'venta_registrada',
        estadoPrevio: estadoAlertasPrevio,
      ),
    );
    return obtenerPorId(ventaId);
  }

  Future<String?> _crearVentaSegura({
    required List<ItemCarrito> items,
    String? notas,
    String? vendedorId,
    int bidonesLlenosEnCarro = 0,
    int bidonesVaciosRecibidos = 0,
    bool aplicarSaldoAFavor = false,
  }) async {
    if (items.isEmpty) throw ArgumentError('La venta esta vacia.');

    final sessionToken = await _authService.obtenerTokenSesion();
    if (sessionToken == null || sessionToken.trim().isEmpty) {
      throw StateError('Inicia sesion para registrar la venta.');
    }

    try {
      final data = await _client
          .schema(_esquemaVentas)
          .rpc(
            'fn_crear_venta_segura',
            params: {
              'p_session_token': sessionToken,
              'p_items': items
                  .map(
                    (item) => {
                      'producto_id': item.productoId,
                      'cantidad': item.cantidad,
                      'devolucion': item.devolucion,
                    },
                  )
                  .toList(),
              'p_notas': notas,
              'p_vendedor_id': vendedorId?.isEmpty == true ? null : vendedorId,
              'p_fecha': _fechaSql(DateTime.now()),
              'p_bidones_llenos_en_carro': bidonesLlenosEnCarro,
              'p_bidones_vacios_recibidos': bidonesVaciosRecibidos,
              'p_aplicar_saldo_favor': aplicarSaldoAFavor,
            },
          );
      if (data is String && data.trim().isNotEmpty) return data;
      if (data is Map &&
          data['id'] is String &&
          (data['id'] as String).trim().isNotEmpty) {
        return data['id'] as String;
      }
      throw StateError('El RPC de venta no devolvio un identificador valido.');
    } on PostgrestException catch (error) {
      if (_rpcNoDisponible(error)) {
        throw StateError(
          'Falta aplicar el parche SQL de devoluciones y saldo a favor.',
        );
      }
      rethrow;
    }
  }

  bool _rpcNoDisponible(PostgrestException error) {
    return error.code == 'PGRST202' ||
        error.code == 'PGRST204' ||
        error.code == '42883';
  }

  // ── Eliminar ───────────────────────────────────────────────────────────────

  Future<void> _programarRecordatorioCobro({
    required String rutaId,
    required String vendedorId,
  }) async {
    try {
      final vendedor = await _desde(
        _esquemaVendedores,
        'vendedores',
      ).select('nombre').eq('id', vendedorId).single();
      final nombreVendedor = vendedor['nombre'] as String? ?? 'Vendedor';
      await ServicioNotificacion().programarNotificacionLocal(
        id: _idNotificacionRuta(rutaId),
        titulo: 'Cobro pendiente',
        cuerpo:
            '$nombreVendedor tiene un despacho pendiente por cobrar. Revisa el saldo antes de cerrar el dia.',
        fecha: DateTime.now().add(const Duration(hours: 2)),
        payload: 'ruta_$rutaId',
      );
    } catch (_) {
      // La venta no debe fallar si Android no permite programar el aviso.
    }
  }

  int _idNotificacionRuta(String rutaId) {
    var valor = 17;
    for (final codigo in rutaId.codeUnits) {
      valor = (valor * 31 + codigo) & 0x7fffffff;
    }
    return valor;
  }

  Future<String> _obtenerOCrearRutaDelDia({
    required String vendedorId,
    required int bidonesLlenosEnCarro,
  }) async {
    final hoy = _fechaSql(DateTime.now());
    final rutaAbierta = await _buscarRutaActiva(vendedorId: vendedorId);

    if (rutaAbierta != null) return rutaAbierta;

    try {
      final rutaData = await _desde(_esquemaRutas, 'rutas')
          .insert({
            'vendedor_id': vendedorId,
            'fecha': hoy,
            'estado': 'pendiente',
            'bidones_llenos_iniciales': bidonesLlenosEnCarro,
            'bidones_vacios_iniciales': 0,
            'bidones_cargados_hoy': 0,
          })
          .select('id')
          .single();

      return rutaData['id'] as String;
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      final rutaCreadaPorOtroProceso = await _buscarRutaActiva(
        vendedorId: vendedorId,
      );
      if (rutaCreadaPorOtroProceso != null) return rutaCreadaPorOtroProceso;
      rethrow;
    }
  }

  Future<String?> _buscarRutaActiva({required String vendedorId}) async {
    final rutas = await _desde(_esquemaRutas, 'rutas')
        .select('id')
        .eq('vendedor_id', vendedorId)
        .inFilter('estado', ['sin_cierre', 'pendiente', 'parcial'])
        .order('fecha', ascending: true)
        .order('creado_en', ascending: true)
        .limit(1);

    if ((rutas as List).isNotEmpty) {
      return rutas.first['id'] as String;
    }
    return null;
  }

  Future<void> _sumarVentaARuta({
    required String rutaId,
    required double totalVenta,
    required int bidonesCargados,
  }) async {
    final ruta = await _desde(_esquemaRutas, 'rutas')
        .select('monto_total, monto_cobrado, bidones_cargados_hoy')
        .eq('id', rutaId)
        .single();

    final montoTotalActual = (ruta['monto_total'] as num?)?.toDouble() ?? 0;
    final montoCobrado = (ruta['monto_cobrado'] as num?)?.toDouble() ?? 0;
    final cargadosActuales = ruta['bidones_cargados_hoy'] as int? ?? 0;
    final nuevoTotal = montoTotalActual + totalVenta.clamp(0, double.infinity);
    final nuevoEstado = montoCobrado > 0 ? 'parcial' : 'pendiente';

    await _desde(_esquemaRutas, 'rutas')
        .update({
          'monto_total': nuevoTotal,
          'bidones_cargados_hoy': cargadosActuales + bidonesCargados,
          'estado': nuevoEstado,
        })
        .eq('id', rutaId);
  }

  Future<void> _descontarInventarioPorVenta({
    required List<ItemCarrito> items,
    required Map<String, ({String nombre, int stock})> stockPorProducto,
  }) async {
    for (final item in items) {
      final producto = stockPorProducto[item.productoId]!;
      // Restar lo vendido, sumar lo devuelto
      final cambioNeto = item.cantidad - item.devolucion;
      final nuevoStock = producto.stock - cambioNeto;

      await _desde(_esquemaInventario, 'productos')
          .update({
            'stock': nuevoStock,
            'actualizado_en': DateTime.now().toIso8601String(),
          })
          .eq('id', item.productoId);
      stockPorProducto[item.productoId] = (
        nombre: producto.nombre,
        stock: nuevoStock,
      );

      if (item.cantidad > 0) {
        await _desde(_esquemaInventario, 'movimientos_inventario').insert({
          'producto_id': item.productoId,
          'tipo': 'salida',
          'cantidad': item.cantidad,
          'motivo': 'Venta registrada',
        });
      }
      if (item.devolucion > 0) {
        await _desde(_esquemaInventario, 'movimientos_inventario').insert({
          'producto_id': item.productoId,
          'tipo': 'entrada',
          'cantidad': item.devolucion,
          'motivo': 'Devolución de producto no vendido',
        });
      }
    }
  }

  Future<Map<String, ({String nombre, int stock})>> _validarStockDisponible(
    List<ItemCarrito> items,
  ) async {
    if (items.isEmpty) return {};

    final ids = items.map((item) => item.productoId).toSet().toList();
    final data = await _desde(
      _esquemaInventario,
      'productos',
    ).select('id, stock, nombre').inFilter('id', ids);

    final stockPorProducto = <String, ({String nombre, int stock})>{
      for (final producto in data as List)
        producto['id'] as String: (
          nombre: producto['nombre'] as String? ?? '',
          stock: producto['stock'] as int? ?? 0,
        ),
    };

    final cantidadesPorProducto = <String, int>{};
    for (final item in items) {
      // Usar cambio neto: cantidad vendida - devolución
      final cambioNeto = item.cantidad - item.devolucion;
      cantidadesPorProducto.update(
        item.productoId,
        (cantidad) => cantidad + cambioNeto,
        ifAbsent: () => cambioNeto,
      );
    }

    for (final entry in cantidadesPorProducto.entries) {
      final producto = stockPorProducto[entry.key];
      final nombreFallback = items
          .firstWhere((item) => item.productoId == entry.key)
          .nombreProducto;
      if (producto == null) {
        throw StateError('Producto no encontrado: $nombreFallback.');
      }
      final nombre = producto.nombre.isEmpty ? nombreFallback : producto.nombre;
      // Solo validar stock si el cambio neto es positivo (vende más de lo que devuelve)
      if (entry.value > 0 && producto.stock < entry.value) {
        throw StateError(
          'Stock insuficiente para $nombre. Disponible: ${producto.stock}.',
        );
      }
    }

    return stockPorProducto;
  }

  Future<void> eliminar(String id) async {
    await _desde(_esquemaVentas, 'ventas').delete().eq('id', id);
  }

  Future<ResumenVentas> _resumirPorFiltrosLocal({
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? vendedorId,
  }) async {
    var query = _desde(_esquemaVentas, 'ventas')
        .select('total')
        .gte('fecha', _fechaSql(fechaInicio))
        .lte('fecha', _fechaSql(fechaFin));

    if (vendedorId != null) {
      query = vendedorId.isEmpty
          ? query.isFilter('vendedor_id', null)
          : query.eq('vendedor_id', vendedorId);
    }

    final data = await query;
    final rows = List<Map<String, dynamic>>.from(data as List);
    final total = rows.fold<double>(
      0,
      (sum, row) => sum + ((row['total'] as num?)?.toDouble() ?? 0),
    );
    return ResumenVentas(cantidad: rows.length, total: total);
  }

  ResumenVentas _parseResumenVentas(Object? data) {
    if (data is List && data.isNotEmpty) {
      return _parseResumenVentas(data.first);
    }
    if (data is Map) {
      final cantidad = (data['cantidad'] as num?)?.toInt() ?? 0;
      final total = (data['total'] as num?)?.toDouble() ?? 0;
      return ResumenVentas(cantidad: cantidad, total: total);
    }
    return ResumenVentas.vacio;
  }

  String _fechaSql(DateTime fecha) {
    final local = fecha.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
