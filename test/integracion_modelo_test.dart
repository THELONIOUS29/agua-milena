import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agua_milena_app/datos/servicios/ejecutor_tflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'NATIVO_M01 - carga asset y ejecuta interprete real; no mide precision',
    () async {
      final texto = await rootBundle.loadString(
        'assets/modelos/metadatos_alertas_agua_milena.json',
      );
      final metadatos = jsonDecode(texto) as Map<String, dynamic>;
      expect(metadatos, isNotEmpty);
      final salida = await ejecutarInferenciaML(
        rutaModelo: 'assets/modelos/modelo_alertas_agua_milena.tflite',
        entradaNormalizada: List<double>.filled(28, 0),
      );
      expect(salida, isNotNull);
      expect(salida!.regresion.length, 5);
      expect(salida.clasificacion.length, 2);
      expect(
        [...salida.regresion, ...salida.clasificacion].every((n) => n.isFinite),
        isTrue,
      );
    },
    skip: const bool.fromEnvironment('RUN_NATIVE_MODEL')
        ? false
        : 'Requiere runtime TFLite nativo compatible. Activar RUN_NATIVE_MODEL tras instalarlo.',
  );
}
