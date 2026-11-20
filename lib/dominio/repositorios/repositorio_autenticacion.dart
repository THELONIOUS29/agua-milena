import '../entidades/rol_usuario.dart';

abstract class RepositorioAutenticacion {
  String hashContrasena(String contrasena);
  bool verificarContrasena(String contrasena, String hashAlmacenado);
  bool necesitaRehash(String hash);
  bool esContrasenaValida(String contrasena);
  Future<bool> puedeUsarBiometria();
  Future<bool> autenticarBiometria();
  Future<void> guardarSesionUsuario(
    UsuarioApp user, {
    required String sessionToken,
  });
  Future<UsuarioApp?> obtenerSesionAlmacenada();
  Future<String?> obtenerTokenSesion();
  Future<bool> estaMfaHabilitado();
  Future<void> cerrarSesion();
}
