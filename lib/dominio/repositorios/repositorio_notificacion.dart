abstract class RepositorioNotificacion {
  Future<void> inicializar({
    Function(String titulo, String cuerpo)? alRecibirMensaje,
  });
  Future<void> mostrarNotificacionLocal({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  });
  Future<String?> obtenerToken();
}
