import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/constantes/textos_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../nucleo/utilidades/utilidades_fecha.dart';
import '../../../datos/modelos/ruta.dart';
import '../../../datos/modelos/venta.dart';
import '../../../datos/modelos/vendedor.dart';
import '../../../datos/servicios/servicio_venta.dart';
import '../../../dominio/entidades/rol_usuario.dart';
import '../../proveedores/proveedor_autenticacion.dart';
import '../../proveedores/proveedor_ruta.dart';
import '../../proveedores/proveedor_venta.dart';
import '../../proveedores/proveedor_vendedor.dart';
import '../../componentes/fondo_agua_ambiental.dart';
import '../../componentes/tarjeta_app.dart';
import '../../componentes/encabezado_seccion.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  static const _limiteVentasRecientes = 30;
  static const _limiteConsultaHistorica = 300;

  String? _selectedSellerId;
  AsyncValue<List<Venta>> _salesAsync = const AsyncLoading();
  ResumenVentas? _resumenConsulta;
  _FiltroVentasHistoricas? _filtroHistorico;

  bool get _mostrandoHistorico => _filtroHistorico != null;
  bool get _esVentaDistribuidoraFiltro =>
      _selectedSellerId == Vendedor.distribuidora.id;

  @override
  void initState() {
    super.initState();
    Future.microtask(_cargarVentasRecientes);
  }

  Future<void> _cargarVentasRecientes({
    bool limpiarFiltros = false,
    bool silencioso = false,
  }) async {
    if (mounted && !silencioso) {
      setState(() {
        _salesAsync = const AsyncLoading();
        _resumenConsulta = null;
        _filtroHistorico = null;
        if (limpiarFiltros) _selectedSellerId = null;
      });
    }
    try {
      final ventas = await ref
          .read(proveedorServicioVenta)
          .obtenerRecientes(limite: _limiteVentasRecientes);
      if (!mounted) return;
      setState(() => _salesAsync = AsyncData(ventas));
    } catch (error, stackTrace) {
      if (!mounted) return;
      if (!silencioso) {
        setState(() => _salesAsync = AsyncError(error, stackTrace));
      }
    }
  }

  Future<void> _cargarVentasHistoricas(
    _FiltroVentasHistoricas filtro, {
    bool silencioso = false,
  }) async {
    if (mounted && !silencioso) {
      setState(() {
        _salesAsync = const AsyncLoading();
        _resumenConsulta = null;
        _filtroHistorico = filtro;
        _selectedSellerId = filtro.vendedorId;
      });
    }
    try {
      final servicio = ref.read(proveedorServicioVenta);
      final ventasFuture = servicio.consultarPorFiltros(
        fechaInicio: filtro.fechaInicio,
        fechaFin: filtro.fechaFin,
        vendedorId: filtro.vendedorId,
        limite: _limiteConsultaHistorica,
      );
      final resumenFuture = servicio.resumirPorFiltros(
        fechaInicio: filtro.fechaInicio,
        fechaFin: filtro.fechaFin,
        vendedorId: filtro.vendedorId,
      );
      final resultados = await Future.wait<Object>([
        ventasFuture,
        resumenFuture,
      ]);
      if (!mounted) return;
      setState(() {
        _salesAsync = AsyncData(resultados[0] as List<Venta>);
        _resumenConsulta = resultados[1] as ResumenVentas;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _salesAsync = AsyncError(error, stackTrace));
    }
  }

  Future<void> _actualizarFiltroVendedor(String? vendedorId) async {
    final filtro = _filtroHistorico;
    if (filtro == null) {
      setState(() => _selectedSellerId = vendedorId);
      return;
    }

    await _cargarVentasHistoricas(filtro.copiarCon(vendedorId: vendedorId));
  }

  Future<void> _recargarVentasActuales({bool silencioso = true}) async {
    final filtro = _filtroHistorico;
    if (filtro == null) {
      await _cargarVentasRecientes(silencioso: silencioso);
    } else {
      await _cargarVentasHistoricas(filtro, silencioso: silencioso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = _salesAsync;
    final sellersAsync = ref.watch(proveedorNotificadorVendedor);
    final rutasAsync = ref.watch(proveedorNotificadorRuta);
    final rol = ref.watch(
      proveedorNotificadorAuth.select((estado) => estado.usuario?.rol),
    );
    final esAdministrador = rol == RolUsuario.admin;

    Future<void> refreshAll() async {
      HapticFeedback.lightImpact();
      await Future.wait([
        _recargarVentasActuales(silencioso: false),
        ref.read(proveedorNotificadorRuta.notifier).cargar(),
        ref.read(proveedorNotificadorVendedor.notifier).cargar(),
      ]);
      ref.invalidate(proveedorVendedoresActivos);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.sales),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_search_rounded),
            onPressed: () => _abrirConsultaHistorica(context),
            tooltip: 'Consultar ventas',
          ),
          IconButton(
            icon: const Icon(Icons.people_outline_rounded),
            onPressed: () => context.push('/sellers'),
            tooltip: 'Vendedores',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _goToNewSale(context),
            tooltip: AppStrings.newSale,
          ),
        ],
      ),
      body: Stack(
        children: [
          const _SalesBackdrop(),
          salesAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (_, _) => _SalesErrorState(onRetry: refreshAll),
            data: (sales) {
              final filtroHistorico = _filtroHistorico;
              final resumenConsulta = _resumenConsulta;
              final rutas = rutasAsync.asData?.value ?? const <Ruta>[];
              final sellers = sellersAsync.asData?.value ?? const <Vendedor>[];
              final selectedSeller =
                  _selectedSellerId == null || _esVentaDistribuidoraFiltro
                  ? null
                  : sellers
                        .where((vendedor) => vendedor.id == _selectedSellerId)
                        .firstOrNull;
              final selectedSellerName = _selectedSellerId == null
                  ? 'Todos los vendedores'
                  : _esVentaDistribuidoraFiltro
                  ? 'Distribuidora Central'
                  : sellers
                            .where(
                              (vendedor) => vendedor.id == _selectedSellerId,
                            )
                            .map((vendedor) => vendedor.nombre)
                            .firstOrNull ??
                        'Vendedor seleccionado';

              final filteredSales = sales
                  .where((venta) => _ventaCoincideVendedor(venta))
                  .toList();

              final sellerRutas =
                  _selectedSellerId == null || _esVentaDistribuidoraFiltro
                        ? <Ruta>[]
                        : rutas
                              .where(
                                (ruta) =>
                                    ruta.vendedorId == _selectedSellerId &&
                                    _rutaDentroDelFiltro(ruta, filtroHistorico),
                              )
                              .toList()
                    ..sort((a, b) {
                      final byDate = b.fecha.compareTo(a.fecha);
                      if (byDate != 0) return byDate;
                      return b.creadoEn.compareTo(a.creadoEn);
                    });

              final groupedSales = <String, List<Venta>>{};
              for (final venta in filteredSales) {
                final key = AppDateUtils.formatDate(venta.fecha);
                groupedSales.putIfAbsent(key, () => []).add(venta);
              }

              final totalVentas = filteredSales.fold<double>(
                0.0,
                (sum, venta) => sum + venta.total,
              );

              final totalAbonos =
                  _selectedSellerId == null || _esVentaDistribuidoraFiltro
                  ? 0.0
                  : sellerRutas.fold<double>(
                      0.0,
                      (sum, ruta) => sum + ruta.montoCobrado,
                    );

              final saldoPendienteTotal =
                  _selectedSellerId == null || _esVentaDistribuidoraFiltro
                  ? 0.0
                  : sellerRutas.fold<double>(
                      0.0,
                      (sum, ruta) => sum + ruta.saldoPendienteVisible,
                    );
              final saldoAFavorTotal =
                  _selectedSellerId == null || _esVentaDistribuidoraFiltro
                  ? 0.0
                  : sellerRutas.fold<double>(
                      0.0,
                      (sum, ruta) => sum + ruta.saldoAFavor,
                    );
              final saldo = saldoPendienteTotal - saldoAFavorTotal;

              final pendingRutasForSeller =
                  rutas
                      .where(
                        (ruta) =>
                            _selectedSellerId != null &&
                            !_esVentaDistribuidoraFiltro &&
                            ruta.vendedorId == _selectedSellerId &&
                            ruta.saldoPendiente > 0,
                      )
                      .toList()
                    ..sort((a, b) {
                      final byDate = a.fecha.compareTo(b.fecha);
                      if (byDate != 0) return byDate;
                      return a.creadoEn.compareTo(b.creadoEn);
                    });

              final pendientesRutas = rutasAsync.when(
                data: (value) => value.length,
                loading: () => 0,
                error: (_, _) => 0,
              );

              final totalOperations = filteredSales.length;

              final groupedEntries = groupedSales.entries.toList();
              final tituloListado = _mostrandoHistorico
                  ? 'Ventas consultadas'
                  : 'Ventas recientes';

              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: refreshAll,
                child: ListView(
                  cacheExtent: 720,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                  children: [
                    _SalesHero(
                      selectedSellerName: selectedSellerName,
                      selectedSellerId: _selectedSellerId,
                      totalVentas: totalVentas,
                      totalAbonos: totalAbonos,
                      saldo: saldo,
                      pendientesRutas: pendientesRutas,
                      totalOperations: totalOperations,
                      esAdministrador: esAdministrador,
                      onNewSale: () => _goToNewSale(context),
                      onViewRoutes: () => context.push('/rutas'),
                    ),
                    const SizedBox(height: 16),
                    TarjetaApp(
                      padding: const EdgeInsets.all(16),
                      borderRadius: BorderRadius.circular(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Filtrar operaciones',
                                  style: GoogleFonts.inter(
                                    color: AppColors.textPrimary(context),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    _abrirConsultaHistorica(context),
                                icon: const Icon(
                                  Icons.manage_search_rounded,
                                  size: 18,
                                ),
                                label: const Text('Consultar'),
                              ),
                            ],
                          ),
                          if (_mostrandoHistorico) ...[
                            const SizedBox(height: 8),
                            _HistoricalQueryBanner(
                              filtro: filtroHistorico!,
                              sellerName: selectedSellerName,
                              onClear: () =>
                                  _cargarVentasRecientes(limpiarFiltros: true),
                            ),
                            if (resumenConsulta != null) ...[
                              const SizedBox(height: 10),
                              _HistoricalTotalsCard(
                                resumen: resumenConsulta,
                                resultadosMostrados: filteredSales.length,
                                limiteResultados: _limiteConsultaHistorica,
                              ),
                            ],
                          ],
                          const SizedBox(height: 14),
                          _SellerFilterPanel(
                            sellersAsync: sellersAsync,
                            selectedSellerId: _selectedSellerId,
                            onChanged: (value) {
                              _actualizarFiltroVendedor(value);
                            },
                          ),
                          if (_selectedSellerId != null) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _goToNewSale(context),
                                  icon: const Icon(Icons.point_of_sale_rounded),
                                  label: const Text('Nueva venta'),
                                ),
                                if (saldoPendienteTotal > 0)
                                  OutlinedButton.icon(
                                    onPressed: pendingRutasForSeller.isEmpty
                                        ? null
                                        : () {
                                            final ruta =
                                                pendingRutasForSeller.first;
                                            context.push(
                                              '/rutas/detail/${ruta.id}?showAbono=1',
                                            );
                                          },
                                    icon: const Icon(Icons.payments_outlined),
                                    label: const Text('Registrar abono'),
                                  ),
                              ],
                            ),
                            if (selectedSeller != null) ...[
                              const SizedBox(height: 14),
                              _SellerOperationalCard(
                                vendedor: selectedSeller,
                                saldoPendienteTotal: saldoPendienteTotal,
                                saldoAFavorTotal: saldoAFavorTotal,
                                rutasPendientes: pendingRutasForSeller.length,
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (_selectedSellerId != null) ...[
                      const EncabezadoSeccion(title: 'Ventas del vendedor'),
                      if (groupedEntries.isEmpty)
                        const _EmptySalesState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Sin ventas para este vendedor',
                          subtitle:
                              'Selecciona otro perfil o registra una nueva venta.',
                        )
                      else
                        ...groupedEntries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SalesGroupCard(
                              dateLabel: entry.key,
                              sales: entry.value,
                              mostrarTotal: esAdministrador,
                              onRefresh: _recargarVentasActuales,
                            ),
                          ),
                        ),
                      if (sellerRutas.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const EncabezadoSeccion(
                          title: 'Despachos del vendedor',
                        ),
                        ...sellerRutas.map(
                          (ruta) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RutaVentaCard(ruta: ruta),
                          ),
                        ),
                      ],
                    ] else ...[
                      EncabezadoSeccion(title: tituloListado),
                      if (groupedEntries.isEmpty)
                        const _EmptySalesState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Aún no hay ventas registradas',
                          subtitle:
                              'Cuando registres la primera venta, aparecerán aquí organizadas por fecha.',
                        )
                      else
                        ...groupedEntries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SalesGroupCard(
                              dateLabel: entry.key,
                              sales: entry.value,
                              mostrarTotal: esAdministrador,
                              onRefresh: _recargarVentasActuales,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _goToNewSale(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          AppStrings.newSale,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _abrirConsultaHistorica(BuildContext context) async {
    final filtro = await showDialog<_FiltroVentasHistoricas>(
      context: context,
      builder: (_) => _DialogoConsultaVentas(filtroInicial: _filtroHistorico),
    );
    if (filtro == null) return;
    await _cargarVentasHistoricas(filtro);
  }

  bool _rutaDentroDelFiltro(Ruta ruta, _FiltroVentasHistoricas? filtro) {
    if (filtro == null) return true;
    final fecha = AppDateUtils.startOfDay(ruta.fecha);
    final inicio = AppDateUtils.startOfDay(filtro.fechaInicio);
    final fin = AppDateUtils.startOfDay(filtro.fechaFin);
    return !fecha.isBefore(inicio) && !fecha.isAfter(fin);
  }

  bool _ventaCoincideVendedor(Venta venta) {
    final selectedSellerId = _selectedSellerId;
    if (selectedSellerId == null) return true;
    if (selectedSellerId == Vendedor.distribuidora.id) {
      return venta.vendedorId == null || venta.vendedorId!.isEmpty;
    }
    return venta.vendedorId == selectedSellerId;
  }

  Future<void> _goToNewSale(BuildContext context) async {
    await context.push(
      _selectedSellerId == null || _esVentaDistribuidoraFiltro
          ? '/sales/new'
          : '/sales/new?sellerId=$_selectedSellerId',
    );
    if (mounted) {
      await _cargarVentasRecientes();
    }
  }
}

class _FiltroVentasHistoricas {
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String? vendedorId;

  const _FiltroVentasHistoricas({
    required this.fechaInicio,
    required this.fechaFin,
    this.vendedorId,
  });

  _FiltroVentasHistoricas copiarCon({String? vendedorId}) =>
      _FiltroVentasHistoricas(
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        vendedorId: vendedorId,
      );
}

class _DialogoConsultaVentas extends ConsumerStatefulWidget {
  final _FiltroVentasHistoricas? filtroInicial;

  const _DialogoConsultaVentas({this.filtroInicial});

  @override
  ConsumerState<_DialogoConsultaVentas> createState() =>
      _DialogoConsultaVentasState();
}

class _DialogoConsultaVentasState
    extends ConsumerState<_DialogoConsultaVentas> {
  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  String? _vendedorId;

  @override
  void initState() {
    super.initState();
    final inicial = widget.filtroInicial;
    _fechaInicio =
        inicial?.fechaInicio ??
        DateTime.now().subtract(const Duration(days: 7));
    _fechaFin = inicial?.fechaFin ?? DateTime.now();
    _vendedorId = inicial?.vendedorId;
  }

  Future<void> _seleccionarInicio() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _fechaInicio,
      firstDate: DateTime(2020),
      lastDate: _fechaFin,
    );
    if (date != null) setState(() => _fechaInicio = date);
  }

  Future<void> _seleccionarFin() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _fechaFin,
      firstDate: _fechaInicio,
      lastDate: DateTime.now(),
    );
    if (date != null) setState(() => _fechaFin = date);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    final sellersAsync = ref.watch(proveedorNotificadorVendedor);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(
        'Consultar ventas',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: compact ? 19 : 21,
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 320 : 430),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Elige un rango de fechas y, si aplica, un vendedor.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary(context),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              if (compact) ...[
                _DateField(
                  label: 'Desde',
                  value: AppDateUtils.formatDate(_fechaInicio),
                  onTap: _seleccionarInicio,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: 'Hasta',
                  value: AppDateUtils.formatDate(_fechaFin),
                  onTap: _seleccionarFin,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Desde',
                        value: AppDateUtils.formatDate(_fechaInicio),
                        onTap: _seleccionarInicio,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Hasta',
                        value: AppDateUtils.formatDate(_fechaFin),
                        onTap: _seleccionarFin,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              sellersAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => Text(
                  'No se pudo cargar la lista de vendedores.',
                  style: GoogleFonts.inter(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                data: (sellers) {
                  final allSellers = [Vendedor.distribuidora, ...sellers];
                  return DropdownButtonFormField<String?>(
                    initialValue: _vendedorId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vendedor',
                      prefixIcon: Icon(Icons.storefront_rounded),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: _DropdownLabel(
                          'Todo: distribuidora y vendedores',
                        ),
                      ),
                      ...allSellers.map(
                        (vendedor) => DropdownMenuItem<String?>(
                          value: vendedor.id,
                          child: _DropdownLabel(
                            vendedor.esDistribuidora
                                ? 'Distribuidora Central'
                                : vendedor.nombre,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _vendedorId = value),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop(
                  _FiltroVentasHistoricas(
                    fechaInicio: _fechaInicio,
                    fechaFin: _fechaFin,
                    vendedorId: _vendedorId,
                  ),
                );
              },
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Consultar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          label: Text(label),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(
          value,
          style: GoogleFonts.inter(
            color: AppColors.textPrimary(context),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DropdownLabel extends StatelessWidget {
  final String text;

  const _DropdownLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: AppColors.textPrimary(context),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HistoricalQueryBanner extends StatelessWidget {
  final _FiltroVentasHistoricas filtro;
  final String sellerName;
  final VoidCallback onClear;

  const _HistoricalQueryBanner({
    required this.filtro,
    required this.sellerName,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final rango =
        '${AppDateUtils.formatDate(filtro.fechaInicio)} - ${AppDateUtils.formatDate(filtro.fechaFin)}';
    final vendedor = filtro.vendedorId == null ? 'Todos' : sellerName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withAlpha(34)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.manage_search_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$rango | $vendedor',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onClear, child: const Text('Recientes')),
        ],
      ),
    );
  }
}

class _HistoricalTotalsCard extends StatelessWidget {
  final ResumenVentas resumen;
  final int resultadosMostrados;
  final int limiteResultados;

  const _HistoricalTotalsCard({
    required this.resumen,
    required this.resultadosMostrados,
    required this.limiteResultados,
  });

  @override
  Widget build(BuildContext context) {
    final limitado = resumen.cantidad > resultadosMostrados;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withAlpha(16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withAlpha(36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  label: 'Total vendido',
                  value: CurrencyUtils.format(resumen.total),
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryValue(
                  label: 'Ventas',
                  value: '${resumen.cantidad}',
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (limitado) ...[
            const SizedBox(height: 10),
            Text(
              'Mostrando $resultadosMostrados de ${resumen.cantidad} ventas. El total corresponde a toda la consulta.',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ] else if (resumen.cantidad >= limiteResultados) ...[
            const SizedBox(height: 10),
            Text(
              'La lista se limita a $limiteResultados resultados para mantener la pantalla fluida.',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary(context),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary(context),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _SalesBackdrop extends StatelessWidget {
  const _SalesBackdrop();

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

class _SalesHero extends StatelessWidget {
  final String selectedSellerName;
  final String? selectedSellerId;
  final double totalVentas;
  final double totalAbonos;
  final double saldo;
  final int pendientesRutas;
  final int totalOperations;
  final bool esAdministrador;
  final VoidCallback onNewSale;
  final VoidCallback onViewRoutes;

  const _SalesHero({
    required this.selectedSellerName,
    required this.selectedSellerId,
    required this.totalVentas,
    required this.totalAbonos,
    required this.saldo,
    required this.pendientesRutas,
    required this.totalOperations,
    required this.esAdministrador,
    required this.onNewSale,
    required this.onViewRoutes,
  });

  @override
  Widget build(BuildContext context) {
    final hasFilter = selectedSellerId != null;
    final saldoLabel = saldo < 0 ? 'Saldo a favor' : 'Saldo pendiente';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
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
            blurRadius: 28,
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
              _HeroPill(
                icon: Icons.bar_chart_rounded,
                label: hasFilter ? 'Vista por vendedor' : 'Vista general',
              ),
              _HeroPill(
                icon: Icons.route_rounded,
                label: '$pendientesRutas despachos pendientes',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            selectedSellerName,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: esAdministrador ? 'Facturado' : 'Operaciones',
                  value: esAdministrador
                      ? CurrencyUtils.format(totalVentas)
                      : '$totalOperations',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMetric(
                  label: esAdministrador ? 'Abonos' : 'Despacho',
                  value: esAdministrador
                      ? CurrencyUtils.format(totalAbonos)
                      : '$pendientesRutas',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMetric(
                  label: esAdministrador ? saldoLabel : 'Cobro',
                  value: esAdministrador
                      ? CurrencyUtils.format(saldo.abs())
                      : 'por despacho',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    title: 'Operaciones',
                    value: '$totalOperations',
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withAlpha(26),
                ),
                Expanded(
                  child: _MiniStat(
                    title: 'Despachos activos',
                    value: '$pendientesRutas',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onNewSale,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Nueva venta'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onViewRoutes,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withAlpha(90)),
                  ),
                  icon: const Icon(Icons.alt_route_rounded),
                  label: const Text('Ver despacho'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(26)),
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

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
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

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;

  const _MiniStat({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: Colors.white.withAlpha(200),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerFilterPanel extends StatelessWidget {
  final AsyncValue<List<Vendedor>> sellersAsync;
  final String? selectedSellerId;
  final ValueChanged<String?> onChanged;

  const _SellerFilterPanel({
    required this.sellersAsync,
    required this.selectedSellerId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: sellersAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LinearProgressIndicator(color: AppColors.primary),
        ),
        error: (_, _) => Text(
          'No se pudo cargar la lista de vendedores.',
          style: GoogleFonts.inter(
            color: AppColors.error,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        data: (sellers) {
          final allSellers = [Vendedor.distribuidora, ...sellers];
          return DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedSellerId ?? '__all__',
              icon: const Icon(Icons.expand_more_rounded),
              items: [
                DropdownMenuItem<String>(
                  value: '__all__',
                  child: Text(
                    'Todos los vendedores',
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                  ),
                ),
                ...allSellers.map(
                  (vendedor) => DropdownMenuItem<String>(
                    value: vendedor.id,
                    child: Text(
                      vendedor.esDistribuidora
                          ? 'Distribuidora Central'
                          : vendedor.nombre,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary(context),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
              onChanged: (value) {
                onChanged(value == null || value == '__all__' ? null : value);
              },
            ),
          );
        },
      ),
    );
  }
}

class _SellerOperationalCard extends StatelessWidget {
  final Vendedor vendedor;
  final double saldoPendienteTotal;
  final double saldoAFavorTotal;
  final int rutasPendientes;

  const _SellerOperationalCard({
    required this.vendedor,
    required this.saldoPendienteTotal,
    required this.saldoAFavorTotal,
    required this.rutasPendientes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen consolidado del vendedor',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SellerInsightChip(
                label: 'Pendiente total',
                value: CurrencyUtils.format(saldoPendienteTotal),
                color: saldoPendienteTotal > 0
                    ? AppColors.error
                    : AppColors.success,
              ),
              _SellerInsightChip(
                label: 'A favor',
                value: CurrencyUtils.format(saldoAFavorTotal),
                color: AppColors.success,
              ),
              _SellerInsightChip(
                label: 'Despachos pendientes',
                value: '$rutasPendientes',
                color: AppColors.warning,
              ),
              _SellerInsightChip(
                label: 'Llenos actuales',
                value: '${vendedor.bidonesLlenosActuales}',
                color: AppColors.primary,
              ),
              _SellerInsightChip(
                label: 'Vacíos actuales',
                value: '${vendedor.bidonesVaciosActuales}',
                color: AppColors.teal,
              ),
              _SellerInsightChip(
                label: 'Prestados',
                value: '${vendedor.bidonesPrestados}',
                color: AppColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SellerInsightChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SellerInsightChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
              color: AppColors.textSecondary(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesGroupCard extends StatelessWidget {
  final String dateLabel;
  final List<Venta> sales;
  final bool mostrarTotal;
  final VoidCallback? onRefresh;

  const _SalesGroupCard({
    required this.dateLabel,
    required this.sales,
    required this.mostrarTotal,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final total = sales.fold<double>(0.0, (sum, venta) => sum + venta.total);

    return TarjetaApp(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dateLabel,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary(context),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (mostrarTotal)
                Text(
                  CurrencyUtils.format(total),
                  style: GoogleFonts.inter(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...sales.map(
            (venta) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SaleCard(venta: venta, onRefresh: onRefresh),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleCard extends StatelessWidget {
  final Venta venta;
  final VoidCallback? onRefresh;

  const _SaleCard({required this.venta, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final itemCount = venta.items.fold<int>(
      0,
      (sum, item) => sum + item.cantidad,
    );

    return TarjetaApp(
      onTap: () async {
        await context.push('/sales/detail/${venta.id}');
        onRefresh?.call();
      },
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(18),
      color: AppColors.surfaceVariant(context),
      border: Border.all(color: AppColors.border(context)),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Venta #${venta.id.substring(0, 8).toUpperCase()}',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${venta.mostrarVendedor} | $itemCount item${itemCount == 1 ? '' : 's'} | ${AppDateUtils.formatTime(venta.creadoEn)}',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary(context),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyUtils.format(venta.total),
                style: GoogleFonts.inter(
                  color: AppColors.success,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint(context),
                size: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RutaVentaCard extends StatelessWidget {
  final Ruta ruta;

  const _RutaVentaCard({required this.ruta});

  @override
  Widget build(BuildContext context) {
    final saldoColor = ruta.saldoPendiente > 0
        ? AppColors.error
        : AppColors.success;
    final saldoLabel = ruta.tieneSaldoAFavor ? 'A favor' : 'Saldo';
    final saldoValue = ruta.tieneSaldoAFavor
        ? ruta.saldoAFavor
        : ruta.saldoPendienteVisible;

    return TarjetaApp(
      onTap: () => context.push('/rutas/detail/${ruta.id}'),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(22),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.warning, AppColors.warning.withAlpha(180)],
              ),
            ),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Despacho ${AppDateUtils.formatDate(ruta.fecha)}',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cobrado ${CurrencyUtils.format(ruta.montoCobrado)} de ${CurrencyUtils.format(ruta.montoTotal)}',
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
              Text(
                CurrencyUtils.format(ruta.montoTotal),
                style: GoogleFonts.inter(
                  color: AppColors.success,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$saldoLabel ${CurrencyUtils.format(saldoValue)}',
                style: GoogleFonts.inter(
                  color: saldoColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptySalesState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptySalesState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 56, color: AppColors.textHint(context)),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary(context),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
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

class _SalesErrorState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _SalesErrorState({required this.onRetry});

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
                Icons.signal_wifi_connected_no_internet_4_rounded,
                size: 46,
                color: AppColors.error,
              ),
              const SizedBox(height: 12),
              Text(
                'No se pudo cargar ventas',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Intenta actualizar nuevamente.',
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
