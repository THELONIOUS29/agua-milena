import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:agua_milena_app/datos/modelos/item_venta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_autenticacion.dart';
import 'package:agua_milena_app/datos/servicios/servicio_venta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_producto.dart';
import 'package:agua_milena_app/datos/servicios/servicio_ruta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_alertas_automaticas.dart';
import 'package:agua_milena_app/datos/servicios/servicio_push_remoto.dart';
import 'package:agua_milena_app/datos/servicios/servicio_modelo_alertas.dart';
import 'package:agua_milena_app/nucleo/enrutador/enrutador_app.dart';
import 'package:agua_milena_app/presentacion/proveedores/proveedor_autenticacion.dart';
import 'package:agua_milena_app/presentacion/proveedores/proveedor_venta.dart';
import 'package:agua_milena_app/dominio/entidades/rol_usuario.dart';

// Transporte guionado: registra solicitudes y devuelve respuestas fijas.
// No calcula stock, totales, transacciones ni permisos de base de datos.
class TransporteGuionado extends http.BaseClient {
  final solicitudes = <http.Request>[];
  final http.Response Function(http.Request) responder;
  TransporteGuionado(this.responder);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final copia = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;
    solicitudes.add(copia);
    final respuesta = responder(copia);
    return http.StreamedResponse(
      Stream.value(respuesta.bodyBytes),
      respuesta.statusCode,
      headers: respuesta.headers,
      request: copia,
      reasonPhrase: respuesta.reasonPhrase,
    );
  }
}

class AuthPrueba extends ServicioAutenticacion {
  final String? token;
  AuthPrueba(this.token);
  @override
  Future<String?> obtenerTokenSesion() async => token;
}

class PushPrueba extends ServicioPushRemoto {
  List<AvisoPushRemoto> avisos = [];
  final envios = <({String titulo, String cuerpo, String? rol})>[];
  PushPrueba(SupabaseClient client) : super(client: client);
  @override
  Future<List<AvisoPushRemoto>> obtenerResumenRevisionOperativa() async =>
      avisos;
  @override
  Future<ResultadoPushRemoto> enviarNotificacion({
    required String titulo,
    required String cuerpo,
    String? rol,
    String? usuarioId,
    List<String> tokens = const [],
    Map<String, Object?> datos = const {},
  }) async {
    envios.add((titulo: titulo, cuerpo: cuerpo, rol: rol));
    return ResultadoPushRemoto.desdeData({'enviados': 1, 'errores': 0});
  }
}

http.Response jsonRespuesta(Object? data, [int codigo = 200]) => http.Response(
  jsonEncode(data),
  codigo,
  headers: {'content-type': 'application/json'},
);
ItemCarrito item({int cantidad = 2, int devolucion = 0}) => ItemCarrito(
  productoId: 'p1',
  nombreProducto: 'Bidón',
  precioUnitario: 1.5,
  unidad: 'bidón',
  cantidad: cantidad,
  devolucion: devolucion,
);
const ventaJson = {
  'id': 'venta1',
  'fecha': '2026-10-25',
  'total': 3,
  'creado_en': '2026-10-25T12:00:00',
  'items_json': <Object>[],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransporteGuionado transporte;
  late SupabaseClient client;
  late PushPrueba push;
  late ServicioAlertasAutomaticas alertas;
  void preparar(http.Response Function(http.Request) respuesta) {
    transporte = TransporteGuionado(respuesta);
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'clave-local-ficticia',
      httpClient: transporte,
    );
    push = PushPrueba(client);
    alertas = ServicioAlertasAutomaticas(push: push);
    addTearDown(client.dispose);
  }

  ServicioVenta ventas([String? token = 'token-prueba']) => ServicioVenta(
    client: client,
    autenticacion: AuthPrueba(token),
    alertas: alertas,
  );

  test(
    'REAL_V01 - crearVenta invoca RPC y deserializa venta; no prueba persistencia',
    () async {
      preparar(
        (r) =>
            jsonRespuesta(r.url.path.contains('/rpc/') ? 'venta1' : ventaJson),
      );
      final venta = await ventas().crearVenta(items: [item()]);
      expect(venta.id, 'venta1');
      expect(venta.total, 3);
      final rpc = transporte.solicitudes.first;
      expect(rpc.url.path, endsWith('/rpc/fn_crear_venta_segura'));
      expect(
        rpc.headers['Content-Profile'] ?? rpc.headers['content-profile'],
        'ventas',
      );
      final body = jsonDecode(rpc.body) as Map;
      expect(body['p_items'], [
        {'producto_id': 'p1', 'cantidad': 2, 'devolucion': 0},
      ]);
      expect(body['p_session_token'], 'token-prueba');
      expect(transporte.solicitudes.where((r) => r.method != 'GET').length, 1);
    },
  );
  test(
    'REAL_V02 - error de stock RPC se propaga sin escrituras alternativas',
    () async {
      preparar(
        (r) => jsonRespuesta({
          'code': 'P0001',
          'message': 'insufficient stock',
        }, 400),
      );
      await expectLater(
        ventas().crearVenta(items: [item()]),
        throwsA(isA<PostgrestException>()),
      );
      expect(transporte.solicitudes.length, 1);
    },
  );
  test(
    'REAL_V03 - RPC ausente bloquea venta sin escrituras alternativas',
    () async {
      preparar(
        (r) => jsonRespuesta({'code': 'PGRST202', 'message': 'missing'}, 404),
      );
      await expectLater(ventas().crearVenta(items: [item()]), throwsStateError);
      expect(transporte.solicitudes.length, 1);
    },
  );
  test('REAL_V04 - sin sesion no inicia persistencia por fallback', () async {
    preparar((r) => throw StateError('No debe llegar al transporte'));
    await expectLater(
      ventas(null).crearVenta(items: [item()]),
      throwsStateError,
    );
    expect(transporte.solicitudes, isEmpty);
  });
  test(
    'REAL_V05 - respuesta RPC invalida no inicia escrituras separadas',
    () async {
      preparar((r) => jsonRespuesta({}));
      await expectLater(ventas().crearVenta(items: [item()]), throwsStateError);
      expect(transporte.solicitudes.length, 1);
    },
  );
  for (final (nombre, items) in <(String, List<ItemCarrito>)>[
    ('vacia', []),
    ('negativa', [item(cantidad: -1)]),
    ('cero', [item(cantidad: 0)]),
    ('devolucion negativa', [item(devolucion: -1)]),
  ]) {
    test('REAL_V06_$nombre - rechaza venta invalida antes de IO', () async {
      preparar((r) => throw StateError('IO inesperado'));
      await expectLater(ventas().crearVenta(items: items), throwsArgumentError);
      expect(transporte.solicitudes, isEmpty);
    });
  }
  test('REAL_V07 - total, cantidades y devoluciones del carrito real', () {
    final carrito = NotificadorCarrito();
    addTearDown(carrito.dispose);
    carrito.agregarProducto(item());
    carrito.agregarProducto(item(cantidad: 3));
    expect(carrito.state.single.cantidad, 5);
    expect(carrito.total, 7.5);
    carrito.actualizarDevolucion(
      'p1',
      2,
      nombreProducto: 'Bidón',
      precioUnitario: 1.5,
      unidad: 'bidón',
    );
    expect(carrito.totalDevoluciones, 3);
    carrito.actualizarCantidad('p1', 0);
    expect(carrito.total, 0);
    expect(carrito.totalDevoluciones, 3);
    carrito.limpiar();
    expect(carrito.state, isEmpty);
  });
  for (final tipo in ['entrada', 'salida']) {
    test(
      'REAL_I01_$tipo - movimiento real usa RPC con cantidad y motivo',
      () async {
        preparar((r) => jsonRespuesta(null));
        await ServicioProducto(
          client: client,
          autenticacion: AuthPrueba('sesion'),
        ).registrarMovimiento(
          productoId: 'p1',
          tipo: tipo,
          cantidad: 4,
          motivo: 'prueba',
        );
        final r = transporte.solicitudes.single;
        expect(r.url.path, endsWith('/rpc/fn_registrar_movimiento_seguro'));
        expect(jsonDecode(r.body), {
          'p_session_token': 'sesion',
          'p_producto_id': 'p1',
          'p_tipo': tipo,
          'p_cantidad': 4,
          'p_motivo': 'prueba',
        });
      },
    );
  }
  for (final (tipo, cantidad) in [
    ('entrada', 0),
    ('entrada', -2),
    ('salida', -2),
    ('ajuste', 2),
  ]) {
    test('REAL_I02_${tipo}_$cantidad - movimiento invalido sin IO', () async {
      preparar((r) => throw StateError('IO inesperado'));
      await expectLater(
        ServicioProducto(
          client: client,
          autenticacion: AuthPrueba('sesion'),
        ).registrarMovimiento(productoId: 'p1', tipo: tipo, cantidad: cantidad),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    });
  }
  test('REAL_I03 - salida insuficiente del RPC no provoca fallback', () async {
    preparar(
      (r) => jsonRespuesta({
        'code': 'P0001',
        'message': 'insufficient stock',
      }, 400),
    );
    await expectLater(
      ServicioProducto(
        client: client,
        autenticacion: AuthPrueba('sesion'),
      ).registrarMovimiento(productoId: 'p1', tipo: 'salida', cantidad: 999),
      throwsA(isA<PostgrestException>()),
    );
    expect(transporte.solicitudes.length, 1);
  });
  test('REAL_I04 - sin sesion no inicia escrituras separadas', () async {
    preparar((r) => throw StateError('IO inesperado'));
    await expectLater(
      ServicioProducto(
        client: client,
        autenticacion: AuthPrueba(null),
      ).registrarMovimiento(productoId: 'p1', tipo: 'entrada', cantidad: 2),
      throwsStateError,
    );
    expect(transporte.solicitudes, isEmpty);
  });
  test(
    'REAL_I05 - RPC ausente bloquea movimiento sin escrituras alternativas',
    () async {
      preparar(
        (r) => jsonRespuesta({'code': 'PGRST202', 'message': 'missing'}, 404),
      );
      await expectLater(
        ServicioProducto(
          client: client,
          autenticacion: AuthPrueba('sesion'),
        ).registrarMovimiento(productoId: 'p1', tipo: 'entrada', cantidad: 2),
        throwsStateError,
      );
      expect(transporte.solicitudes.length, 1);
    },
  );
  for (final monto in [0.0, -1.0, double.nan, double.infinity]) {
    test('REAL_R01_$monto - abono invalido no escribe', () async {
      preparar((r) => throw StateError('IO inesperado'));
      await expectLater(
        ServicioRuta(client: client).registrarAbono(rutaId: 'r1', monto: monto),
        throwsArgumentError,
      );
      expect(transporte.solicitudes, isEmpty);
    });
  }
  for (final rol in RolUsuario.values) {
    for (final ubicacion in [
      '/users',
      '/sellers',
      '/rutas/new',
      '/profile',
      '/sales',
    ]) {
      test(
        'REAL_P01_${rol.name}_$ubicacion - redireccion usada por GoRouter',
        () {
          const esperados = {
            RolUsuario.admin: <String?>[null, null, null, null, null],
            RolUsuario.planta: <String?>['/', '/', null, null, null],
            RolUsuario.vendedor: <String?>[
              '/rutas',
              '/rutas',
              '/rutas',
              null,
              '/rutas',
            ],
          };
          final estado = EstadoAutenticacion(
            autenticado: true,
            usuario: UsuarioApp(
              id: 'u1',
              email: 'prueba@example.invalid',
              nombre: 'Prueba',
              rol: rol,
            ),
          );
          expect(
            redirigirAutenticacion(estado, ubicacion),
            esperados[rol]![[
              '/users',
              '/sellers',
              '/rutas/new',
              '/profile',
              '/sales',
            ].indexOf(ubicacion)],
          );
        },
      );
    }
  }
  test('REAL_P02 - sesion ausente, MFA y cambio obligatorio', () {
    expect(
      redirigirAutenticacion(const EstadoAutenticacion(), '/sales'),
      '/login',
    );
    expect(
      redirigirAutenticacion(
        const EstadoAutenticacion(requiereMfa: true),
        '/sales',
      ),
      '/mfa',
    );
    expect(
      redirigirAutenticacion(
        const EstadoAutenticacion(
          autenticado: true,
          debeCambiarContrasena: true,
        ),
        '/sales',
      ),
      '/change-password',
    );
  });
  test(
    'REAL_A01 - solo avisos nuevos: contenido y destinatarios admin y planta',
    () async {
      preparar((r) => throw StateError('IO inesperado'));
      push.avisos = [
        const AvisoPushRemoto(
          titulo: 'Existente',
          cuerpo: 'Antes',
          datos: {'clave': 'vieja'},
        ),
      ];
      final antes = await alertas.capturarEstadoActual();
      push.avisos = [
        ...push.avisos,
        const AvisoPushRemoto(
          titulo: 'Stock crítico',
          cuerpo: 'Bidón: quedan 2',
          datos: {'clave': 'nueva'},
        ),
      ];
      await alertas.notificarAlertasNuevas(
        motivo: 'prueba',
        estadoPrevio: antes,
      );
      expect(push.envios.map((e) => e.rol), ['admin', 'planta']);
      expect(push.envios.map((e) => e.titulo), everyElement('Stock crítico'));
      expect(push.envios.map((e) => e.cuerpo), everyElement('Bidón: quedan 2'));
    },
  );
  test('REAL_A02 - sin cambios o sin captura previa no notifica', () async {
    preparar((r) => throw StateError('IO inesperado'));
    await alertas.notificarAlertasNuevas(motivo: 'prueba', estadoPrevio: {});
    await alertas.notificarAlertasNuevas(motivo: 'prueba', estadoPrevio: null);
    expect(push.envios, isEmpty);
  });
  test('REAL_M01 - inferencia no disponible produce respaldo real', () async {
    final servicio = ServicioModeloAlertas(
      inferir: ({required rutaModelo, required entradaNormalizada}) async =>
          null,
    );
    final estado = await servicio.cargar();
    expect(estado.nombre, 'Estimación estadística');
    expect(estado.prediccion, isNotNull);
    expect(estado.prediccionSemana, isNull);
  });
  test(
    'REAL_M02 - fallo nativo produce respaldo real sin ocultar estimacion',
    () async {
      final servicio = ServicioModeloAlertas(
        inferir: ({required rutaModelo, required entradaNormalizada}) async =>
            throw StateError('biblioteca nativa ausente'),
      );
      final estado = await servicio.cargar();
      expect(estado.nombre, 'Estimación estadística');
      expect(estado.prediccion, isNotNull);
    },
  );
  test('REAL_F01 - consulta de reportes construye filtros reales', () async {
    preparar((r) => jsonRespuesta([ventaJson]));
    final lista = await ventas().consultarPorFiltros(
      fechaInicio: DateTime(2026, 10, 1),
      fechaFin: DateTime(2026, 10, 25),
      vendedorId: 'v1',
    );
    expect(lista.single.id, 'venta1');
    final filtros = transporte.solicitudes.single.url.queryParametersAll;
    expect(filtros['fecha'], ['gte.2026-10-01', 'lte.2026-10-25']);
    expect(filtros['vendedor_id'], ['eq.v1']);
  });
}
