import 'package:uuid/uuid.dart';

class NotificacionApp {
  final String id;
  final String titulo;
  final String cuerpo;
  final DateTime fecha;
  final bool leida;

  NotificacionApp({
    String? id,
    required this.titulo,
    required this.cuerpo,
    DateTime? fecha,
    this.leida = false,
  }) : id = id ?? const Uuid().v4(),
       fecha = fecha ?? DateTime.now();

  NotificacionApp copiarCon({
    String? id,
    String? titulo,
    String? cuerpo,
    DateTime? fecha,
    bool? leida,
  }) {
    return NotificacionApp(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      cuerpo: cuerpo ?? this.cuerpo,
      fecha: fecha ?? this.fecha,
      leida: leida ?? this.leida,
    );
  }
}
