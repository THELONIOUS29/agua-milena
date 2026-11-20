import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:agua_milena_app/datos/modelos/item_venta.dart';
import 'package:agua_milena_app/datos/modelos/producto.dart';
import 'package:agua_milena_app/datos/modelos/ruta.dart';
import 'package:agua_milena_app/datos/modelos/venta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_alertas_automaticas.dart';
import 'package:agua_milena_app/datos/servicios/servicio_criptografia.dart';
import 'package:agua_milena_app/datos/servicios/servicio_modelo_alertas.dart';
import 'package:agua_milena_app/datos/servicios/servicio_producto.dart';
import 'package:agua_milena_app/datos/servicios/servicio_push_remoto.dart';
import 'package:agua_milena_app/datos/servicios/servicio_reporte_pdf.dart';
import 'package:agua_milena_app/datos/servicios/servicio_ruta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_venta.dart';
// Se reutilizan solo los dobles de transporte/sesion; importar no ejecuta su main.
import 'servicios_reales_test.dart'
    show TransporteGuionado, AuthPrueba, PushPrueba, jsonRespuesta;

// Este auxiliar registra casos y metadatos; no decide reglas del negocio.
void caso(
  String codigo,
  String nombre,
  String metodoReal,
  FutureOr<void> Function() ejecutar,
) {
  test('$codigo - $nombre', ejecutar);
}

const productoJson = <String, dynamic>{
  'id': 'p1',
  'nombre': 'Bidón',
  'unidad': 'unidad',
  'precio': 3,
  'stock': 100,
  'stock_minimo': 5,
  'creado_en': '2026-10-01',
  'actualizado_en': '2026-10-01',
};
const rutaJson = <String, dynamic>{
  'id': 'r1',
  'vendedor_id': 'v1',
  'nombre_vendedor': 'Fixture',
  'fecha': '2026-10-01',
  'monto_total': 100,
  'monto_cobrado': 40,
  'estado': 'parcial',
  'creado_en': '2026-10-01',
};
const ventaJson = <String, dynamic>{
  'id': 'venta1',
  'fecha': '2026-10-01',
  'total': 6,
  'creado_en': '2026-10-01',
};

// Solo fallos, latencia y respuestas de la dependencia push; las reglas las decide el servicio real.
class PushControlado extends PushPrueba {
  bool fallaConsulta = false, fallaEnvioUnaVez = false;
  int consultas = 0, intentosEnvio = 0;
  Completer<List<AvisoPushRemoto>>? bloqueo;
  PushControlado(super.client);
  @override
  Future<List<AvisoPushRemoto>> obtenerResumenRevisionOperativa() async {
    consultas++;
    if (fallaConsulta) throw StateError('Transporte no disponible');
    if (bloqueo != null) return bloqueo!.future;
    return avisos;
  }

  @override
  Future<ResultadoPushRemoto> enviarNotificacion({
    required String titulo,
    required String cuerpo,
    String? rol,
    String? usuarioId,
    List<String> tokens = const [],
    Map<String, Object?> datos = const {},
  }) async {
    intentosEnvio++;
    if (fallaEnvioUnaVez) {
      fallaEnvioUnaVez = false;
      throw StateError('Error de transporte');
    }
    return super.enviarNotificacion(
      titulo: titulo,
      cuerpo: cuerpo,
      rol: rol,
      usuarioId: usuarioId,
      tokens: tokens,
      datos: datos,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransporteGuionado transporte;
  late SupabaseClient client;
  late http.Response Function(http.Request) responder;
  late PushControlado push;
  late ServicioAlertasAutomaticas alertas;
  late Map<String, String> almacen;
  late int escriturasClave;
  const canal = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    responder = (r) => throw StateError(
      'Solicitud externa no prevista: ${r.method} ${r.url.path}',
    );
    transporte = TransporteGuionado((r) => responder(r));
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'clave-local-ficticia',
      httpClient: transporte,
    );
    push = PushControlado(client);
    alertas = ServicioAlertasAutomaticas(push: push);
    almacen = {};
    escriturasClave = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (call) async {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          switch (call.method) {
            case 'read':
              return almacen[args['key']];
            case 'write':
              almacen[args['key'] as String] = args['value'] as String;
              escriturasClave++;
              return null;
            default:
              throw StateError(
                'Metodo de almacenamiento no previsto: ${call.method}',
              );
          }
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
    await client.dispose();
  });
  ServicioProducto inventario() => ServicioProducto(
    client: client,
    autenticacion: AuthPrueba('sesion-local'),
  );
  ServicioVenta ventas() => ServicioVenta(
    client: client,
    autenticacion: AuthPrueba('sesion-local'),
    alertas: alertas,
  );
  final desde = DateTime(2026, 10, 1), hasta = DateTime(2026, 10, 31);
  ItemCarrito item({
    String id = 'p1',
    double precio = 3,
    int cantidad = 2,
    int devolucion = 0,
  }) => ItemCarrito(
    productoId: id,
    nombreProducto: 'Bidón',
    precioUnitario: precio,
    unidad: 'unidad',
    cantidad: cantidad,
    devolucion: devolucion,
  );

  caso(
    'AMP_AU01',
    'cifrado AES-GCM conserva Unicode al descifrar',
    'ServicioCriptografia.encryptString/decryptString',
    () async {
      final servicio = ServicioCriptografia();
      final cifrado = await servicio.encryptString('Milena 💧 teléfono áéí');
      expect(cifrado, startsWith('v1.'));
      expect(cifrado, isNot(contains('teléfono')));
      expect(await servicio.decryptString(cifrado), 'Milena 💧 teléfono áéí');
    },
  );
  caso(
    'AMP_AU02',
    'dos cifrados del mismo texto usan IV distintos',
    'ServicioCriptografia.encryptString',
    () async {
      final s = ServicioCriptografia();
      final a = await s.encryptString('sesion'),
          b = await s.encryptString('sesion');
      expect(a.split('.')[1], isNot(b.split('.')[1]));
      expect(await s.decryptString(a), 'sesion');
      expect(await s.decryptString(b), 'sesion');
    },
  );
  caso(
    'AMP_AU03',
    'la clave local se reutiliza entre instancias',
    'ServicioCriptografia._getOrCreateKey',
    () async {
      final a = await ServicioCriptografia().encryptString('primero');
      final b = await ServicioCriptografia().encryptString('segundo');
      expect(escriturasClave, 1);
      expect(await ServicioCriptografia().decryptString(a), 'primero');
      expect(await ServicioCriptografia().decryptString(b), 'segundo');
    },
  );
  caso(
    'AMP_AU04',
    'la manipulacion del contenido cifrado invalida GCM',
    'ServicioCriptografia.decryptString',
    () async {
      final s = ServicioCriptografia();
      final partes = (await s.encryptString('secreto')).split('.');
      final datos = base64Url.decode(partes[2]);
      datos[0] ^= 1;
      partes[2] = base64UrlEncode(datos);
      expect(await s.decryptString(partes.join('.')), isNull);
    },
  );
  caso(
    'AMP_AU05',
    'un texto cifrado no se descifra con otra clave',
    'ServicioCriptografia.decryptString',
    () async {
      final s = ServicioCriptografia();
      final cifrado = await s.encryptString('sesion');
      almacen['session_encryption_key'] = base64UrlEncode(
        List<int>.filled(32, 7),
      );
      expect(await s.decryptString(cifrado), isNull);
    },
  );
  caso(
    'AMP_AU06',
    'payload versionado incompleto se rechaza sin almacenamiento',
    'ServicioCriptografia.decryptString',
    () async {
      expect(
        await ServicioCriptografia().decryptString('v1.incompleto'),
        isNull,
      );
      expect(escriturasClave, 0);
    },
  );
  caso(
    'AMP_AU07',
    'ausencia de dato cifrado devuelve null',
    'ServicioCriptografia.decryptString',
    () async {
      final s = ServicioCriptografia();
      expect(await s.decryptString(null), isNull);
      expect(await s.decryptString(''), isNull);
      expect(almacen, isEmpty);
    },
  );
  caso(
    'AMP_AU08',
    'compatibilidad de lectura del formato heredado',
    'ServicioCriptografia.decryptString',
    () async {
      expect(
        await ServicioCriptografia().decryptString('dato-heredado'),
        'dato-heredado',
      );
      expect(escriturasClave, 0);
    },
  );

  caso(
    'AMP_IN01',
    'lista productos y pide orden alfabetico al servidor',
    'ServicioProducto.obtenerTodos',
    () async {
      responder = (r) => jsonRespuesta([
        productoJson,
        {...productoJson, 'id': 'p2', 'nombre': 'Funda'},
      ]);
      final lista = await inventario().obtenerTodos();
      expect(lista.map((p) => p.id), ['p1', 'p2']);
      expect(
        transporte.solicitudes.single.url.queryParameters['order'],
        'nombre.asc.nullslast',
      );
      expect(lista.first.precio, 3);
    },
  );
  caso(
    'AMP_IN02',
    'detalle consulta el ID exacto y deserializa stock',
    'ServicioProducto.obtenerPorId',
    () async {
      responder = (r) => jsonRespuesta(productoJson);
      final p = await inventario().obtenerPorId('p1');
      expect(p.stock, 100);
      expect(transporte.solicitudes.single.url.queryParameters['id'], 'eq.p1');
    },
  );
  caso(
    'AMP_IN03',
    'alta envia los datos y devuelve el producto del servidor',
    'ServicioProducto.crear',
    () async {
      responder = (r) => jsonRespuesta(productoJson);
      final p = await inventario().crear({
        'nombre': 'Bidón',
        'precio': 3,
        'stock': 100,
      });
      expect(p.id, 'p1');
      final r = transporte.solicitudes.single;
      expect(r.method, 'POST');
      expect(jsonDecode(r.body), {
        'nombre': 'Bidón',
        'precio': 3,
        'stock': 100,
      });
    },
  );
  caso(
    'AMP_IN04',
    'edicion agrega fecha de actualizacion y filtra producto',
    'ServicioProducto.actualizar',
    () async {
      responder = (r) => jsonRespuesta({...productoJson, 'precio': 4});
      final inicio = DateTime.now();
      final p = await inventario().actualizar('p1', {'precio': 4});
      final r = transporte.solicitudes.single;
      expect(p.precio, 4);
      expect(r.method, 'PATCH');
      expect(r.url.queryParameters['id'], 'eq.p1');
      expect(
        DateTime.parse(
          jsonDecode(r.body)['actualizado_en'] as String,
        ).isBefore(inicio),
        isFalse,
      );
    },
  );
  caso(
    'AMP_IN05',
    'eliminacion se limita al producto seleccionado',
    'ServicioProducto.eliminar',
    () async {
      responder = (r) => jsonRespuesta(null);
      await inventario().eliminar('p1');
      final r = transporte.solicitudes.single;
      expect(r.method, 'DELETE');
      expect(r.url.path, endsWith('/productos'));
      expect(r.url.queryParameters['id'], 'eq.p1');
    },
  );
  caso(
    'AMP_IN06',
    'historial consulta producto orden y columnas reales',
    'ServicioProducto.obtenerMovimientos',
    () async {
      responder = (r) => jsonRespuesta([
        {'id': 'm1', 'tipo': 'entrada', 'cantidad': 4},
      ]);
      final historial = await inventario().obtenerMovimientos('p1');
      final q = transporte.solicitudes.single.url.queryParameters;
      expect(historial.single['cantidad'], 4);
      expect(q['producto_id'], 'eq.p1');
      expect(q['order'], 'creado_en.desc.nullslast');
      expect(q['limit'], '10');
    },
  );
  caso(
    'AMP_IN07',
    'historial limita solicitudes fuera del rango permitido',
    'ServicioProducto.obtenerMovimientos',
    () async {
      responder = (r) => jsonRespuesta([]);
      await inventario().obtenerMovimientos('p1', limite: 0);
      await inventario().obtenerMovimientos('p1', limite: 1000);
      expect(
        transporte.solicitudes.map((r) => r.url.queryParameters['limit']),
        ['1', '50'],
      );
    },
  );
  caso(
    'AMP_IN08',
    'seleccion de stock critico usa los modelos obtenidos',
    'ServicioProducto.obtenerStockCritico',
    () async {
      responder = (r) => jsonRespuesta([
        {...productoJson, 'id': 'p1', 'stock': 5},
        {...productoJson, 'id': 'p2', 'stock': 6},
        {...productoJson, 'id': 'p3', 'stock': 0},
      ]);
      expect((await inventario().obtenerStockCritico()).map((p) => p.id), [
        'p1',
        'p3',
      ]);
    },
  );
  caso(
    'AMP_IN09',
    'error de consulta se propaga sin devolver inventario ficticio',
    'ServicioProducto.obtenerTodos',
    () async {
      responder = (r) =>
          jsonRespuesta({'code': '42501', 'message': 'denied'}, 403);
      await expectLater(
        inventario().obtenerTodos(),
        throwsA(isA<PostgrestException>()),
      );
      expect(transporte.solicitudes.length, 1);
    },
  );
  caso(
    'AMP_IN10',
    'error de alta no devuelve un producto fabricado',
    'ServicioProducto.crear',
    () async {
      responder = (r) =>
          jsonRespuesta({'code': '23505', 'message': 'duplicate'}, 409);
      await expectLater(
        inventario().crear({'nombre': 'Bidón'}),
        throwsA(isA<PostgrestException>()),
      );
      expect(transporte.solicitudes.length, 1);
    },
  );
  caso(
    'AMP_IN11',
    'movimiento sin producto se rechaza antes del transporte',
    'ServicioProducto.registrarMovimiento',
    () async {
      await expectLater(
        inventario().registrarMovimiento(
          productoId: '  ',
          tipo: 'entrada',
          cantidad: 1,
        ),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    },
  );
  caso(
    'AMP_IN12',
    'imagen envia bytes y tipo MIME al bucket de productos',
    'ServicioProducto.subirImagen',
    () async {
      responder = (r) => jsonRespuesta({'Key': 'product-images/fixture.png'});
      final url = await inventario().subirImagen(
        Uint8List.fromList([1, 2, 3, 4]),
        'png',
      );
      final r = transporte.solicitudes.single;
      expect(r.method, 'POST');
      expect(r.url.path, contains('/object/product-images/'));
      final cuerpo = latin1.decode(r.bodyBytes);
      expect(cuerpo, contains(String.fromCharCodes([1, 2, 3, 4])));
      expect(cuerpo.toLowerCase(), contains('content-type: image/png'));
      expect(
        r.headers['Content-Type'] ?? r.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(url, contains('/object/public/product-images/'));
      expect(url, endsWith('.png'));
    },
  );
  caso(
    'AMP_IN13',
    'eliminar imagen obtiene el nombre desde su URL',
    'ServicioProducto.eliminarImagen',
    () async {
      responder = (r) => jsonRespuesta([]);
      await inventario().eliminarImagen(
        'http://127.0.0.1:54321/storage/v1/object/public/product-images/foto.png',
      );
      final r = transporte.solicitudes.single;
      expect(r.method, 'DELETE');
      expect(jsonDecode(r.body), {
        'prefixes': ['foto.png'],
      });
    },
  );

  caso(
    'AMP_VE01',
    'ventas recientes acota los limites inferior y superior',
    'ServicioVenta.obtenerRecientes',
    () async {
      responder = (r) => jsonRespuesta([]);
      await ventas().obtenerRecientes(limite: 0);
      await ventas().obtenerRecientes(limite: 1000);
      expect(
        transporte.solicitudes.map((r) => r.url.queryParameters['limit']),
        ['1', '100'],
      );
    },
  );
  caso(
    'AMP_VE02',
    'ventas del dia filtra la fecha local actual',
    'ServicioVenta.obtenerVentasHoy',
    () async {
      responder = (r) => jsonRespuesta([ventaJson]);
      final lista = await ventas().obtenerVentasHoy();
      final hoy = DateTime.now();
      final fecha =
          '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}';
      expect(lista.single.id, 'venta1');
      expect(
        transporte.solicitudes.single.url.queryParameters['fecha'],
        'eq.$fecha',
      );
    },
  );
  caso(
    'AMP_VE03',
    'total diario suma importes devueltos por la consulta real',
    'ServicioVenta.obtenerTotalHoy',
    () async {
      responder = (r) => jsonRespuesta([
        {'total': 3},
        {'total': 4.5},
        {'total': 0},
      ]);
      expect(await ventas().obtenerTotalHoy(), 7.5);
      expect(
        transporte.solicitudes.single.url.queryParameters['select'],
        'total',
      );
    },
  );
  caso(
    'AMP_VE04',
    'saldo del vendedor suma excedentes e ignora deudas',
    'ServicioVenta.obtenerSaldoAFavor',
    () async {
      responder = (r) => jsonRespuesta([
        {'monto_total': 100, 'monto_cobrado': 130},
        {'monto_total': 50, 'monto_cobrado': 70},
        {'monto_total': 90, 'monto_cobrado': 10},
      ]);
      expect(await ventas().obtenerSaldoAFavor('v1'), 50);
      expect(
        transporte.solicitudes.single.url.queryParameters['vendedor_id'],
        'eq.v1',
      );
    },
  );
  caso(
    'AMP_VE05',
    'nota de venta puede borrarse sin afectar otros campos',
    'ServicioVenta.actualizarNota',
    () async {
      responder = (r) => jsonRespuesta(null);
      await ventas().actualizarNota('venta1', null);
      final r = transporte.solicitudes.single;
      expect(r.method, 'PATCH');
      expect(r.url.queryParameters['id'], 'eq.venta1');
      expect(jsonDecode(r.body), {'notas': null});
    },
  );
  caso(
    'AMP_VE06',
    'RPC con respuesta objeto permite obtener la venta real',
    'ServicioVenta.crearVenta',
    () async {
      responder = (r) => jsonRespuesta(
        r.url.path.contains('/rpc/') ? {'id': 'venta1'} : ventaJson,
      );
      expect((await ventas().crearVenta(items: [item()])).id, 'venta1');
      expect(transporte.solicitudes.length, 2);
    },
  );
  caso(
    'AMP_VE07',
    'venta transmite devoluciones credito y datos de bidones al RPC',
    'ServicioVenta.crearVenta',
    () async {
      responder = (r) =>
          jsonRespuesta(r.url.path.contains('/rpc/') ? 'venta1' : ventaJson);
      await ventas().crearVenta(
        items: [item(devolucion: 1)],
        vendedorId: 'v1',
        notas: 'Retorno',
        bidonesLlenosEnCarro: 5,
        bidonesVaciosRecibidos: 2,
        aplicarSaldoAFavor: true,
      );
      final body = jsonDecode(transporte.solicitudes.first.body) as Map;
      expect(body['p_items'], [
        {'producto_id': 'p1', 'cantidad': 2, 'devolucion': 1},
      ]);
      expect(body['p_vendedor_id'], 'v1');
      expect(body['p_notas'], 'Retorno');
      expect(body['p_bidones_llenos_en_carro'], 5);
      expect(body['p_bidones_vacios_recibidos'], 2);
      expect(body['p_aplicar_saldo_favor'], isTrue);
    },
  );
  caso(
    'AMP_VE08',
    'venta rechaza precios no finitos antes de consultar',
    'ServicioVenta.crearVenta',
    () async {
      await expectLater(
        ventas().crearVenta(items: [item(precio: double.nan)]),
        throwsArgumentError,
      );
      await expectLater(
        ventas().crearVenta(items: [item(precio: double.infinity)]),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    },
  );
  caso(
    'AMP_VE09',
    'venta rechaza un producto sin identificador',
    'ServicioVenta.crearVenta',
    () async {
      await expectLater(
        ventas().crearVenta(items: [item(id: ' ')]),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    },
  );
  caso(
    'AMP_VE10',
    'venta rechaza cantidades negativas de bidones del vehiculo',
    'ServicioVenta.crearVenta',
    () async {
      await expectLater(
        ventas().crearVenta(items: [item()], bidonesLlenosEnCarro: -1),
        throwsArgumentError,
      );
      await expectLater(
        ventas().crearVenta(items: [item()], bidonesVaciosRecibidos: -1),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    },
  );

  caso(
    'AMP_RE01',
    'reporte de distribuidora usa filtro de vendedor nulo',
    'ServicioVenta.consultarPorFiltros',
    () async {
      responder = (r) => jsonRespuesta([]);
      await ventas().consultarPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
        vendedorId: '',
      );
      expect(
        transporte.solicitudes.single.url.queryParameters['vendedor_id'],
        'is.null',
      );
    },
  );
  caso(
    'AMP_RE02',
    'reporte general no limita vendedores',
    'ServicioVenta.consultarPorFiltros',
    () async {
      responder = (r) => jsonRespuesta([]);
      await ventas().consultarPorFiltros(fechaInicio: desde, fechaFin: hasta);
      expect(
        transporte.solicitudes.single.url.queryParameters.containsKey(
          'vendedor_id',
        ),
        isFalse,
      );
    },
  );
  caso(
    'AMP_RE03',
    'consulta de reportes acota su limite de filas',
    'ServicioVenta.consultarPorFiltros',
    () async {
      responder = (r) => jsonRespuesta([]);
      await ventas().consultarPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
        limite: 0,
      );
      await ventas().consultarPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
        limite: 999,
      );
      expect(
        transporte.solicitudes.map((r) => r.url.queryParameters['limit']),
        ['1', '500'],
      );
    },
  );
  caso(
    'AMP_RE04',
    'resumen RPC interpreta objeto y conserva los filtros',
    'ServicioVenta.resumirPorFiltros',
    () async {
      responder = (r) => jsonRespuesta({'cantidad': 3, 'total': 12.75});
      final resumen = await ventas().resumirPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
        vendedorId: 'v1',
      );
      expect(resumen.cantidad, 3);
      expect(resumen.total, 12.75);
      expect(jsonDecode(transporte.solicitudes.single.body), {
        'p_fecha_inicio': '2026-10-01',
        'p_fecha_fin': '2026-10-31',
        'p_vendedor_id': 'v1',
        'p_solo_distribuidora': false,
      });
    },
  );
  caso(
    'AMP_RE05',
    'resumen RPC interpreta la primera fila de una tabla',
    'ServicioVenta.resumirPorFiltros',
    () async {
      responder = (r) => jsonRespuesta([
        {'cantidad': 2, 'total': 8},
      ]);
      final s = await ventas().resumirPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
      );
      expect(s.cantidad, 2);
      expect(s.total, 8.0);
    },
  );
  caso(
    'AMP_RE06',
    'resumen sin filas devuelve cero sin segunda consulta',
    'ServicioVenta.resumirPorFiltros',
    () async {
      responder = (r) => jsonRespuesta([]);
      final s = await ventas().resumirPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
      );
      expect(s.cantidad, 0);
      expect(s.total, 0);
      expect(transporte.solicitudes.length, 1);
    },
  );
  caso(
    'AMP_RE07',
    'respaldo de resumen suma filas cuando el RPC falla',
    'ServicioVenta._resumirPorFiltrosLocal',
    () async {
      responder = (r) => r.url.path.contains('/rpc/')
          ? jsonRespuesta({'code': 'PGRST202', 'message': 'missing'}, 404)
          : jsonRespuesta([
              {'total': 2.5},
              {'total': 4},
            ]);
      final s = await ventas().resumirPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
        vendedorId: 'v1',
      );
      expect(s.total, 6.5);
      expect(s.cantidad, 2);
      expect(
        transporte.solicitudes.last.url.queryParameters['vendedor_id'],
        'eq.v1',
      );
      expect(transporte.solicitudes.length, 2);
    },
  );
  caso(
    'AMP_RE08',
    'si tambien falla el respaldo de resumen se informa el error',
    'ServicioVenta.resumirPorFiltros',
    () async {
      responder = (r) =>
          jsonRespuesta({'code': '42501', 'message': 'denied'}, 403);
      await expectLater(
        ventas().resumirPorFiltros(fechaInicio: desde, fechaFin: hasta),
        throwsA(isA<PostgrestException>()),
      );
      expect(transporte.solicitudes.length, 2);
    },
  );
  caso(
    'AMP_RE09',
    'resumen distribuidora preserva el filtro durante respaldo',
    'ServicioVenta._resumirPorFiltrosLocal',
    () async {
      responder = (r) => r.url.path.contains('/rpc/')
          ? jsonRespuesta({'code': 'PGRST202', 'message': 'missing'}, 404)
          : jsonRespuesta([
              {'total': null},
              {'total': 3},
            ]);
      final s = await ventas().resumirPorFiltros(
        fechaInicio: desde,
        fechaFin: hasta,
        vendedorId: '',
      );
      expect(s.total, 3);
      expect(s.cantidad, 2);
      expect(
        jsonDecode(transporte.solicitudes.first.body)['p_solo_distribuidora'],
        isTrue,
      );
      expect(
        transporte.solicitudes.last.url.queryParameters['vendedor_id'],
        'is.null',
      );
    },
  );
  caso(
    'AMP_RE10',
    'generacion de PDF sin ventas ni productos termina correctamente',
    'ServicioReportePdf.generarReporte',
    () async {
      final bytes = await ServicioReportePdf.generarReporte(
        ventas: [],
        productos: [],
        fechaInicio: desde,
        fechaFin: hasta,
        generadoPor: 'Auditoria local',
      );
      expect(ascii.decode(bytes.take(4).toList()), '%PDF');
      expect(bytes.length, greaterThan(1000));
    },
  );

  caso(
    'AMP_RU01',
    'lista de rutas solicita orden y conserva el saldo real',
    'ServicioRuta.obtenerTodas',
    () async {
      responder = (r) => jsonRespuesta([rutaJson]);
      final lista = await ServicioRuta(client: client).obtenerTodas();
      expect(lista.single.saldoPendienteVisible, 60);
      expect(
        transporte.solicitudes.single.url.queryParameters['order'],
        'creado_en.desc.nullslast',
      );
    },
  );
  caso(
    'AMP_RU02',
    'detalle de ruta consulta su ID exacto',
    'ServicioRuta.obtenerPorId',
    () async {
      responder = (r) => jsonRespuesta(rutaJson);
      expect((await ServicioRuta(client: client).obtenerPorId('r1')).id, 'r1');
      expect(transporte.solicitudes.single.url.queryParameters['id'], 'eq.r1');
    },
  );
  caso(
    'AMP_RU03',
    'consulta del vendedor usa su ID y fecha descendente',
    'ServicioRuta.obtenerPorVendedor',
    () async {
      responder = (r) => jsonRespuesta([rutaJson]);
      await ServicioRuta(client: client).obtenerPorVendedor('v1');
      final q = transporte.solicitudes.single.url.queryParameters;
      expect(q['vendedor_id'], 'eq.v1');
      expect(q['order'], 'fecha.desc.nullslast');
    },
  );
  caso(
    'AMP_RU04',
    'editar nota de ruta limita el cambio a ese despacho',
    'ServicioRuta.actualizarNota',
    () async {
      responder = (r) => jsonRespuesta(null);
      await ServicioRuta(client: client).actualizarNota('r1', 'Revision');
      final r = transporte.solicitudes.single;
      expect(r.method, 'PATCH');
      expect(r.url.queryParameters['id'], 'eq.r1');
      expect(jsonDecode(r.body), {'notas': 'Revision'});
    },
  );
  caso(
    'AMP_RU05',
    'saldo disponible excluye ruta destino e ignora deudas',
    'ServicioRuta.obtenerSaldoAFavorDisponible',
    () async {
      responder = (r) => jsonRespuesta([
        {'monto_total': 10, 'monto_cobrado': 30},
        {'monto_total': 50, 'monto_cobrado': 10},
      ]);
      expect(
        await ServicioRuta(
          client: client,
        ).obtenerSaldoAFavorDisponible(Ruta.desdeJson(rutaJson)),
        20,
      );
      final q = transporte.solicitudes.single.url.queryParameters;
      expect(q['id'], 'neq.r1');
      expect(q['vendedor_id'], 'eq.v1');
    },
  );
  caso(
    'AMP_RU06',
    'pago con credito exige ID de operacion para reintentos',
    'ServicioRuta.registrarPagoConDescuento',
    () async {
      await expectLater(
        ServicioRuta(client: client).registrarPagoConDescuento(
          rutaId: 'r1',
          montoEfectivo: 0,
          descuento: 0,
          credito: 10,
        ),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    },
  );
  caso(
    'AMP_RU07',
    'pago rechaza descuento negativo sin consultar sesion',
    'ServicioRuta.registrarPagoConDescuento',
    () async {
      await expectLater(
        ServicioRuta(client: client).registrarPagoConDescuento(
          rutaId: 'r1',
          montoEfectivo: 10,
          descuento: -1,
        ),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
      expect(almacen, isEmpty);
    },
  );
  caso(
    'AMP_RU08',
    'pago rechaza credito no finito aun con operacion indicada',
    'ServicioRuta.registrarPagoConDescuento',
    () async {
      await expectLater(
        ServicioRuta(client: client).registrarPagoConDescuento(
          rutaId: 'r1',
          montoEfectivo: 1,
          descuento: 0,
          credito: double.nan,
          operacionId: 'op1',
        ),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    },
  );
  caso(
    'AMP_RU09',
    'una ruta con cierre incompleto no publica totales finales',
    'Ruta.estaCerrada/totalVendidos/totalFaltantes',
    () {
      final r = Ruta.desdeJson({
        ...rutaJson,
        'items_json': [
          {
            'id': 'i1',
            'ruta_id': 'r1',
            'producto_id': 'p1',
            'precio_unitario': 3,
            'cantidad_salida': 5,
            'cantidad_sin_vender': 1,
            'cantidad_retorno_vacio': 4,
          },
          {
            'id': 'i2',
            'ruta_id': 'r1',
            'producto_id': 'p2',
            'precio_unitario': 1,
            'cantidad_salida': 2,
          },
        ],
      });
      expect(r.estaCerrada, isFalse);
      expect(r.totalVendidos, isNull);
      expect(r.totalFaltantes, isNull);
      expect(r.bidonesPrestadosFinales, isNull);
    },
  );
  caso(
    'AMP_RU10',
    'detalle JSON incorpora abonos y datos anidados del vendedor',
    'Ruta.desdeJson/Abono.desdeJson',
    () {
      final r = Ruta.desdeJson({
        ...rutaJson,
        'vendedores': {'nombre': 'Nombre anidado', 'bidones_propios': 7},
        'abonos_json': [
          {
            'id': 'a1',
            'ruta_id': 'r1',
            'monto': 12.5,
            'fecha': '2026-10-01T09:00:00',
            'nota': 'Parcial',
          },
        ],
      });
      expect(r.abonos.single.monto, 12.5);
      expect(r.abonos.single.nota, 'Parcial');
      expect(r.nombreVendedor, 'Nombre anidado');
      expect(r.vendedorBidonesPropios, 7);
    },
  );

  caso(
    'AMP_AL01',
    'clave explicita de aviso prevalece y elimina espacios',
    'AvisoPushRemoto.clave',
    () {
      final a = AvisoPushRemoto.desdeData({
        'titulo': 'Stock',
        'cuerpo': 'Detalle',
        'datos': {'clave': '  stock:p1  ', 'tipo': 'stock'},
      });
      expect(a.clave, 'stock:p1');
    },
  );
  caso(
    'AMP_AL02',
    'aviso sin clave obtiene identificador de tipo y contenido',
    'AvisoPushRemoto.clave',
    () {
      final a = AvisoPushRemoto.desdeData({
        'titulo': 'Stock',
        'cuerpo': 'Quedan 2',
        'datos': {'tipo': 'stock'},
      });
      expect(a.clave, 'stock|Stock|Quedan 2');
    },
  );
  caso(
    'AMP_AL03',
    'aviso incompleto obtiene valores de presentacion seguros',
    'AvisoPushRemoto.desdeData',
    () {
      final a = AvisoPushRemoto.desdeData({'datos': 'invalido'});
      expect(a.titulo, 'Agua Milena');
      expect(a.cuerpo, '');
      expect(a.datos, isEmpty);
    },
  );
  caso(
    'AMP_AL04',
    'resultado push convierte contadores recibidos como texto o decimal',
    'ResultadoPushRemoto.desdeData',
    () {
      final r = ResultadoPushRemoto.desdeData({
        'enviados': '2',
        'errores': 1.0,
        'avisos': '3',
        'error': 'rechazo',
      });
      expect(r.enviados, 2);
      expect(r.errores, 1);
      expect(r.avisos, 3);
      expect(r.error, 'rechazo');
    },
  );
  caso(
    'AMP_AL05',
    'respuesta push sin estructura no fabrica envios exitosos',
    'ResultadoPushRemoto.desdeData',
    () {
      final r = ResultadoPushRemoto.desdeData('respuesta invalida');
      expect(r.enviados, 0);
      expect(r.errores, 0);
      expect(r.avisos, 0);
      expect(r.error, isNull);
    },
  );
  caso(
    'AMP_AL06',
    'fallo al capturar alertas devuelve ausencia y no envia avisos',
    'ServicioAlertasAutomaticas.capturarEstadoActual',
    () async {
      push.fallaConsulta = true;
      final previo = await alertas.capturarEstadoActual();
      expect(previo, isNull);
      await alertas.notificarAlertasNuevas(
        motivo: 'prueba',
        estadoPrevio: previo,
      );
      expect(push.intentosEnvio, 0);
    },
  );
  caso(
    'AMP_AL07',
    'fallo de envio libera la revision para permitir reintentar',
    'ServicioAlertasAutomaticas.notificarAlertasNuevas',
    () async {
      push.avisos = [
        const AvisoPushRemoto(
          titulo: 'Stock',
          cuerpo: 'Detalle',
          datos: {'clave': 'p1'},
        ),
      ];
      push.fallaEnvioUnaVez = true;
      await alertas.notificarAlertasNuevas(motivo: 'prueba', estadoPrevio: {});
      await alertas.notificarAlertasNuevas(
        motivo: 'reintento',
        estadoPrevio: {},
      );
      expect(push.intentosEnvio, 3);
      expect(push.envios.map((e) => e.rol), ['admin', 'planta']);
    },
  );
  caso(
    'AMP_AL08',
    'revision simultanea no duplica envios mientras esta en curso',
    'ServicioAlertasAutomaticas.notificarAlertasNuevas',
    () async {
      push.bloqueo = Completer<List<AvisoPushRemoto>>();
      final primera = alertas.notificarAlertasNuevas(
        motivo: 'uno',
        estadoPrevio: {},
      );
      await alertas.notificarAlertasNuevas(motivo: 'dos', estadoPrevio: {});
      expect(push.consultas, 1);
      push.bloqueo!.complete([
        const AvisoPushRemoto(
          titulo: 'Stock',
          cuerpo: 'Detalle',
          datos: {'clave': 'p1'},
        ),
      ]);
      await primera;
      expect(push.envios.length, 2);
      expect(push.intentosEnvio, 2);
    },
  );
  caso(
    'AMP_AL09',
    'riesgo estadistico cambia al alcanzar stock operativo minimo',
    'ServicioModeloAlertas.estimarPrediccionEstadistica',
    () {
      final s = ServicioModeloAlertas();
      final fundas = Producto.desdeJson({
        ...productoJson,
        'id': 'p2',
        'nombre': 'Fundas',
        'stock': 20,
      });
      final bajo = s.estimarPrediccionEstadistica(
        productos: [
          Producto.desdeJson({...productoJson, 'stock': 9}),
          fundas,
        ],
        ventas: [],
        fecha: desde,
      );
      final suficiente = s.estimarPrediccionEstadistica(
        productos: [
          Producto.desdeJson({...productoJson, 'stock': 10}),
          fundas,
        ],
        ventas: [],
        fecha: desde,
      );
      expect(bajo.probabilidadStockBajo, 0.7);
      expect(suficiente.probabilidadStockBajo, 0.2);
    },
  );
  caso(
    'AMP_AL10',
    'estimacion no utiliza ventas del dia objetivo ni del futuro',
    'ServicioModeloAlertas.estimarPrediccionEstadistica',
    () {
      final s = ServicioModeloAlertas();
      final fecha = DateTime(2026, 5, 18);
      final futuro = Venta.desdeJson({
        ...ventaJson,
        'fecha': '2026-05-19',
        'items_json': [
          {
            'id': 'i1',
            'venta_id': 'venta1',
            'producto_id': 'p1',
            'nombre_producto': 'Bidón',
            'cantidad': 10000,
            'precio_unitario': 3,
            'subtotal': 30000,
          },
        ],
      });
      final hoy = Venta.desdeJson({
        ...ventaJson,
        'fecha': '2026-05-18',
        'items_json': [
          {
            'id': 'i2',
            'venta_id': 'venta1',
            'producto_id': 'p1',
            'nombre_producto': 'Bidón',
            'cantidad': 10000,
            'precio_unitario': 3,
            'subtotal': 30000,
          },
        ],
      });
      final p = s.estimarPrediccionEstadistica(
        productos: [],
        ventas: [futuro, hoy],
        fecha: fecha,
      );
      expect(p.demandaBidones, 115);
      expect(p.demandaFundas, 52);
    },
  );
}
