import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../datos/servicios/servicio_modelo_alertas.dart';

final proveedorServicioModeloAlertas = Provider<ServicioModeloAlertas>(
  (ref) => ServicioModeloAlertas(),
);

final proveedorEstadoModeloAlertas = FutureProvider<EstadoModeloAlertas>(
  (ref) => ref.watch(proveedorServicioModeloAlertas).cargar(),
);
