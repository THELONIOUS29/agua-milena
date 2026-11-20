import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../datos/servicios/servicio_autenticacion.dart';
import '../../datos/servicios/servicio_reporte_errores.dart';
import '../../datos/servicios/servicio_token_notificacion.dart';
import '../../datos/servicios/servicio_usuario.dart';
import '../../dominio/entidades/rol_usuario.dart';

final proveedorServicioAuth = Provider<ServicioAutenticacion>(
  (ref) => ServicioAutenticacion(),
);
final proveedorServicioUsuario = Provider<ServicioUsuario>(
  (ref) => ServicioUsuario(),
);
final proveedorServicioTokenNotificacion = Provider<ServicioTokenNotificacion>(
  (ref) => ServicioTokenNotificacion(),
);

class EstadoAutenticacion {
  final UsuarioApp? usuario;
  final bool cargando;
  final bool autenticado;
  final String? error;
  final bool requiereMfa;
  final bool debeCambiarContrasena;

  const EstadoAutenticacion({
    this.usuario,
    this.cargando = false,
    this.autenticado = false,
    this.error,
    this.requiereMfa = false,
    this.debeCambiarContrasena = false,
  });

  EstadoAutenticacion copiarCon({
    UsuarioApp? usuario,
    bool? cargando,
    bool? autenticado,
    String? error,
    bool limpiarError = false,
    bool? requiereMfa,
    bool? debeCambiarContrasena,
  }) {
    return EstadoAutenticacion(
      usuario: usuario ?? this.usuario,
      cargando: cargando ?? this.cargando,
      autenticado: autenticado ?? this.autenticado,
      error: limpiarError ? null : (error ?? this.error),
      requiereMfa: requiereMfa ?? this.requiereMfa,
      debeCambiarContrasena:
          debeCambiarContrasena ?? this.debeCambiarContrasena,
    );
  }
}

class NotificadorAutenticacion extends StateNotifier<EstadoAutenticacion> {
  final ServicioAutenticacion _authService;
  final ServicioUsuario _userService;
  final ServicioTokenNotificacion _tokenNotificacionService;

  NotificadorAutenticacion(
    this._authService,
    this._userService,
    this._tokenNotificacionService,
  ) : super(const EstadoAutenticacion()) {
    _verificarSesionInicial();
  }

  Future<void> _verificarSesionInicial() async {
    state = state.copiarCon(cargando: true, limpiarError: true);
    try {
      final localUser = await _authService.obtenerSesionAlmacenada();
      if (localUser == null) {
        state = state.copiarCon(cargando: false, autenticado: false);
        return;
      }

      final puedeUsarBiometria = await _authService.puedeUsarBiometria();
      if (puedeUsarBiometria) {
        state = state.copiarCon(
          usuario: localUser,
          cargando: false,
          autenticado: false,
          requiereMfa: true,
        );
        return;
      }

      final serverUser = await _userService.validarSesionAlmacenada();
      if (serverUser == null) {
        await _authService.cerrarSesion();
        state = state.copiarCon(cargando: false, autenticado: false);
        return;
      }

      final user = UsuarioApp.desdeJson(serverUser);
      ServicioReporteErrores.instance.establecerUsuario(user.id);
      await _registrarTokenNotificaciones();

      state = state.copiarCon(
        usuario: user,
        autenticado: true,
        cargando: false,
        debeCambiarContrasena:
            serverUser['must_change_password'] as bool? ?? false,
      );
    } catch (e) {
      state = state.copiarCon(cargando: false, error: e.toString());
    }
  }

  Future<bool> validarBiometria() async {
    state = state.copiarCon(cargando: true, limpiarError: true);
    final ok = await _authService.autenticarBiometria();
    if (ok) {
      final serverUser = await _userService.validarSesionAlmacenada();
      final localUser =
          state.usuario ?? await _authService.obtenerSesionAlmacenada();
      if (serverUser == null && localUser == null) {
        await _authService.cerrarSesion();
        state = state.copiarCon(
          autenticado: false,
          requiereMfa: false,
          cargando: false,
          error: 'La sesion guardada ya no es valida. Ingresa nuevamente.',
        );
        return false;
      }

      final usuarioValidado = serverUser == null
          ? localUser!
          : UsuarioApp.desdeJson(serverUser);
      final debeCambiarContrasenaValidada =
          serverUser?['must_change_password'] as bool? ??
          state.debeCambiarContrasena;
      ServicioReporteErrores.instance.establecerUsuario(usuarioValidado.id);
      await _registrarTokenNotificaciones();
      state = state.copiarCon(
        usuario: usuarioValidado,
        autenticado: true,
        requiereMfa: false,
        debeCambiarContrasena: debeCambiarContrasenaValidada,
        cargando: false,
      );
      return true;
    }
    state = state.copiarCon(
      error: 'Autenticacion biometrica fallida o cancelada.',
      cargando: false,
    );
    return false;
  }

  Future<bool> loginConContrasena({
    required String email,
    required String contrasena,
  }) async {
    state = state.copiarCon(cargando: true, limpiarError: true);
    try {
      final response = await _userService.login(email, contrasena);
      if (response == null) {
        state = state.copiarCon(
          cargando: false,
          error: 'Correo o contrasena incorrectos.',
        );
        return false;
      }
      final userData = Map<String, dynamic>.from(response['user'] as Map);
      final sessionToken = response['session_token'] as String;
      final user = UsuarioApp.desdeJson(userData);
      await _authService.guardarSesionUsuario(user, sessionToken: sessionToken);
      ServicioReporteErrores.instance.establecerUsuario(user.id);
      await _registrarTokenNotificaciones();
      state = state.copiarCon(
        usuario: user,
        autenticado: true,
        requiereMfa: false,
        debeCambiarContrasena:
            userData['must_change_password'] as bool? ?? false,
        cargando: false,
      );
      return true;
    } catch (_) {
      state = state.copiarCon(
        cargando: false,
        error: 'Correo o contrasena incorrectos.',
      );
      return false;
    }
  }

  Future<void> cerrarSesion() async {
    ServicioReporteErrores.instance.establecerUsuario(null);
    await _desactivarTokenNotificaciones();
    await _userService.cerrarSesion();
    await _authService.cerrarSesion();
    state = const EstadoAutenticacion();
  }

  void marcarContrasenaCambiada() =>
      state = state.copiarCon(debeCambiarContrasena: false);

  Future<void> sincronizarUsuario(UsuarioApp user) async {
    final token = await _authService.obtenerTokenSesion();
    if (token != null && token.isNotEmpty) {
      await _authService.guardarSesionUsuario(user, sessionToken: token);
    }
    if (state.autenticado) {
      await _registrarTokenNotificaciones();
    }
    state = state.copiarCon(
      usuario: user,
      cargando: false,
      autenticado: state.autenticado,
      requiereMfa: state.requiereMfa,
      limpiarError: true,
    );
  }

  Future<void> sincronizarUsuarioDesdeJson(Map<String, dynamic> json) async =>
      await sincronizarUsuario(UsuarioApp.desdeJson(json));
  Future<void> recargarSesion() async => await _verificarSesionInicial();

  Future<void> _registrarTokenNotificaciones() async {
    try {
      await _tokenNotificacionService.registrarTokenActual();
    } catch (error, stackTrace) {
      debugPrint('No se pudo registrar el token de notificaciones: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _desactivarTokenNotificaciones() async {
    try {
      await _tokenNotificacionService.desactivarTokenActual();
      _tokenNotificacionService.cancelarEscucha();
    } catch (error, stackTrace) {
      debugPrint('No se pudo desactivar el token de notificaciones: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

final proveedorNotificadorAuth =
    StateNotifierProvider<NotificadorAutenticacion, EstadoAutenticacion>(
      (ref) => NotificadorAutenticacion(
        ref.watch(proveedorServicioAuth),
        ref.watch(proveedorServicioUsuario),
        ref.watch(proveedorServicioTokenNotificacion),
      ),
    );
