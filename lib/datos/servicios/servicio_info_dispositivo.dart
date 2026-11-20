import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Servicio que obtiene y cachea información del dispositivo y la app.
class ServicioInfoDispositivo {
  static ServicioInfoDispositivo? _instance;
  static ServicioInfoDispositivo get instance =>
      _instance ??= ServicioInfoDispositivo._();
  ServicioInfoDispositivo._();

  String? _nombreDispositivo;
  String? _versionOS;
  String? _versionApp;
  bool _inicializado = false;

  Future<void> inicializar() async {
    if (_inicializado) return;
    final deviceInfo = DeviceInfoPlugin();
    final packageInfo = await PackageInfo.fromPlatform();
    _versionApp = '${packageInfo.version}+${packageInfo.buildNumber}';
    if (kIsWeb) {
      final web = await deviceInfo.webBrowserInfo;
      _nombreDispositivo = '${web.browserName.name} (Web)';
      _versionOS = web.userAgent ?? 'Web';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      final android = await deviceInfo.androidInfo;
      _nombreDispositivo = '${android.brand} ${android.model}';
      _versionOS =
          'Android ${android.version.release} (SDK ${android.version.sdkInt})';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = await deviceInfo.iosInfo;
      _nombreDispositivo = '${ios.name} (${ios.model})';
      _versionOS = '${ios.systemName} ${ios.systemVersion}';
    }
    _inicializado = true;
  }

  String get nombreDispositivo => _nombreDispositivo ?? 'Desconocido';
  String get versionOS => _versionOS ?? 'Desconocido';
  String get versionApp => _versionApp ?? '1.0.0';
}
