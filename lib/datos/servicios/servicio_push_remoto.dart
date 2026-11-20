import 'package:supabase_flutter/supabase_flutter.dart';

import 'servicio_autenticacion.dart';

class ServicioPushRemoto {
  final SupabaseClient _client;
  ServicioPushRemoto({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;
  final ServicioAutenticacion _servicioAutenticacion = ServicioAutenticacion();

  Future<ResultadoPushRemoto> enviarNotificacion({
    required String titulo,
    required String cuerpo,
    String? rol,
    String? usuarioId,
    List<String> tokens = const [],
    Map<String, Object?> datos = const {},
  }) async {
    final tokenSesion = await _servicioAutenticacion.obtenerTokenSesion();
    if (tokenSesion == null || tokenSesion.trim().isEmpty) {
      throw StateError('No hay una sesion activa para enviar notificaciones.');
    }

    final respuesta = await _client.functions.invoke(
      'enviar-notificaciones',
      body: {
        'titulo': titulo,
        'cuerpo': cuerpo,
        'token_sesion': tokenSesion,
        if (rol != null && rol.trim().isNotEmpty) 'rol': rol.trim(),
        if (usuarioId != null && usuarioId.trim().isNotEmpty)
          'usuario_id': usuarioId.trim(),
        if (tokens.isNotEmpty) 'tokens': tokens,
        if (datos.isNotEmpty) 'datos': datos,
      },
    );

    return _validarRespuesta(respuesta.data);
  }

  Future<ResultadoPushRemoto> ejecutarRevisionOperativa({
    String rol = 'admin',
  }) async {
    final tokenSesion = await _servicioAutenticacion.obtenerTokenSesion();
    if (tokenSesion == null || tokenSesion.trim().isEmpty) {
      throw StateError('No hay una sesion activa para enviar notificaciones.');
    }

    final respuesta = await _client.functions.invoke(
      'enviar-notificaciones',
      body: {'revision': 'operativa', 'rol': rol, 'token_sesion': tokenSesion},
    );

    return _validarRespuesta(respuesta.data, permitirSinAvisos: true);
  }

  Future<List<AvisoPushRemoto>> obtenerResumenRevisionOperativa() async {
    final tokenSesion = await _servicioAutenticacion.obtenerTokenSesion();
    if (tokenSesion == null || tokenSesion.trim().isEmpty) {
      throw StateError('No hay una sesion activa para consultar alertas.');
    }

    final respuesta = await _client.functions.invoke(
      'enviar-notificaciones',
      body: {
        'revision': 'operativa',
        'solo_resumen': true,
        'token_sesion': tokenSesion,
      },
    );

    final data = respuesta.data;
    if (data is Map && data['error'] != null) {
      throw StateError(data['error'].toString());
    }
    final detalle = data is Map ? data['detalle'] : null;
    if (detalle is! List) return const [];
    return detalle
        .whereType<Map>()
        .map(AvisoPushRemoto.desdeData)
        .where((aviso) => aviso.clave.isNotEmpty)
        .toList();
  }

  ResultadoPushRemoto _validarRespuesta(
    Object? data, {
    bool permitirSinAvisos = false,
  }) {
    final resultado = ResultadoPushRemoto.desdeData(data);
    final error = resultado.error;
    if (error != null && error.trim().isNotEmpty) {
      throw StateError(error);
    }
    if (permitirSinAvisos && resultado.avisos == 0) {
      return resultado;
    }
    if (resultado.enviados == 0) {
      throw StateError(
        resultado.avisos > 0
            ? 'Hay ${resultado.avisos} avisos, pero no hay dispositivos registrados para recibirlos.'
            : 'No hay dispositivos registrados para recibir notificaciones.',
      );
    }
    if (resultado.errores > 0) {
      throw StateError(
        'Firebase reporto ${resultado.errores} errores al enviar.',
      );
    }
    return resultado;
  }
}

class AvisoPushRemoto {
  final String titulo;
  final String cuerpo;
  final Map<String, Object?> datos;

  const AvisoPushRemoto({
    required this.titulo,
    required this.cuerpo,
    required this.datos,
  });

  String get clave {
    final claveDato = datos['clave']?.toString().trim();
    if (claveDato != null && claveDato.isNotEmpty) return claveDato;
    final tipo = datos['tipo']?.toString().trim() ?? '';
    return '$tipo|$titulo|$cuerpo';
  }

  factory AvisoPushRemoto.desdeData(Map<dynamic, dynamic> data) {
    final rawDatos = data['datos'];
    return AvisoPushRemoto(
      titulo: data['titulo']?.toString() ?? 'Agua Milena',
      cuerpo: data['cuerpo']?.toString() ?? '',
      datos: rawDatos is Map
          ? rawDatos.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
  }
}

class ResultadoPushRemoto {
  final int enviados;
  final int errores;
  final int avisos;
  final String? error;

  const ResultadoPushRemoto({
    required this.enviados,
    required this.errores,
    required this.avisos,
    this.error,
  });

  factory ResultadoPushRemoto.desdeData(Object? data) {
    if (data is Map) {
      return ResultadoPushRemoto(
        enviados: _leerEntero(data['enviados']),
        errores: _leerEntero(data['errores']),
        avisos: _leerEntero(data['avisos']),
        error: data['error']?.toString(),
      );
    }
    return const ResultadoPushRemoto(enviados: 0, errores: 0, avisos: 0);
  }

  static int _leerEntero(Object? valor) {
    if (valor is int) return valor;
    if (valor is num) return valor.toInt();
    return int.tryParse(valor?.toString() ?? '') ?? 0;
  }
}
