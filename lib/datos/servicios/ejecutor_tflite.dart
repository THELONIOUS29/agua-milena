// Punto de entrada con importacion condicional.
// En plataformas con dart:io (movil) usa el interprete TFLite nativo.
// En web usa el stub que retorna null.
export 'ejecutor_tflite_stub.dart'
    if (dart.library.io) 'ejecutor_tflite_nativo.dart';
