import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../nucleo/utilidades/utilidades_fecha.dart';
import '../../../datos/modelos/ruta.dart';
import '../../../dominio/entidades/rol_usuario.dart';
import '../../proveedores/proveedor_autenticacion.dart';
import '../../proveedores/proveedor_bidones.dart';
import '../../proveedores/proveedor_ruta.dart';
import '../../componentes/fondo_agua_ambiental.dart';
import '../../componentes/tarjeta_app.dart';
import '../../componentes/encabezado_seccion.dart';

final rutaFilterDateProvider = StateProvider<DateTime?>((ref) => null);

class RutasScreen extends ConsumerWidget {
  const RutasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutasAsync = ref.watch(proveedorNotificadorRuta);
    final userRole = ref.watch(
      proveedorNotificadorAuth.select((estado) => estado.usuario?.rol),
    );
    final esAdministrador = userRole == RolUsuario.admin;
    final esVendedor = userRole == RolUsuario.vendedor;
    final filterDate = ref.watch(rutaFilterDateProvider);
    final bidonesOverviewAsync = esVendedor
        ? null
        : ref.watch(proveedorResumenBidones);

    Future<void> refreshAll() async {
      HapticFeedback.lightImpact();
      await ref.read(proveedorNotificadorRuta.notifier).cargar();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Despacho de vendedores'),
        actions: [
          IconButton(
            icon: Icon(
              filterDate != null
                  ? Icons.event_available_rounded
                  : Icons.calendar_month_rounded,
              color: filterDate != null ? AppColors.primary : null,
            ),
            tooltip: 'Filtrar por fecha',
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: filterDate ?? DateTime.now(),
                firstDate: DateTime(2023),
                lastDate: DateTime(2030),
              );
              if (date != null) {
                ref.read(rutaFilterDateProvider.notifier).state = date;
              }
            },
          ),
          if (filterDate != null)
            IconButton(
              icon: const Icon(Icons.clear_rounded, color: AppColors.error),
              tooltip: 'Quitar filtro',
              onPressed: () =>
                  ref.read(rutaFilterDateProvider.notifier).state = null,
            ),
          IconButton(
            icon: const Icon(Icons.person_rounded),
            tooltip: 'Mi perfil',
            onPressed: () {
              HapticFeedback.lightImpact();
              context.push('/profile');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const _RoutesBackdrop(),
          rutasAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (error, _) => _RoutesErrorState(onRetry: refreshAll),
            data: (rutas) {
              final filteredRutas = filterDate == null
                  ? rutas
                  : rutas.where((ruta) {
                      return ruta.fecha.year == filterDate.year &&
                          ruta.fecha.month == filterDate.month &&
                          ruta.fecha.day == filterDate.day;
                    }).toList();

              final pendientes = filteredRutas
                  .where((ruta) => ruta.saldoPendiente > 0)
                  .length;
              final totalCobrar = filteredRutas.fold<double>(
                0.0,
                (sum, ruta) => sum + ruta.saldoPendienteVisible,
              );
              final totalFacturado = filteredRutas.fold<double>(
                0.0,
                (sum, ruta) => sum + ruta.montoTotal,
              );
              final sinCierre = filteredRutas
                  .where((ruta) => ruta.estado == EstadoRuta.sinCierre)
                  .length;

              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: refreshAll,
                child: CustomScrollView(
                  cacheExtent: 720,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _RoutesHero(
                            routeCount: filteredRutas.length,
                            pendientes: pendientes,
                            sinCierre: sinCierre,
                            totalFacturado: totalFacturado,
                            totalCobrar: totalCobrar,
                            filterDate: filterDate,
                            esAdministrador: esAdministrador,
                            canCreateRoute: !esVendedor,
                            onCreateRoute: () => context.push('/rutas/new'),
                            onClearFilter: filterDate == null
                                ? null
                                : () =>
                                      ref
                                              .read(
                                                rutaFilterDateProvider.notifier,
                                              )
                                              .state =
                                          null,
                          ),
                          const SizedBox(height: 16),
                          TarjetaApp(
                            padding: const EdgeInsets.all(16),
                            borderRadius: BorderRadius.circular(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const EncabezadoSeccion(
                                  title: 'Estado operativo',
                                  padding: EdgeInsets.zero,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _StatusBadge(
                                      label: '$pendientes pendientes',
                                      color: pendientes > 0
                                          ? AppColors.warning
                                          : AppColors.success,
                                    ),
                                    _StatusBadge(
                                      label: '$sinCierre sin cierre',
                                      color: sinCierre > 0
                                          ? AppColors.error
                                          : AppColors.teal,
                                    ),
                                    _StatusBadge(
                                      label: filterDate == null
                                          ? 'Sin filtro de fecha'
                                          : AppDateUtils.formatDate(filterDate),
                                      color: AppColors.primary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!esVendedor) ...[
                            const SizedBox(height: 16),
                            _RoutesResumenBidonesCard(
                              overviewAsync: bidonesOverviewAsync!,
                            ),
                            const SizedBox(height: 18),
                          ] else
                            const SizedBox(height: 16),
                          const EncabezadoSeccion(
                            title: 'Listado de despachos',
                          ),
                        ]),
                      ),
                    ),
                    if (filteredRutas.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                        sliver: SliverToBoxAdapter(
                          child: _EmptyRoutesState(
                            hasFilter: filterDate != null,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                        sliver: SliverList.builder(
                          itemCount: filteredRutas.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RutaCard(ruta: filteredRutas[index]),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: esVendedor
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/rutas/new'),
              icon: const Icon(Icons.add_road_rounded),
              label: Text(
                'Nuevo despacho',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
    );
  }
}

class _RoutesBackdrop extends StatelessWidget {
  const _RoutesBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: FondoAguaAmbiental(
        primary: AppColors.primary,
        secondary: AppColors.teal,
        accent: AppColors.warning,
      ),
    );
  }
}

class _RoutesHero extends StatelessWidget {
  final int routeCount;
  final int pendientes;
  final int sinCierre;
  final double totalFacturado;
  final double totalCobrar;
  final DateTime? filterDate;
  final bool esAdministrador;
  final bool canCreateRoute;
  final VoidCallback onCreateRoute;
  final VoidCallback? onClearFilter;

  const _RoutesHero({
    required this.routeCount,
    required this.pendientes,
    required this.sinCierre,
    required this.totalFacturado,
    required this.totalCobrar,
    required this.filterDate,
    required this.esAdministrador,
    required this.canCreateRoute,
    required this.onCreateRoute,
    this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.teal],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(32),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroRoutePill(
                icon: Icons.route_rounded,
                label: '$routeCount despachos visibles',
              ),
              _HeroRoutePill(
                icon: Icons.pending_actions_rounded,
                label: '$pendientes por cobrar',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            filterDate == null
                ? 'Despachos en campo'
                : 'Vista filtrada para ${AppDateUtils.formatDate(filterDate!)}',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              height: 1.12,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (esAdministrador)
                _RouteMetric(
                  label: 'Facturado',
                  value: CurrencyUtils.format(totalFacturado),
                )
              else
                _RouteMetric(label: 'Despachos', value: '$routeCount'),
              _RouteMetric(
                label: 'Por cobrar',
                value: CurrencyUtils.format(totalCobrar),
              ),
              _RouteMetric(label: 'Sin cierre', value: '$sinCierre'),
            ],
          ),
          if (canCreateRoute || onClearFilter != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (canCreateRoute)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onCreateRoute,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                      ),
                      icon: const Icon(Icons.add_road_rounded),
                      label: const Text('Nuevo despacho'),
                    ),
                  ),
                if (onClearFilter != null) ...[
                  SizedBox(width: canCreateRoute ? 12 : 0),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onClearFilter,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withAlpha(90)),
                      ),
                      icon: const Icon(Icons.filter_alt_off_rounded),
                      label: const Text('Quitar filtro'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroRoutePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroRoutePill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMetric extends StatelessWidget {
  final String label;
  final String value;

  const _RouteMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(210),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutesResumenBidonesCard extends StatelessWidget {
  final AsyncValue<ResumenBidones> overviewAsync;

  const _RoutesResumenBidonesCard({required this.overviewAsync});

  @override
  Widget build(BuildContext context) {
    return TarjetaApp(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: overviewAsync.when(
        loading: () => const LinearProgressIndicator(color: AppColors.primary),
        error: (error, _) => Text(
          'No se pudo cargar el resumen de bidones: $error',
          style: GoogleFonts.inter(color: AppColors.error, fontSize: 12),
        ),
        data: (overview) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EncabezadoSeccion(
              title: 'Bidones en operación',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusBadge(
                  label: 'Empresa ${overview.totalEmpresa}',
                  color: AppColors.primary,
                ),
                _StatusBadge(
                  label: 'Planta ${overview.bidonesEnPlanta}',
                  color: AppColors.teal,
                ),
                _StatusBadge(
                  label: 'En vendedores ${overview.bidonesConVendedores}',
                  color: AppColors.warning,
                ),
                if (overview.bidonesFaltantes > 0)
                  _StatusBadge(
                    label: 'Faltantes ${overview.bidonesFaltantes}',
                    color: AppColors.error,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RutaCard extends ConsumerWidget {
  final Ruta ruta;

  const _RutaCard({required this.ruta});

  Color get _estadoColor {
    switch (ruta.estado) {
      case EstadoRuta.pagado:
        return AppColors.success;
      case EstadoRuta.parcial:
        return AppColors.warning;
      case EstadoRuta.pendiente:
        return AppColors.error;
      case EstadoRuta.sinCierre:
        return AppColors.textHintLight;
    }
  }

  IconData get _estadoIcon {
    switch (ruta.estado) {
      case EstadoRuta.pagado:
        return Icons.check_circle_rounded;
      case EstadoRuta.parcial:
        return Icons.timelapse_rounded;
      case EstadoRuta.pendiente:
        return Icons.radio_button_unchecked_rounded;
      case EstadoRuta.sinCierre:
        return Icons.pending_outlined;
    }
  }

  Future<void> _confirmarEliminacion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar despacho'),
        content: Text(
          '¿Eliminar el despacho de ${ruta.nombreVendedor}? Sus pagos se eliminarán y las ventas quedarán desvinculadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true || !context.mounted) return;

    try {
      await ref.read(proveedorNotificadorRuta.notifier).eliminar(ruta.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Despacho eliminado'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esAdministrador =
        ref.watch(
          proveedorNotificadorAuth.select((estado) => estado.usuario?.rol),
        ) ==
        RolUsuario.admin;
    final saldoLabel = ruta.tieneSaldoAFavor ? 'A favor' : 'Saldo';
    final saldoValue = ruta.tieneSaldoAFavor
        ? ruta.saldoAFavor
        : ruta.saldoPendienteVisible;
    final bidonesIniciales =
        '${ruta.bidonesLlenosIniciales}L / ${ruta.bidonesVaciosIniciales}V';
    final bidonesFinales = ruta.bidonesLlenosFinales == null
        ? 'Sin cierre'
        : '${ruta.bidonesLlenosFinales}L / ${ruta.bidonesVaciosFinales ?? 0}V';

    return TarjetaApp(
      onTap: () => context.push('/rutas/detail/${ruta.id}'),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ),
                ),
                child: Center(
                  child: Text(
                    ruta.nombreVendedor.isNotEmpty
                        ? ruta.nombreVendedor[0].toUpperCase()
                        : '-',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ruta.nombreVendedor,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppDateUtils.formatDate(ruta.fecha)} | ${ruta.totalProductosSalida} unid.',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_estadoIcon, color: _estadoColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        ruta.estado.etiqueta,
                        style: GoogleFonts.inter(
                          color: _estadoColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (esAdministrador) ...[
                    const SizedBox(height: 4),
                    IconButton(
                      tooltip: 'Eliminar despacho',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _confirmarEliminacion(context, ref),
                    ),
                  ],
                  if (ruta.montoTotal > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      CurrencyUtils.format(saldoValue),
                      style: GoogleFonts.inter(
                        color: ruta.saldoPendiente > 0
                            ? AppColors.error
                            : AppColors.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$saldoLabel de ${CurrencyUtils.format(ruta.montoTotal)}',
                      style: GoogleFonts.inter(
                        color: AppColors.textHint(context),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RouteInfoChip(
                label: 'Inicio',
                value: bidonesIniciales,
                color: AppColors.primary,
              ),
              _RouteInfoChip(
                label: 'Carga hoy',
                value: '${ruta.bidonesCargadosHoy}',
                color: AppColors.warning,
              ),
              _RouteInfoChip(
                label: 'Final',
                value: bidonesFinales,
                color: ruta.estaCerrada
                    ? AppColors.teal
                    : AppColors.textHint(context),
              ),
              if (ruta.estaCerrada)
                _RouteInfoChip(
                  label: 'Recogidos',
                  value: '${ruta.bidonesVaciosRecogidos}',
                  color: AppColors.info,
                ),
            ],
          ),
          if (ruta.estaCerrada) ...[
            const SizedBox(height: 8),
            Text(
              'Vendidos: ${ruta.totalVendidos ?? 0} | Faltantes: ${ruta.totalFaltantes ?? 0}',
              style: GoogleFonts.inter(
                color: AppColors.textHint(context),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RouteInfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _RouteInfoChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textHint(context),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRoutesState extends StatelessWidget {
  final bool hasFilter;

  const _EmptyRoutesState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Column(
          children: [
            Icon(
              hasFilter
                  ? Icons.calendar_view_day_outlined
                  : Icons.route_outlined,
              size: 58,
              color: AppColors.textHint(context),
            ),
            const SizedBox(height: 12),
            Text(
              hasFilter
                  ? 'No hay despachos para esa fecha'
                  : 'Sin despachos registrados',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilter
                  ? 'Prueba con otra fecha o quita el filtro.'
                  : 'Cuando se creen nuevos despachos aparecerán aquí con su estado operativo y saldo.',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary(context),
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutesErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _RoutesErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: TarjetaApp(
          padding: const EdgeInsets.all(22),
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 46,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              Text(
                'No se pudieron cargar los despachos',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Intenta de nuevo para recuperar la vista operativa.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  onRetry();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
