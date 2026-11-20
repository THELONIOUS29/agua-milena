// Implementacion nativa con TFLite para movil.
import 'package:tflite_flutter/tflite_flutter.dart';

class ResultadoInferenciaML {
  final List<String> nombresEntrada;
  final List<String> nombresSalida;
  final List<double> clasificacion;
  final List<double> regresion;

  const ResultadoInferenciaML({
    required this.nombresEntrada,
    required this.nombresSalida,
    required this.clasificacion,
    required this.regresion,
  });
}

Future<ResultadoInferenciaML?> ejecutarInferenciaML({
  required String rutaModelo,
  required List<double> entradaNormalizada,
}) async {
  final interpreter = await Interpreter.fromAsset(rutaModelo);
  try {
    interpreter.allocateTensors();

    final entradas = interpreter
        .getInputTensors()
        .map((tensor) => '${tensor.name} ${tensor.shape}')
        .toList(growable: false);
    final salidas = interpreter
        .getOutputTensors()
        .map((tensor) => '${tensor.name} ${tensor.shape}')
        .toList(growable: false);

    final tensorSalidas = interpreter.getOutputTensors();
    final output0 = _crearSalida(tensorSalidas[0].shape);
    final output1 = _crearSalida(tensorSalidas[1].shape);
    interpreter.runForMultipleInputs(
      [
        [entradaNormalizada],
      ],
      {0: output0, 1: output1},
    );

    final primeraEsClasificacion = tensorSalidas.first.shape.last == 2;
    final clasificacion = primeraEsClasificacion
        ? output0.first
        : output1.first;
    final regresion = primeraEsClasificacion ? output1.first : output0.first;

    return ResultadoInferenciaML(
      nombresEntrada: entradas,
      nombresSalida: salidas,
      clasificacion: clasificacion,
      regresion: regresion,
    );
  } finally {
    interpreter.close();
  }
}

List<List<double>> _crearSalida(List<int> forma) {
  final filas = forma.isNotEmpty ? forma.first : 1;
  final columnas = forma.length > 1 ? forma[1] : 1;
  return List.generate(filas, (_) => List<double>.filled(columnas, 0));
}
