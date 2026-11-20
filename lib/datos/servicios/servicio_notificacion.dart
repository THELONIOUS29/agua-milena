import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class ServicioNotificacion {
  static final ServicioNotificacion _instancia = ServicioNotificacion._();

  factory ServicioNotificacion() => _instancia;

  ServicioNotificacion._();

  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  Function(String, String)? _alRecibirMensaje;
  bool _zonaHorariaLista = false;
  bool _inicializado = false;
  bool _escuchandoMensajes = false;

  Future<void> inicializar({
    Function(String titulo, String cuerpo)? alRecibirMensaje,
  }) async {
    _alRecibirMensaje = alRecibirMensaje;
    if (_inicializado) return;

    // flutter_local_notifications no funciona en web
    if (!kIsWeb) {
      const initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initDarwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: initAndroid,
        iOS: initDarwin,
        macOS: initDarwin,
      );
      await _localPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (_) {},
      );

      const channel = AndroidNotificationChannel(
        'high_importance_channel',
        'Notificaciones Importantes',
        description: 'Canal para notificaciones importantes.',
        importance: Importance.max,
      );
      await _localPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);

      FirebaseMessaging.onBackgroundMessage(
        _firebaseMessagingBackgroundHandler,
      );

      await _localPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      await programarAlertasTemporadasFuertes();
    }

    if (!kIsWeb) {
      await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    if (!_escuchandoMensajes) {
      _escuchandoMensajes = true;
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notification = message.notification;
        if (notification != null) {
          if (!kIsWeb) {
            mostrarNotificacionLocal(
              id: notification.hashCode,
              titulo: notification.title ?? '',
              cuerpo: notification.body ?? '',
              payload: message.data.toString(),
            );
          }
          _alRecibirMensaje?.call(
            notification.title ?? '',
            notification.body ?? '',
          );
        }
      });
    }
    _inicializado = true;
  }

  Future<void> mostrarNotificacionLocal({
    required int id,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Notificaciones Importantes',
      channelDescription: 'Canal para notificaciones importantes.',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _localPlugin.show(id, titulo, cuerpo, details, payload: payload);
  }

  Future<String?> obtenerToken() async {
    if (kIsWeb) {
      return await _firebaseMessaging.getToken(
        vapidKey:
            'BACdvuy9j9NyKB8dxNYAmBOz8GPYIn_qnenW9z2pVC_wTHSUwRjrVcIHE3iyTy-CU3XfqUIiy4m5oEV2s96LSZM',
      );
    }
    return await _firebaseMessaging.getToken();
  }

  Future<void> programarNotificacionLocal({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime fecha,
    String? payload,
  }) async {
    if (kIsWeb) return;
    if (!fecha.isAfter(DateTime.now())) return;

    await _prepararZonaHoraria();
    await _localPlugin.zonedSchedule(
      id,
      titulo,
      cuerpo,
      tz.TZDateTime.from(fecha, tz.local),
      _detallesNotificacion(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelarNotificacion(int id) async {
    if (kIsWeb) return;
    await _localPlugin.cancel(id);
  }

  Future<void> programarAlertasTemporadasFuertes({DateTime? ahora}) async {
    if (kIsWeb) return;
    final base = ahora ?? DateTime.now();
    final temporadas = _temporadasFuertes();

    for (final anio in [base.year, base.year + 1]) {
      for (var indice = 0; indice < temporadas.length; indice++) {
        final temporada = temporadas[indice];
        final inicio = DateTime(anio, temporada.mes, temporada.dia, 8, 0);
        final aviso = inicio.subtract(Duration(days: temporada.diasAntes));
        final fechaAviso = aviso.isAfter(base)
            ? aviso
            : inicio.isAfter(base)
            ? base.add(const Duration(minutes: 2))
            : null;

        if (fechaAviso == null) continue;

        await programarNotificacionLocal(
          id: anio * 100 + indice,
          titulo: 'Temporada fuerte cerca',
          cuerpo:
              '${temporada.nombre}: prepara inventario y despacho. ${temporada.motivo}',
          fecha: fechaAviso,
          payload: 'temporada_${temporada.mes}_${temporada.dia}_$anio',
        );
      }
    }
  }

  Future<void> _prepararZonaHoraria() async {
    if (_zonaHorariaLista) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Guayaquil'));
    _zonaHorariaLista = true;
  }

  NotificationDetails _detallesNotificacion() {
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Notificaciones Importantes',
      channelDescription: 'Canal para notificaciones importantes.',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  List<_TemporadaFuerteNotificacion> _temporadasFuertes() => const [
    _TemporadaFuerteNotificacion(
      nombre: 'Inicio de clases',
      mes: 4,
      dia: 1,
      diasAntes: 7,
      motivo: 'Suele aumentar la salida de bidones y fundas.',
    ),
    _TemporadaFuerteNotificacion(
      nombre: 'Fiestas de Lago Agrio',
      mes: 6,
      dia: 14,
      diasAntes: 7,
      motivo: 'Revisa stock antes del movimiento local.',
    ),
    _TemporadaFuerteNotificacion(
      nombre: 'Pedidos grandes de septiembre',
      mes: 9,
      dia: 1,
      diasAntes: 10,
      motivo: 'Históricamente aparecen pedidos grandes de fundas.',
    ),
    _TemporadaFuerteNotificacion(
      nombre: 'Pedidos grandes de octubre',
      mes: 10,
      dia: 1,
      diasAntes: 10,
      motivo: 'Prepara fundas para pedidos externos grandes.',
    ),
    _TemporadaFuerteNotificacion(
      nombre: 'Navidad',
      mes: 12,
      dia: 8,
      diasAntes: 10,
      motivo: 'La venta sube antes de Navidad.',
    ),
  ];
}

class _TemporadaFuerteNotificacion {
  final String nombre;
  final int mes;
  final int dia;
  final int diasAntes;
  final String motivo;

  const _TemporadaFuerteNotificacion({
    required this.nombre,
    required this.mes,
    required this.dia,
    required this.diasAntes,
    required this.motivo,
  });
}
