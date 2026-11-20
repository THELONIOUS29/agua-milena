// Stub para web: TFLite no esta disponible.

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
}) async => null;
