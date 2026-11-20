import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../nucleo/utilidades/utilidades_fecha.dart';
import '../../../datos/modelos/ruta.dart';
import '../../../dominio/entidades/rol_usuario.dart';
import '../../proveedores/proveedor_autenticacion.dart';
import '../../proveedores/proveedor_bidones.dart';
import '../../proveedores/proveedor_producto.dart';
import '../../proveedores/proveedor_ruta.dart';
import '../../proveedores/proveedor_venta.dart';
import '../../proveedores/proveedor_vendedor.dart';
import '../../componentes/fondo_agua_ambiental.dart';
import '../../componentes/item_lista_animado.dart';
import '../../componentes/tarjeta_app.dart';
import '../../componentes/logo_app.dart';
import '../../componentes/dialogo_filtro_reporte.dart';
import '../../componentes/encabezado_seccion.dart';
import '../../componentes/tarjeta_estadistica.dart';
import '../../componentes/grilla_inicio.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(proveedorNotificadorVenta);
    final rutasAsync = ref.watch(proveedorNotificadorRuta);
    final productsAsync = ref.watch(proveedorNotificadorProducto);
    final bidonesOverviewAsync = ref.watch(proveedorResumenBidones);
    final authState = ref.watch(
      proveedorNotificadorAuth.select(
        (estado) => (
          usuario: estado.usuario,
          cargando: estado.cargando,
          autenticado: estado.autenticado,
        ),
      ),
    );
    final user = authState.usuario;
    final userRole = user?.rol;
    final esAdministrador = userRole == RolUsuario.admin;
    final esVendedor = userRole == RolUsuario.vendedor;

    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final todaySales = salesAsync.when(
      loading: () => 0,
      error: (_, _) => 0,
      data: (sales) =>
          sales.where((venta) => isSameDay(venta.fecha, today)).length,
    );

    final todayAmount = salesAsync.when(
      loading: () => 0.0,
      error: (_, _) => 0.0,
      data: (sales) => sales
          .where((venta) => isSameDay(venta.fecha, today))
          .fold<double>(0.0, (sum, venta) => sum + venta.total),
    );

    final rutasPendientes = rutasAsync.when(
      loading: () => 0,
      error: (_, _) => 0,
      data: (rutas) => rutas
          .where(
            (ruta) =>
                ruta.estado == EstadoRuta.pendiente ||
                ruta.estado == EstadoRuta.parcial ||
                ruta.estado == EstadoRuta.sinCierre,
          )
          .length,
    );

    final saldoPendiente = rutasAsync.when(
      loading: () => 0.0,
      error: (_, _) => 0.0,
      data: (rutas) => rutas.fold<double>(
        0.0,
        (sum, ruta) =>
            sum + (ruta.saldoPendiente > 0 ? ruta.saldoPendiente : 0),
      ),
    );

    final criticalStock = productsAsync.when(
      loading: () => 0,
      error: (_, _) => 0,
      data: (products) =>
          products.where((producto) => producto.esCritico).length,
    );

    final lowStock = productsAsync.when(
      loading: () => 0,
      error: (_, _) => 0,
      data: (products) => products
          .where((producto) => producto.esBajo && !producto.esCritico)
          .length,
    );

    final totalProducts = productsAsync.when(
      loading: () => 0,
      error: (_, _) => 0,
      data: (products) => products.length,
    );

    final weeklySales = salesAsync.when(
      loading: () => _weeklySalePoints(todayDate),
      error: (_, _) => _weeklySalePoints(todayDate),
      data: (sales) {
        return _weeklySalePoints(todayDate, (day) {
          return sales
              .where((venta) => isSameDay(venta.fecha, day))
              .fold<double>(0.0, (sum, venta) => sum + venta.total);
        });
      },
    );

    final firstName = user?.nombre.trim().split(' ').first ?? 'equipo';
    final roleLabel = userRole == null ? 'SIN ROL' : _roleLabel(userRole);

    final focusCards = <_SignalData>[
      _SignalData(
        title: 'Cobro pendiente',
        value: CurrencyUtils.format(saldoPendiente),
        caption: '$rutasPendientes despachos',
        icon: Icons.account_balance_wallet_rounded,
        color: saldoPendiente > 0 ? AppColors.warning : AppColors.success,
        onTap: () => context.push('/rutas'),
      ),
      _SignalData(
        title: 'Stock sensible',
        value: '$criticalStock criticos',
        caption: '$lowStock bajos',
        icon: Icons.local_shipping_rounded,
        color: criticalStock > 0 ? AppColors.error : AppColors.teal,
        onTap: () => context.push('/inventory'),
      ),
      _SignalData(
        title: 'Movimiento del dia',
        value: '$todaySales ventas',
        caption: esAdministrador
            ? CurrencyUtils.format(todayAmount)
            : 'operaciones registradas',
        icon: Icons.insights_rounded,
        color: AppColors.info,
        onTap: () => context.push('/sales'),
      ),
    ];

    final quickActions = <_QuickActionData>[
      _QuickActionData(
        title: 'Nueva venta',
        subtitle: 'Pedido + cobro',
        icon: Icons.add_shopping_cart_rounded,
        color: AppColors.accent,
        onTap: () => context.push('/sales/new'),
      ),
      _QuickActionData(
        title: 'Despacho',
        subtitle: '$rutasPendientes despachos activos',
        icon: Icons.alt_route_rounded,
        color: AppColors.warning,
        onTap: () => context.push('/rutas'),
      ),
      _QuickActionData(
        title: 'Inventario',
        subtitle: '$totalProducts productos',
        icon: Icons.inventory_2_rounded,
        color: AppColors.teal,
        onTap: () => context.push('/inventory'),
      ),
      if (userRole == RolUsuario.admin)
        _QuickActionData(
          title: 'Usuarios',
          subtitle: 'Permisos y perfiles',
          icon: Icons.manage_accounts_rounded,
          color: AppColors.primary,
          onTap: () => context.push('/users'),
        ),
    ];

    Future<void> refreshAll() async {
      HapticFeedback.lightImpact();
      await Future.wait([
        ref.read(proveedorNotificadorVenta.notifier).cargar(),
        ref.read(proveedorNotificadorRuta.notifier).cargar(),
        ref.read(proveedorNotificadorProducto.notifier).cargar(),
        ref.read(proveedorNotificadorVendedor.notifier).cargar(),
      ]);
      ref.invalidate(proveedorTotalBidonesEmpresa);
    }

    Future<void> abrirFacturadorSri() async {
      HapticFeedback.lightImpact();
      final url = Uri.parse(
        'https://facturadorsri.sri.gob.ec/portal-facturadorsri-internet/pages/inicio.html',
      );
      final abierto = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!abierto && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el Facturador SRI.')),
        );
      }
    }

    if (!esVendedor) {
      quickActions.add(
        _QuickActionData(
          title: 'Generar facturas',
          subtitle: 'Abrir Facturador SRI',
          icon: Icons.request_quote_rounded,
          color: AppColors.primary,
          onTap: abrirFacturadorSri,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Inicio',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_rounded),
            tooltip: 'Mi perfil',
            onPressed: () {
              HapticFeedback.lightImpact();
              context.push('/profile');
            },
          ),
          if (esAdministrador)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: 'Exportar reporte',
              onPressed: () {
                HapticFeedback.lightImpact();
                showDialog(
                  context: context,
                  builder: (_) => const DialogoFiltroReporte(),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: refreshAll,
          ),
        ],
      ),
      body: Stack(
        children: [
          const _DashboardBackdrop(),
          RefreshIndicator(
            color: AppColors.primary,
            onRefresh: refreshAll,
            child: ListView(
              cacheExtent: 720,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                ItemListaAnimado(
                  index: 0,
                  child: _HeroPanel(
                    firstName: firstName,
                    roleLabel: roleLabel,
                    todaySales: todaySales,
                    todayAmount: todayAmount,
                    rutasPendientes: rutasPendientes,
                    saldoPendiente: saldoPendiente,
                    esAdministrador: esAdministrador,
                    onPrimaryTap: () => context.push('/sales/new'),
                    onSecondaryTap: refreshAll,
                  ),
                ),
                const SizedBox(height: 18),
                ItemListaAnimado(
                  index: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const EncabezadoSeccion(title: 'Radar operativo'),
                      SizedBox(
                        height: 176,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: focusCards.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final item = focusCards[index];
                            return SizedBox(
                              width: 255,
                              child: _SignalCard(data: item),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (!esVendedor) ...[
                  ItemListaAnimado(
                    index: 2,
                    child: _BidonesPulseCard(
                      overviewAsync: bidonesOverviewAsync,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.push('/sellers');
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                ItemListaAnimado(
                  index: 3,
                  child: GrillaInicio(
                    children: [
                      TarjetaEstadistica(
                        title: 'Ventas hoy',
                        value: '$todaySales',
                        subtitle: esAdministrador
                            ? CurrencyUtils.format(todayAmount)
                            : 'operaciones registradas',
                        icon: Icons.receipt_long_rounded,
                        color: AppColors.success,
                        onTap: () => context.push('/sales'),
                      ),
                      TarjetaEstadistica(
                        title: 'Despachos abiertos',
                        value: '$rutasPendientes',
                        subtitle: CurrencyUtils.format(saldoPendiente),
                        icon: Icons.route_rounded,
                        color: rutasPendientes > 0
                            ? AppColors.warning
                            : AppColors.teal,
                        onTap: () => context.push('/rutas'),
                      ),
                      TarjetaEstadistica(
                        title: 'Stock crítico',
                        value: '$criticalStock',
                        subtitle: 'requieren atención',
                        icon: Icons.warning_amber_rounded,
                        color: criticalStock > 0
                            ? AppColors.error
                            : AppColors.teal,
                        onTap: () => context.push('/inventory'),
                      ),
                      TarjetaEstadistica(
                        title: 'Stock bajo',
                        value: '$lowStock',
                        subtitle: '$totalProducts productos activos',
                        icon: Icons.inventory_2_rounded,
                        color: lowStock > 0
                            ? AppColors.warning
                            : AppColors.info,
                        onTap: () => context.push('/inventory'),
                      ),
                    ],
                  ),
                ),
                if (esAdministrador) ...[
                  const SizedBox(height: 22),
                  ItemListaAnimado(
                    index: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EncabezadoSeccion(title: 'Pulso semanal'),
                        TarjetaApp(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                          borderRadius: BorderRadius.circular(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _LabelChip(
                                    label:
                                        'Acumulado ${CurrencyUtils.format(weeklySales.fold<double>(0, (sum, point) => sum + point.value))}',
                                    color: AppColors.primary,
                                  ),
                                  _LabelChip(
                                    label: todayAmount > 0
                                        ? 'Hoy activo'
                                        : 'Hoy quieto',
                                    color: AppColors.teal,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _WeeklySalesChart(points: weeklySales),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                ItemListaAnimado(
                  index: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EncabezadoSeccion(
                        title: 'Acciones del día',
                        actionLabel: esAdministrador ? 'Exportar' : null,
                        onAction: esAdministrador
                            ? () {
                                HapticFeedback.lightImpact();
                                showDialog(
                                  context: context,
                                  builder: (_) => const DialogoFiltroReporte(),
                                );
                              }
                            : null,
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 380;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: quickActions.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: constraints.maxWidth >= 1000
                                      ? 4
                                      : constraints.maxWidth >= 600
                                      ? 3
                                      : 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: isCompact ? 196 : 182,
                                ),
                            itemBuilder: (context, index) {
                              return _QuickActionCard(
                                data: quickActions[index],
                                compact: isCompact,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _roleLabel(RolUsuario role) {
    switch (role) {
      case RolUsuario.admin:
        return 'Administrador';
      case RolUsuario.vendedor:
        return 'Vendedor';
      case RolUsuario.planta:
        return 'Planta';
    }
  }

  static List<_WeeklySalePoint> _weeklySalePoints(
    DateTime today, [
    double Function(DateTime day)? valueForDay,
  ]) {
    return List.generate(7, (index) {
      final day = today.subtract(Duration(days: 6 - index));
      return _WeeklySalePoint(date: day, value: valueForDay?.call(day) ?? 0);
    });
  }
}

class _DashboardBackdrop extends StatelessWidget {
  const _DashboardBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: FondoAguaAmbiental(
        primary: AppColors.primary,
        secondary: AppColors.teal,
        accent: AppColors.accent,
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final String firstName;
  final String roleLabel;
  final int todaySales;
  final double todayAmount;
  final int rutasPendientes;
  final double saldoPendiente;
  final bool esAdministrador;
  final VoidCallback onPrimaryTap;
  final VoidCallback onSecondaryTap;

  const _HeroPanel({
    required this.firstName,
    required this.roleLabel,
    required this.todaySales,
    required this.todayAmount,
    required this.rutasPendientes,
    required this.saldoPendiente,
    required this.esAdministrador,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
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
              color: AppColors.primary.withAlpha(26),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -22,
              top: -18,
              child: Icon(
                Icons.water_drop_rounded,
                size: 126,
                color: Colors.white.withAlpha(20),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LogoApp(size: 58),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hola, $firstName',
                            style: GoogleFonts.inter(
                              color: Colors.white.withAlpha(210),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tu operación hoy',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _HeroBadge(
                                label: roleLabel,
                                icon: Icons.verified_user_rounded,
                              ),
                              _HeroBadge(
                                label: '$todaySales ventas hoy',
                                icon: Icons.bolt_rounded,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _HeroMetric(
                        label: esAdministrador ? 'Ventas' : 'Operaciones',
                        value: esAdministrador
                            ? CurrencyUtils.format(todayAmount)
                            : '$todaySales',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroMetric(
                        label: 'Despachos activos',
                        value: '$rutasPendientes',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroMetric(
                        label: esAdministrador ? 'Cobro pendiente' : 'Cobros',
                        value: esAdministrador
                            ? CurrencyUtils.format(saldoPendiente)
                            : '$rutasPendientes despachos',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onPrimaryTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                        ),
                        icon: const Icon(Icons.add_circle_rounded),
                        label: const Text('Nueva venta'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSecondaryTap,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withAlpha(90)),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Actualizar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _HeroBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
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

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(195),
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

class _SignalData {
  final String title;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SignalData({
    required this.title,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _SignalCard extends StatelessWidget {
  final _SignalData data;

  const _SignalCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return TarjetaApp(
      onTap: data.onTap,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: data.color.withAlpha(18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(data.icon, color: data.color, size: 22),
              ),
              const Spacer(),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: data.color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            data.title,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.value,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.caption,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _BidonesPulseCard extends StatelessWidget {
  final AsyncValue<ResumenBidones> overviewAsync;
  final VoidCallback? onTap;

  const _BidonesPulseCard({required this.overviewAsync, this.onTap});

  @override
  Widget build(BuildContext context) {
    return TarjetaApp(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: overviewAsync.when(
        loading: () => const LinearProgressIndicator(color: AppColors.primary),
        error: (error, _) => Text(
          'No se pudo cargar el control de bidones: $error',
          style: GoogleFonts.inter(color: AppColors.error, fontSize: 12),
        ),
        data: (overview) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EncabezadoSeccion(
              title: 'Control de bidones',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            _BidonesFlowStrip(overview: overview),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LabelChip(
                  label: 'Empresa ${overview.totalEmpresa}',
                  color: AppColors.primary,
                ),
                _LabelChip(
                  label: 'Planta ${overview.bidonesEnPlanta}',
                  color: AppColors.teal,
                ),
                _LabelChip(
                  label: 'Con vendedores ${overview.bidonesConVendedores}',
                  color: AppColors.warning,
                ),
                _LabelChip(
                  label: 'Prestados ${overview.bidonesPrestados}',
                  color: AppColors.warning,
                ),
                _LabelChip(
                  label: 'Llenos ${overview.bidonesLlenosConVendedores}',
                  color: AppColors.success,
                ),
                _LabelChip(
                  label: 'Vacíos ${overview.bidonesVaciosConVendedores}',
                  color: AppColors.info,
                ),
                if (overview.bidonesFaltantes > 0)
                  _LabelChip(
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

class _BidonesFlowStrip extends StatelessWidget {
  final ResumenBidones overview;

  const _BidonesFlowStrip({required this.overview});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.factory_rounded, AppColors.primary, overview.totalEmpresa),
      (
        Icons.local_shipping_rounded,
        AppColors.warning,
        overview.bidonesConVendedores,
      ),
      (Icons.water_drop_rounded, AppColors.teal, overview.bidonesEnPlanta),
      (Icons.inventory_2_rounded, AppColors.info, overview.bidonesPrestados),
    ];

    return Row(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: items[index].$2.withAlpha(16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: items[index].$2.withAlpha(34)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    items[index].$1,
                    color: items[index].$2.withAlpha(120),
                    size: 26,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 5,
                    child: Text(
                      '${items[index].$3}',
                      style: GoogleFonts.inter(
                        color: items[index].$2,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (index < items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _LabelChip extends StatelessWidget {
  final String label;
  final Color color;

  const _LabelChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QuickActionData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _QuickActionData data;
  final bool compact;

  const _QuickActionCard({required this.data, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return TarjetaApp(
      onTap: data.onTap,
      padding: EdgeInsets.all(compact ? 14 : 16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 44 : 48,
            height: compact ? 44 : 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [data.color, data.color.withAlpha(170)],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              data.icon,
              color: Colors.white,
              size: compact ? 22 : 24,
            ),
          ),
          SizedBox(height: compact ? 12 : 14),
          Text(
            data.title,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontSize: compact ? 15 : 16,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            data.subtitle,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.4,
            ),
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Abrir',
                style: GoogleFonts.inter(
                  color: data.color,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, size: 16, color: data.color),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklySalePoint {
  final DateTime date;
  final double value;

  const _WeeklySalePoint({required this.date, required this.value});
}

class _WeeklySalesChart extends StatelessWidget {
  final List<_WeeklySalePoint> points;

  const _WeeklySalesChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final maxValue = points.fold<double>(
      0.0,
      (max, point) => point.value > max ? point.value : max,
    );

    return SizedBox(
      height: 188,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(points.length, (index) {
          final point = points[index];
          final value = point.value;
          final factor = maxValue <= 0 ? 0.0 : value / maxValue;
          final barHeight = 26 + (96 * factor);
          final isToday =
              point.date.year == today.year &&
              point.date.month == today.month &&
              point.date.day == today.day;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    value > 0 ? value.toStringAsFixed(0) : '',
                    style: GoogleFonts.inter(
                      color: AppColors.textHint(context),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutCubic,
                    width: double.infinity,
                    height: barHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: isToday
                          ? const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [AppColors.accent, AppColors.accentSoft],
                            )
                          : const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.primaryLight,
                                AppColors.primary,
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppDateUtils.weekdayInitial(point.date),
                    style: GoogleFonts.inter(
                      color: isToday
                          ? AppColors.primary
                          : AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
