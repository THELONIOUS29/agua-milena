import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../datos/modelos/vendedor.dart';
import '../../../datos/modelos/precio_producto.dart';
import '../../proveedores/proveedor_bidones.dart';
import '../../proveedores/proveedor_vendedor.dart';
import '../../proveedores/proveedor_producto.dart';
import '../../proveedores/proveedor_precio.dart';

class SellersScreen extends ConsumerWidget {
  const SellersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sellersAsync = ref.watch(proveedorNotificadorVendedor);
    final bidonesOverviewAsync = ref.watch(proveedorResumenBidones);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendedores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sell_outlined),
            tooltip: 'Precios distribuidora',
            onPressed: () => showDialog(
              context: context,
              builder: (_) =>
                  _VendorPricesModal(vendedor: Vendedor.distribuidora),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.directions_bike_rounded),
            onPressed: () => context.push('/rutas'),
            tooltip: 'Ver despacho',
          ),
          IconButton(
            icon: const Icon(Icons.water_drop_rounded),
            onPressed: () => _showTotalBidonesDialog(context, ref),
            tooltip: 'Configurar bidones de empresa',
          ),
        ],
      ),
      body: sellersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => Center(child: Text('$error')),
        data: (sellers) {
          if (sellers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 56,
                    color: AppColors.textHint(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sin vendedores registrados',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: sellers.length + 1,
            itemBuilder: (_, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ResumenBidonesCard(
                    overviewAsync: bidonesOverviewAsync,
                  ),
                );
              }
              return _SellerCard(vendedor: sellers[index - 1]);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/users/add?rol=vendedor'),
        icon: const Icon(Icons.person_add_rounded),
        label: Text(
          'Crear usuario vendedor',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static void _showSellerForm(
    BuildContext context,
    WidgetRef ref,
    Vendedor existing,
  ) {
    final nameCtrl = TextEditingController(text: existing.nombre);
    final phoneCtrl = TextEditingController(text: existing.telefono ?? '');
    final bidonesCtrl = TextEditingController(
      text: existing.bidonesPropios > 0
          ? existing.bidonesPropios.toString()
          : '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: AppColors.surface(context),
        title: Text(
          'Editar vendedor',
          style: GoogleFonts.inter(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'El nombre es requerido'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (opcional)',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bidonesCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                    decoration: InputDecoration(
                      labelText: 'Bidones propios',
                      hintText: 'Ej: 30',
                      prefixIcon: const Icon(Icons.water_rounded),
                      helperText:
                          'Total de bidones que pertenecen a este vendedor',
                      helperStyle: TextStyle(
                        color: AppColors.textHint(context),
                        fontSize: 11,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = int.tryParse(value.trim());
                      if (parsed == null) return 'Ingresa un número';
                      if (parsed < 0) return 'Debe ser mayor o igual a 0';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: Size.zero),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);

              final phone = phoneCtrl.text.trim().isEmpty
                  ? null
                  : phoneCtrl.text.trim();
              final bidones = int.tryParse(bidonesCtrl.text.trim()) ?? 0;
              final llenosActuales = existing.bidonesLlenosActuales;
              final vaciosActuales = existing.bidonesVaciosActuales;
              final prestados = (llenosActuales + vaciosActuales - bidones)
                  .clamp(0, 1 << 30)
                  .toInt();

              await ref
                  .read(proveedorNotificadorVendedor.notifier)
                  .actualizar(
                    existing.id,
                    nombre: nameCtrl.text.trim(),
                    telefono: phone,
                    bidonesPropios: bidones,
                    bidonesPrestados: prestados,
                  );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showTotalBidonesDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final currentTotal = await ref.read(proveedorTotalBidonesEmpresa.future);
    if (!context.mounted) return;
    final ctrl = TextEditingController(text: '$currentTotal');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: AppColors.surface(context),
        title: Text(
          'Total de bidones de la empresa',
          style: GoogleFonts.inter(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: TextStyle(color: AppColors.textPrimary(context)),
          decoration: const InputDecoration(
            labelText: 'Total general',
            prefixIcon: Icon(Icons.warehouse_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final total = int.tryParse(ctrl.text.trim());
              if (total == null || total < 0) return;
              await ref
                  .read(proveedorServicioConfigBidones)
                  .establecerTotalBidonesEmpresa(total);
              ref.invalidate(proveedorTotalBidonesEmpresa);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _ResumenBidonesCard extends StatelessWidget {
  final AsyncValue<ResumenBidones> overviewAsync;

  const _ResumenBidonesCard({required this.overviewAsync});

  @override
  Widget build(BuildContext context) {
    return overviewAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(color: AppColors.primary),
        ),
      ),
      error: (error, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No se pudo cargar el resumen de bidones: $error',
            style: GoogleFonts.inter(color: AppColors.error),
          ),
        ),
      ),
      data: (overview) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Resumen global de bidones',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Controla lo que está en planta y lo que se encuentra en manos de los vendedores.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary(context),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SellerMetricPill(
                    icon: Icons.warehouse_rounded,
                    label: 'Empresa ${overview.totalEmpresa}',
                    color: AppColors.primary,
                  ),
                  _SellerMetricPill(
                    icon: Icons.store_rounded,
                    label: 'Planta ${overview.bidonesEnPlanta}',
                    color: AppColors.teal,
                  ),
                  _SellerMetricPill(
                    icon: Icons.local_shipping_rounded,
                    label: 'Con vendedores ${overview.bidonesConVendedores}',
                    color: AppColors.warning,
                  ),
                  _SellerMetricPill(
                    icon: Icons.handshake_rounded,
                    label: 'Prestados ${overview.bidonesPrestados}',
                    color: AppColors.warning,
                  ),
                  _SellerMetricPill(
                    icon: Icons.inventory_2_rounded,
                    label: 'Llenos ${overview.bidonesLlenosConVendedores}',
                    color: AppColors.success,
                  ),
                  _SellerMetricPill(
                    icon: Icons.recycling_rounded,
                    label: 'Vacíos ${overview.bidonesVaciosConVendedores}',
                    color: AppColors.teal,
                  ),
                  if (overview.bidonesFaltantes > 0)
                    _SellerMetricPill(
                      icon: Icons.warning_amber_rounded,
                      label: 'Faltantes ${overview.bidonesFaltantes}',
                      color: AppColors.error,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellerCard extends ConsumerWidget {
  final Vendedor vendedor;

  const _SellerCard({required this.vendedor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 460;

            final actions = [
              Switch(
                value: vendedor.activo,
                activeThumbColor: AppColors.success,
                onChanged: (value) => ref
                    .read(proveedorNotificadorVendedor.notifier)
                    .actualizar(vendedor.id, activo: value),
              ),
              IconButton(
                icon: const Icon(
                  Icons.sell_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                tooltip: 'Gestionar precios',
                onPressed: () =>
                    _showVendorPricesDialog(context, ref, vendedor),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                onPressed: () =>
                    SellersScreen._showSellerForm(context, ref, vendedor),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
                onPressed: () => _confirmDelete(context, ref),
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.primary.withAlpha(38),
                      child: Text(
                        vendedor.nombre.isNotEmpty
                            ? vendedor.nombre[0].toUpperCase()
                            : '-',
                        style: GoogleFonts.inter(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vendedor.nombre,
                            style: GoogleFonts.inter(
                              color: vendedor.activo
                                  ? AppColors.textPrimary(context)
                                  : AppColors.textHint(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          if (vendedor.telefono != null &&
                              vendedor.telefono!.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              vendedor.telefono!,
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!compact)
                      Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (vendedor.bidonesPropios > 0)
                      _SellerMetricPill(
                        icon: Icons.water_rounded,
                        label: 'Propios ${vendedor.bidonesPropios}',
                        color: AppColors.primary,
                      ),
                    if (vendedor.bidonesLlenosActuales > 0)
                      _SellerMetricPill(
                        icon: Icons.local_shipping_rounded,
                        label: 'Llenos ${vendedor.bidonesLlenosActuales}',
                        color: AppColors.success,
                      ),
                    if (vendedor.bidonesVaciosActuales > 0)
                      _SellerMetricPill(
                        icon: Icons.recycling_rounded,
                        label: 'Vacíos ${vendedor.bidonesVaciosActuales}',
                        color: AppColors.teal,
                      ),
                    if (vendedor.bidonesPrestados > 0)
                      _SellerMetricPill(
                        icon: Icons.handshake_rounded,
                        label: 'Prestados ${vendedor.bidonesPrestados}',
                        color: AppColors.warning,
                      ),
                  ],
                ),
                if (compact) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _showVendorPricesDialog(
    BuildContext context,
    WidgetRef ref,
    Vendedor vendedor,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => _VendorPricesModal(vendedor: vendedor),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface(context),
        title: Text(
          'Eliminar vendedor',
          style: GoogleFonts.inter(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '¿Eliminar a ${vendedor.nombre}? Las ventas registradas se mantendrán.',
          style: GoogleFonts.inter(color: AppColors.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(proveedorNotificadorVendedor.notifier)
                  .eliminar(vendedor.id);
            },
            child: const Text(
              'Eliminar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerMetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SellerMetricPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorPricesModal extends ConsumerStatefulWidget {
  final Vendedor vendedor;

  const _VendorPricesModal({required this.vendedor});

  @override
  ConsumerState<_VendorPricesModal> createState() => _VendorPricesModalState();
}

class _VendorPricesModalState extends ConsumerState<_VendorPricesModal> {
  final Map<String, TextEditingController> _controllers = {};
  bool _guardando = false;

  Future<void> _guardar() async {
    final valores = <String, double>{};
    for (final entry in _controllers.entries) {
      final valor = double.tryParse(
        entry.value.text.trim().replaceAll(',', '.'),
      );
      if (valor == null || !valor.isFinite || valor < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ingresa precios validos, mayores o iguales a cero.'),
          ),
        );
        return;
      }
      valores[entry.key] = valor;
    }
    setState(() => _guardando = true);
    try {
      final servicio = ref.read(proveedorServicioPrecio);
      for (final entry in valores.entries) {
        await servicio.guardarPrecio(
          productoId: entry.key,
          vendedorId: widget.vendedor.esDistribuidora
              ? null
              : widget.vendedor.id,
          precio: entry.value,
        );
      }
      await ref.read(proveedorNotificadorPrecios.notifier).cargar();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron guardar los precios: $e')),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productosAsync = ref.watch(proveedorNotificadorProducto);
    final preciosAsync = ref.watch(proveedorNotificadorPrecios);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: AppColors.surface(context),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Precios personalizados',
            style: GoogleFonts.inter(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            'Vendedor: ${widget.vendedor.nombre}',
            style: GoogleFonts.inter(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        child: productosAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error al cargar productos: $e'),
          data: (productos) {
            if (preciosAsync.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (preciosAsync.hasError) {
              return const Text('No se pudieron cargar los precios.');
            }
            final productosVendedor = productos.toList();

            if (productosVendedor.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay productos en inventario.'),
              );
            }

            final preciosMap = <String, double>{};
            if (preciosAsync.hasValue) {
              for (final p in preciosAsync.value!) {
                if (widget.vendedor.esDistribuidora
                    ? p.esDistribuidora
                    : p.vendedorId == widget.vendedor.id) {
                  preciosMap[p.productoId] = p.precio;
                }
              }
            }

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: productosVendedor.map((prod) {
                  final ctrl = _controllers.putIfAbsent(
                    prod.id,
                    () => TextEditingController(
                      text: preciosMap.containsKey(prod.id)
                          ? preciosMap[prod.id]!.toStringAsFixed(2)
                          : PrecioProducto.resolver(
                              precios: preciosAsync.value!,
                              productoId: prod.id,
                              precioBase: prod.precio,
                              vendedorId: widget.vendedor.esDistribuidora
                                  ? null
                                  : widget.vendedor.id,
                            ).toStringAsFixed(2),
                    ),
                  );

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prod.nombre,
                                style: GoogleFonts.inter(
                                  color: AppColors.textPrimary(context),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Por ${prod.unidad}',
                                style: GoogleFonts.inter(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 14,
                            ),
                            decoration: const InputDecoration(
                              prefixText: '\$ ',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _guardando ||
                  preciosAsync.isLoading ||
                  preciosAsync.hasError ||
                  !productosAsync.hasValue
              ? null
              : _guardar,
          child: const Text('Guardar precios'),
        ),
      ],
    );
  }
}
