import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../datos/modelos/config_app.dart';
import '../../datos/servicios/servicio_config_app.dart';
import '../../nucleo/constantes/colores_app.dart';
import '../pantallas/pantalla_actualizacion.dart';
import '../pantallas/pantalla_mantenimiento.dart';

/// Widget que verifica mantenimiento y versión mínima antes de mostrar la app.
/// Se ejecuta una vez al iniciar. Si pasa las verificaciones, muestra [child].
class VerificadorApp extends StatefulWidget {
  final Widget child;

  const VerificadorApp({super.key, required this.child});

  @override
  State<VerificadorApp> createState() => _VerificadorAppState();
}

class _VerificadorAppState extends State<VerificadorApp> {
  final _servicio = ServicioConfigApp();
  _EstadoVerificacion _estado = _EstadoVerificacion.cargando;
  ConfigApp _config = const ConfigApp();

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    setState(() => _estado = _EstadoVerificacion.cargando);

    final config = await _servicio.obtener();
    _config = config;

    if (config.modoMantenimiento) {
      setState(() => _estado = _EstadoVerificacion.mantenimiento);
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (ServicioConfigApp.requiereActualizar(packageInfo, config)) {
        setState(() => _estado = _EstadoVerificacion.actualizacionRequerida);
        return;
      }
    } catch (_) {
      // Si no se puede obtener la versión, no bloquear.
    }

    setState(() => _estado = _EstadoVerificacion.listo);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_estado) {
      _EstadoVerificacion.cargando => Scaffold(
        backgroundColor: AppColors.background(context),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
      _EstadoVerificacion.mantenimiento => PantallaMantenimiento(
        mensaje: _config.mensajeMantenimiento,
        onReintentar: _verificar,
      ),
      _EstadoVerificacion.actualizacionRequerida => PantallaActualizacion(
        versionMinima: _config.versionMinima,
        numeroCompilacionMinima: _config.numeroCompilacionMinima,
        urlActualizacion: _config.urlActualizacion,
        mensajeActualizacion: _config.mensajeActualizacion,
      ),
      _EstadoVerificacion.listo => widget.child,
    };
  }
}

enum _EstadoVerificacion {
  cargando,
  mantenimiento,
  actualizacionRequerida,
  listo,
}
