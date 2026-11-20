import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../datos/modelos/producto.dart';
import '../../../datos/modelos/ruta.dart';
import '../../../datos/modelos/venta.dart';
import '../../../datos/servicios/servicio_modelo_alertas.dart';
import '../../../datos/servicios/servicio_push_remoto.dart';
import '../../../datos/servicios/servicio_token_notificacion.dart';
import '../../../dominio/entidades/rol_usuario.dart';
import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../componentes/item_lista_animado.dart';
import '../../componentes/tarjeta_app.dart';
import '../../proveedores/proveedor_autenticacion.dart';
import '../../proveedores/proveedor_modelo_alertas.dart';
import '../../proveedores/proveedor_producto.dart';
import '../../proveedores/proveedor_ruta.dart';
import '../../proveedores/proveedor_venta.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(proveedorNotificadorAuth).usuario;
    final rol = usuario?.rol;
    final esVendedor = rol == RolUsuario.vendedor;
    final rutasAsync = ref.watch(proveedorNotificadorRuta);
    final productosAsync = esVendedor
        ? const AsyncData<List<Producto>>([])
        : ref.watch(proveedorNotificadorProducto);
    final ventasAsync = esVendedor || kIsWeb
        ? const AsyncData<List<Venta>>([])
        : ref.watch(proveedorNotificadorVenta);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas'),
        actions: [
          if (!esVendedor && usuario != null)
            IconButton(
              tooltip: 'Probar Firebase',
              icon: const Icon(Icons.notifications_active_rounded),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final tokenActual = await ServicioTokenNotificacion()
                      .registrarTokenActual();
                  if (tokenActual == null || tokenActual.trim().isEmpty) {
                    throw StateError(
                      'Este dispositivo no entrego token Firebase.',
                    );
                  }
                  final resultado = await ServicioPushRemoto()
                      .enviarNotificacion(
                        titulo: 'Prueba Firebase',
                        cuerpo:
                            'La notificación remota de Agua Milena funciona.',
                        tokens: [tokenActual],
                        datos: const {'tipo': 'prueba_firebase'},
                      );
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Firebase enviado a ${resultado.enviados} dispositivo(s).',
                      ),
                    ),
                  );
                } catch (error) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(_mensajeErrorFirebase(error))),
                  );
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.read(proveedorNotificadorRuta.notifier).cargar();
              if (!esVendedor) {
                ref.read(proveedorNotificadorProducto.notifier).cargar();
                ref.read(proveedorNotificadorVenta.notifier).cargar();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: esVendedor
            ? rutasAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (error, _) => _EstadoError(
                  mensaje: 'No se pudieron cargar tus despachos: $error',
                ),
                data: (rutas) {
                  final alertas = _construirAlertasVendedor(rutas: rutas);
                  if (alertas.isEmpty) return const _EstadoSinAlertas();
                  return _ListaAlertas(alertas: alertas);
                },
              )
            : productosAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (error, _) => _EstadoError(
                  mensaje: 'No se pudo cargar el inventario: $error',
                ),
                data: (productos) => rutasAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                  error: (error, _) => _EstadoError(
                    mensaje: 'No se pudieron cargar los despachos: $error',
                  ),
                  data: (rutas) {
                    if (kIsWeb) {
                      final alertas = _construirAlertas(
                        productos: productos,
                        rutas: rutas,
                        modeloAsync: const AsyncLoading<EstadoModeloAlertas>(),
                      );
                      if (alertas.isEmpty) return const _EstadoSinAlertas();
                      return _ListaAlertasSecciones(
                        secciones: _separarAlertas(alertas),
                      );
                    }
                    final ventas = ventasAsync.asData?.value ?? const [];

                    return FutureBuilder<EstadoModeloAlertas>(
                      future: ref
                          .read(proveedorServicioModeloAlertas)
                          .predecir(
                            productos: productos,
                            rutas: rutas,
                            ventas: ventas,
                          ),
                      builder: (context, snapshot) {
                        final AsyncValue<EstadoModeloAlertas> modeloAsync;
                        if (snapshot.hasData) {
                          modeloAsync = AsyncData(snapshot.data!);
                        } else if (snapshot.hasError) {
                          modeloAsync = AsyncError(
                            snapshot.error!,
                            snapshot.stackTrace ?? StackTrace.current,
                          );
                        } else {
                          modeloAsync =
                              const AsyncLoading<EstadoModeloAlertas>();
                        }
                        final alertas = _construirAlertas(
                          productos: productos,
                          rutas: rutas,
                          modeloAsync: modeloAsync,
                        );

                        if (alertas.isEmpty) return const _EstadoSinAlertas();
                        return _ListaAlertasSecciones(
                          secciones: _separarAlertas(alertas),
                        );
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }

  String _mensajeErrorFirebase(Object error) {
    final texto = error.toString();
    if (texto.contains('No autorizado')) {
      return 'Falta actualizar la función enviar-notificaciones en Supabase.';
    }
    return 'No se pudo enviar Firebase: $error';
  }

  List<_AlertaNecesaria> _construirAlertasVendedor({
    required List<Ruta> rutas,
  }) {
    final alertas = <_AlertaNecesaria>[];
    for (final ruta in rutas.where((r) => r.saldoPendienteVisible > 0.009)) {
      alertas.add(
        _AlertaNecesaria(
          prioridad: 0,
          icono: Icons.payments_rounded,
          color: AppColors.stockWarning,
          titulo: 'Saldo pendiente',
          resumen:
              '${ruta.nombreVendedor}: ${CurrencyUtils.format(ruta.saldoPendienteVisible)} por pagar.',
          explicacion:
              'Esta alerta aparece porque existe un saldo pendiente en tu despacho. Puedes consultar su estado desde el detalle.',
        ),
      );
    }
    alertas.sort((a, b) => a.prioridad.compareTo(b.prioridad));
    return alertas;
  }

  List<_SeccionAlertas> _separarAlertas(List<_AlertaNecesaria> alertas) {
    final aplicacion = <_AlertaNecesaria>[];
    final modelo = <_AlertaNecesaria>[];

    for (final alerta in alertas) {
      if (_esAlertaModeloInteligente(alerta)) {
        modelo.add(alerta);
      } else {
        aplicacion.add(alerta);
      }
    }

    return [
      _SeccionAlertas(
        titulo: 'Alertas de la aplicación',
        icono: Icons.notifications_rounded,
        alertas: aplicacion,
      ),
      _SeccionAlertas(
        titulo: 'Modelo inteligente',
        icono: Icons.auto_awesome_rounded,
        alertas: modelo,
      ),
    ].where((seccion) => seccion.alertas.isNotEmpty).toList();
  }

  bool _esAlertaModeloInteligente(_AlertaNecesaria alerta) {
    return alerta.titulo.startsWith('Predicción') ||
        alerta.titulo == 'Temporada fuerte cercana' ||
        alerta.titulo == 'Modelo inteligente no disponible';
  }

  List<_AlertaNecesaria> _construirAlertas({
    required List<Producto> productos,
    required List<Ruta> rutas,
    required AsyncValue<EstadoModeloAlertas> modeloAsync,
  }) {
    final alertas = <_AlertaNecesaria>[];

    for (final producto in productos.where((p) => p.esCritico)) {
      alertas.add(
        _AlertaNecesaria(
          prioridad: 0,
          icono: Icons.inventory_2_rounded,
          color: AppColors.error,
          titulo: 'Stock crítico',
          resumen:
              '${producto.nombre}: quedan ${producto.stock} ${producto.unidad}.',
          explicacion:
              'Está en el mínimo o por debajo del mínimo configurado (${producto.stockMinimo}). Reponer antes de registrar nuevas ventas.',
        ),
      );
    }

    for (final producto in productos.where((p) => p.esBajo && !p.esCritico)) {
      alertas.add(
        _AlertaNecesaria(
          prioridad: 1,
          icono: Icons.warning_amber_rounded,
          color: AppColors.warning,
          titulo: 'Stock bajo',
          resumen:
              '${producto.nombre}: quedan ${producto.stock} ${producto.unidad}.',
          explicacion:
              'Todavía se puede vender, pero el stock está cerca del mínimo (${producto.stockMinimo}).',
        ),
      );
    }

    for (final ruta in rutas.where((r) => r.saldoPendienteVisible > 0.009)) {
      alertas.add(
        _AlertaNecesaria(
          prioridad: 1,
          icono: Icons.payments_rounded,
          color: AppColors.stockWarning,
          titulo: 'Cobro pendiente',
          resumen:
              '${ruta.nombreVendedor}: ${CurrencyUtils.format(ruta.saldoPendienteVisible)} por cobrar.',
          explicacion:
              'El despacho tiene ventas registradas y aún no está pagado por completo. El abono o cobro debe hacerse desde el detalle de ese despacho.',
        ),
      );
    }

    for (final ruta in rutas.where(
      (r) => r.tieneSaldoAFavor && r.estado != EstadoRuta.pagado,
    )) {
      alertas.add(
        _AlertaNecesaria(
          prioridad: 2,
          icono: Icons.savings_rounded,
          color: AppColors.success,
          titulo: 'Saldo a favor',
          resumen:
              '${ruta.nombreVendedor}: ${CurrencyUtils.format(ruta.saldoAFavor)} disponible.',
          explicacion:
              'Puedes aplicar este excedente al total de un despacho o al registrar una nueva venta.',
        ),
      );
    }

    for (final ruta in rutas) {
      final bidonesEnVentas = ruta.ventas.fold<int>(
        0,
        (s, venta) => s + venta.bidonesCargados,
      );
      if (bidonesEnVentas > ruta.bidonesCargadosHoy) {
        alertas.add(
          _AlertaNecesaria(
            prioridad: 0,
            icono: Icons.sync_problem_rounded,
            color: AppColors.error,
            titulo: 'Despacho con bidones sin cuadrar',
            resumen:
                '${ruta.nombreVendedor}: ventas con $bidonesEnVentas bidones, despacho con ${ruta.bidonesCargadosHoy}.',
            explicacion:
                'El despacho no refleja todos los bidones cargados desde las ventas. Revisa la venta o sincroniza el despacho.',
          ),
        );
      }
    }

    modeloAsync.whenOrNull(
      data: (estado) {
        final prediccion = estado.prediccion;
        if (prediccion != null) {
          alertas.add(
            _AlertaNecesaria(
              prioridad: 1,
              icono: Icons.psychology_alt_rounded,
              color: AppColors.primaryLight,
              titulo: 'Predicción de hoy',
              resumen:
                  'Venta esperada: ${prediccion.demandaBidones} bidones y ${prediccion.demandaFundas} fundas.',
              explicacion:
                  'Preparación sugerida con margen: ${prediccion.cargaRecomendadaBidones} bidones y ${prediccion.cargaRecomendadaFundas} fundas. Riesgo de stock bajo: ${(prediccion.probabilidadStockBajo * 100).round()}%. Venta alta inesperada: ${(prediccion.probabilidadVentaAltaInesperada * 100).round()}%.',
            ),
          );
        }

        final semana = estado.prediccionSemana;
        if (semana != null) {
          alertas.add(
            _AlertaNecesaria(
              prioridad: 2,
              icono: Icons.calendar_view_week_rounded,
              color: AppColors.teal,
              titulo: 'Predicción semanal',
              resumen:
                  '${semana.etiqueta}: venta esperada de ${semana.demandaBidones} bidones y ${semana.demandaFundas} fundas.',
              explicacion:
                  'Día pico estimado: ${_formatearFechaCorta(semana.diaPico)}. Preparación sugerida acumulada: ${semana.cargaRecomendadaBidones} bidones y ${semana.cargaRecomendadaFundas} fundas.',
            ),
          );
        }

        final mes = estado.prediccionMes;
        if (mes != null) {
          alertas.add(
            _AlertaNecesaria(
              prioridad: 2,
              icono: Icons.calendar_month_rounded,
              color: AppColors.primary,
              titulo: 'Predicción mensual',
              resumen:
                  '${mes.etiqueta}: venta esperada de ${mes.demandaBidones} bidones y ${mes.demandaFundas} fundas.',
              explicacion:
                  'Día pico estimado: ${_formatearFechaCorta(mes.diaPico)}. Riesgo máximo de stock bajo: ${(mes.probabilidadStockBajoMaxima * 100).round()}%.',
            ),
          );
        }

        final temporada = estado.temporadaProxima;
        if (temporada != null) {
          alertas.add(
            _AlertaNecesaria(
              prioridad: 1,
              icono: Icons.event_available_rounded,
              color: AppColors.stockWarning,
              titulo: 'Temporada fuerte cercana',
              resumen:
                  '${temporada.nombre} empieza en ${temporada.diasRestantes} días.',
              explicacion:
                  '${temporada.explicacion} También se programó una notificación local antes de la temporada para revisar inventario y despacho.',
            ),
          );
        }
      },
      error: (_, _) {
        alertas.add(
          _AlertaNecesaria(
            prioridad: 2,
            icono: Icons.auto_awesome_rounded,
            color: AppColors.warning,
            titulo: 'Modelo inteligente no disponible',
            resumen: 'No se pudo cargar el modelo de predicción.',
            explicacion:
                'Las alertas operativas siguen funcionando con reglas reales de inventario y despacho, pero las predicciones de TensorFlow Lite no están activas.',
          ),
        );
      },
    );

    alertas.sort((a, b) => a.prioridad.compareTo(b.prioridad));
    return alertas;
  }

  String _formatearFechaCorta(DateTime fecha) {
    const meses = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${fecha.day} ${meses[fecha.month - 1]}';
  }
}

class _AlertaNecesaria {
  final int prioridad;
  final IconData icono;
  final Color color;
  final String titulo;
  final String resumen;
  final String explicacion;

  const _AlertaNecesaria({
    required this.prioridad,
    required this.icono,
    required this.color,
    required this.titulo,
    required this.resumen,
    required this.explicacion,
  });
}

class _SeccionAlertas {
  final String titulo;
  final IconData icono;
  final List<_AlertaNecesaria> alertas;

  const _SeccionAlertas({
    required this.titulo,
    required this.icono,
    required this.alertas,
  });
}

class _ListaAlertasSecciones extends StatelessWidget {
  final List<_SeccionAlertas> secciones;

  const _ListaAlertasSecciones({required this.secciones});

  @override
  Widget build(BuildContext context) {
    final total = secciones.fold<int>(
      0,
      (suma, seccion) => suma + seccion.alertas.length,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
      children: [
        _ResumenAlertas(total: total),
        const SizedBox(height: 18),
        for (final seccion in secciones) ...[
          _EncabezadoSeccionAlertas(seccion: seccion),
          const SizedBox(height: 10),
          for (var indice = 0; indice < seccion.alertas.length; indice++) ...[
            ItemListaAnimado(
              index: indice,
              child: _TarjetaAlerta(alerta: seccion.alertas[indice]),
            ),
            if (indice != seccion.alertas.length - 1)
              const SizedBox(height: 12),
          ],
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

class _EncabezadoSeccionAlertas extends StatelessWidget {
  final _SeccionAlertas seccion;

  const _EncabezadoSeccionAlertas({required this.seccion});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(seccion.icono, color: AppColors.primary, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            seccion.titulo,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          '${seccion.alertas.length}',
          style: GoogleFonts.inter(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ListaAlertas extends StatelessWidget {
  final List<_AlertaNecesaria> alertas;

  const _ListaAlertas({required this.alertas});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
      children: [
        _ResumenAlertas(total: alertas.length),
        const SizedBox(height: 18),
        for (var index = 0; index < alertas.length; index++) ...[
          ItemListaAnimado(
            index: index,
            child: _TarjetaAlerta(alerta: alertas[index]),
          ),
          if (index != alertas.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ResumenAlertas extends StatelessWidget {
  final int total;

  const _ResumenAlertas({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryDark,
            AppColors.primary,
            AppColors.primaryLight,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(34),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(28),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withAlpha(30)),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == 1 ? '1 alerta activa' : '$total alertas activas',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Revisa primero las de stock, cobros y despacho.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withAlpha(218),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaAlerta extends StatelessWidget {
  final _AlertaNecesaria alerta;

  const _TarjetaAlerta({required this.alerta});

  @override
  Widget build(BuildContext context) {
    final fondo = alerta.color.withAlpha(16);
    final borde = alerta.color.withAlpha(62);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: alerta.color.withAlpha(16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card(context),
            border: Border.all(color: borde),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 6, color: alerta.color),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [fondo, AppColors.card(context)],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: alerta.color.withAlpha(28),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: alerta.color.withAlpha(70),
                            ),
                          ),
                          child: Icon(
                            alerta.icono,
                            color: alerta.color,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    alerta.titulo,
                                    style: GoogleFonts.inter(
                                      color: AppColors.textPrimary(context),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  _ChipPrioridad(alerta: alerta),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                alerta.resumen,
                                style: GoogleFonts.inter(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                alerta.explicacion,
                                style: GoogleFonts.inter(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipPrioridad extends StatelessWidget {
  final _AlertaNecesaria alerta;

  const _ChipPrioridad({required this.alerta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: alerta.color.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: alerta.color.withAlpha(70)),
      ),
      child: Text(
        _etiqueta(alerta),
        style: GoogleFonts.inter(
          color: alerta.color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  String _etiqueta(_AlertaNecesaria alerta) {
    if (alerta.prioridad == 0) return 'URGENTE';
    if (alerta.titulo.startsWith('Predicci')) return 'MODELO';
    if (alerta.titulo.toLowerCase().contains('pendiente')) return 'PENDIENTE';
    return 'REVISAR';
  }
}

class _EstadoSinAlertas extends StatelessWidget {
  const _EstadoSinAlertas();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: AppColors.success,
                size: 42,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Sin alertas activas',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary(context),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inventario, despacho y cobros están dentro de los valores esperados.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: const [
                _RevisionChip(icono: Icons.inventory_2_rounded, texto: 'Stock'),
                _RevisionChip(icono: Icons.payments_rounded, texto: 'Cobros'),
                _RevisionChip(icono: Icons.route_rounded, texto: 'Despachos'),
                _RevisionChip(
                  icono: Icons.auto_awesome_rounded,
                  texto: 'Modelo',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RevisionChip extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _RevisionChip({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withAlpha(28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            texto,
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoError extends StatelessWidget {
  final String mensaje;

  const _EstadoError({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: TarjetaApp(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mensaje,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
