import 'package:agua_milena_app/datos/modelos/config_app.dart';
import 'package:agua_milena_app/datos/servicios/servicio_autenticacion.dart';
import 'package:agua_milena_app/datos/servicios/servicio_config_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('politica de contrasenas', () {
    final auth = ServicioAutenticacion();

    test('rechaza contrasenas temporales debiles', () {
      expect(auth.esContrasenaValida('abc123'), isFalse);
      expect(auth.esContrasenaValida('password1'), isFalse);
      expect(auth.esContrasenaValida('Password'), isFalse);
    });

    test('acepta contrasenas con longitud, numero y caracter especial', () {
      expect(auth.esContrasenaValida('Agua2026!'), isTrue);
      expect(auth.esContrasenaValida('Milena#123'), isTrue);
    });
  });

  group('version minima', () {
    test('compara versiones semanticas con partes faltantes', () {
      expect(ServicioConfigApp.compararVersiones('1.0.2', '1.0.1'), isPositive);
      expect(ServicioConfigApp.compararVersiones('1.0', '1.0.0'), 0);
      expect(ServicioConfigApp.compararVersiones('1.0.1', '1.0.2'), isNegative);
    });

    test('usa build number cuando la configuracion lo define', () {
      final packageInfo = PackageInfo(
        appName: 'Agua Milena',
        packageName: 'com.aguamilena.app',
        version: '1.0.2',
        buildNumber: '2004',
        buildSignature: '',
      );

      expect(
        ServicioConfigApp.requiereActualizar(
          packageInfo,
          const ConfigApp(numeroCompilacionMinima: 2005),
        ),
        isTrue,
      );
      expect(
        ServicioConfigApp.requiereActualizar(
          packageInfo,
          const ConfigApp(numeroCompilacionMinima: 2004),
        ),
        isFalse,
      );
    });
  });
}
