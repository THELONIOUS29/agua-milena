import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'servicio_autenticacion.dart';

class ServicioUsuario {
  final _client = Supabase.instance.client;
  final ServicioAutenticacion _authService = ServicioAutenticacion();

  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final data = await _client
          .schema('usuarios')
          .rpc('fn_login', params: {'p_email': email, 'p_password': password});
      if (data == null) return null;
      final resultado = Map<String, dynamic>.from(data as Map);
      final usuario = resultado['user'];
      if (usuario is Map) {
        resultado['user'] = _normalizarUsuario(
          Map<String, dynamic>.from(usuario),
        );
      }
      return resultado;
    } catch (e, stack) {
      debugPrint('LOGIN ERROR: $e');
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  Future<Map<String, dynamic>?> validarSesionAlmacenada() async {
    final sessionToken = await _authService.obtenerTokenSesion();
    if (sessionToken == null || sessionToken.isEmpty) return null;
    try {
      final data = await _client
          .schema('usuarios')
          .rpc(
            'fn_validate_session',
            params: {'p_session_token': sessionToken},
          );
      if (data == null) return null;
      return _normalizarUsuario(Map<String, dynamic>.from(data as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> cerrarSesion() async {
    final sessionToken = await _authService.obtenerTokenSesion();
    if (sessionToken == null || sessionToken.isEmpty) return;
    try {
      await _client
          .schema('usuarios')
          .rpc('fn_logout', params: {'p_session_token': sessionToken});
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> obtenerTodos() async {
    final sessionToken = await _requerirTokenSesion();
    final data = await _client
        .schema('usuarios')
        .rpc('fn_list_users', params: {'p_session_token': sessionToken});
    return List<Map<String, dynamic>>.from(
      (data as List).map(
        (item) => _normalizarUsuario(Map<String, dynamic>.from(item as Map)),
      ),
    );
  }

  Future<Map<String, dynamic>> crear({
    required String email,
    required String nombre,
    required String hashContrasena,
    required String rol,
    String? vendedorId,
    String? telefono,
  }) async {
    final sessionToken = await _requerirTokenSesion();
    final data = await _client
        .schema('usuarios')
        .rpc(
          'fn_upsert_user',
          params: {
            'p_session_token': sessionToken,
            'p_email': email,
            'p_name': nombre,
            'p_password_hash': hashContrasena,
            'p_role': rol,
            'p_seller_id': vendedorId,
            'p_must_change_password': true,
            'p_phone': telefono,
          },
        );
    return _normalizarUsuario(Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> actualizar(
    String id, {
    String? nombre,
    String? email,
    String? hashContrasena,
    String? rol,
    bool? activo,
    String? vendedorId,
    bool? debeCambiarContrasena,
    String? telefono,
    String? urlAvatar,
  }) async {
    final sessionToken = await _requerirTokenSesion();
    final data = await _client
        .schema('usuarios')
        .rpc(
          'fn_upsert_user',
          params: {
            'p_session_token': sessionToken,
            'p_target_user_id': id,
            'p_name': nombre,
            'p_email': email,
            'p_password_hash': hashContrasena,
            'p_role': rol,
            'p_active': activo,
            'p_seller_id': vendedorId,
            'p_must_change_password': debeCambiarContrasena,
            'p_phone': telefono,
            'p_avatar_url': urlAvatar,
          },
        );
    return _normalizarUsuario(Map<String, dynamic>.from(data as Map));
  }

  Future<void> eliminar(String id) async {
    final sessionToken = await _requerirTokenSesion();
    await _client
        .schema('usuarios')
        .rpc(
          'fn_delete_user',
          params: {'p_session_token': sessionToken, 'p_target_user_id': id},
        );
  }

  Future<void> cambiarMiContrasena(String hashContrasena) async {
    final sessionToken = await _requerirTokenSesion();
    await _client
        .schema('usuarios')
        .rpc(
          'fn_change_my_password_hash',
          params: {
            'p_session_token': sessionToken,
            'p_password_hash': hashContrasena,
          },
        );
  }

  Future<String> _requerirTokenSesion() async {
    final sessionToken = await _authService.obtenerTokenSesion();
    if (sessionToken == null || sessionToken.isEmpty) {
      throw StateError('No hay una sesión válida en el dispositivo.');
    }
    return sessionToken;
  }

  Map<String, dynamic> _normalizarUsuario(Map<String, dynamic> json) {
    final normalizado = Map<String, dynamic>.from(json);
    normalizado['name'] = normalizado['name'] ?? normalizado['nombre'] ?? '';
    normalizado['nombre'] = normalizado['nombre'] ?? normalizado['name'] ?? '';
    normalizado['role'] = normalizado['role'] ?? normalizado['rol'] ?? 'planta';
    normalizado['rol'] = normalizado['rol'] ?? normalizado['role'] ?? 'planta';
    normalizado['active'] =
        normalizado['active'] ?? normalizado['activo'] ?? true;
    normalizado['activo'] =
        normalizado['activo'] ?? normalizado['active'] ?? true;
    normalizado['seller_id'] =
        normalizado['seller_id'] ?? normalizado['vendedor_id'];
    normalizado['vendedor_id'] =
        normalizado['vendedor_id'] ?? normalizado['seller_id'];
    normalizado['must_change_password'] =
        normalizado['must_change_password'] ??
        normalizado['debe_cambiar_contrasena'] ??
        false;
    normalizado['debe_cambiar_contrasena'] =
        normalizado['debe_cambiar_contrasena'] ??
        normalizado['must_change_password'] ??
        false;
    normalizado['phone'] = normalizado['phone'] ?? normalizado['telefono'];
    normalizado['telefono'] = normalizado['telefono'] ?? normalizado['phone'];
    normalizado['avatar_url'] =
        normalizado['avatar_url'] ?? normalizado['url_avatar'];
    normalizado['url_avatar'] =
        normalizado['url_avatar'] ?? normalizado['avatar_url'];
    return normalizado;
  }
}
