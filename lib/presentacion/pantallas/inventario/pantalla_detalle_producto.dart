import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/constantes/textos_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../nucleo/utilidades/utilidades_fecha.dart';
import '../../../datos/modelos/producto.dart';
import '../../../datos/modelos/precio_producto.dart';
import '../../proveedores/proveedor_producto.dart';
import '../../proveedores/proveedor_precio.dart';
import '../../proveedores/proveedor_vendedor.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productoId;

  const ProductDetailScreen({super.key, required this.productoId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  static const _limiteMovimientos = 10;

  Producto? _product;
  List<Map<String, dynamic>> _movements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(proveedorServicioProducto);

    try {
      final productoFuture = repository.obtenerPorId(widget.productoId);
      final movementsFuture = repository.obtenerMovimientos(
        widget.productoId,
        limite: _limiteMovimientos,
      );
      final producto = await productoFuture;
      final movements = await movementsFuture;

      if (!mounted) return;
      setState(() {
        _product = producto;
        _movements = movements;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text(
          'Eliminar producto',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          AppStrings.deleteConfirm,
          style: GoogleFonts.inter(color: AppColors.textSecondaryLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              AppStrings.cancel,
              style: const TextStyle(color: AppColors.textSecondaryLight),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppStrings.delete,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await ref
        .read(proveedorNotificadorProducto.notifier)
        .eliminarProducto(widget.productoId);

    if (mounted) context.pop();
  }

  // ignore: unused_element
  void _showMovementDialog() {
    final quantityCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String type = 'entrada';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          scrollable: true,
          backgroundColor: AppColors.surfaceLight,
          title: Text(
            'Registrar movimiento',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 320;
                  final optionWidth = compact
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 8) / 2;

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: optionWidth,
                        child: _TypeButton(
                          label: 'Entrada',
                          icon: Icons.add_circle_outline_rounded,
                          color: AppColors.success,
                          selected: type == 'entrada',
                          onTap: () => setDialogState(() => type = 'entrada'),
                        ),
                      ),
                      SizedBox(
                        width: optionWidth,
                        child: _TypeButton(
                          label: 'Salida',
                          icon: Icons.remove_circle_outline_rounded,
                          color: AppColors.error,
                          selected: type == 'salida',
                          onTap: () => setDialogState(() => type = 'salida'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimaryLight),
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(color: AppColors.textPrimaryLight),
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                AppStrings.cancel,
                style: const TextStyle(color: AppColors.textSecondaryLight),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: Size.zero),
              onPressed: () async {
                final quantity = int.tryParse(quantityCtrl.text);
                if (quantity == null || quantity <= 0) return;

                Navigator.pop(ctx);
                try {
                  await ref
                      .read(proveedorNotificadorProducto.notifier)
                      .registrarMovimiento(
                        productoId: widget.productoId,
                        tipo: type,
                        cantidad: quantity,
                        motivo: reasonCtrl.text.trim().isEmpty
                            ? null
                            : reasonCtrl.text.trim(),
                      );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Movimiento registrado con éxito'),
                      ),
                    );
                    _load();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMovementSheet() {
    final quantityCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String type = 'entrada';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 22,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Registrar movimiento',
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimaryLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 320;
                      final optionWidth = compact
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 8) / 2;

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: optionWidth,
                            child: _TypeButton(
                              label: 'Entrada',
                              icon: Icons.add_circle_outline_rounded,
                              color: AppColors.success,
                              selected: type == 'entrada',
                              onTap: () =>
                                  setDialogState(() => type = 'entrada'),
                            ),
                          ),
                          SizedBox(
                            width: optionWidth,
                            child: _TypeButton(
                              label: 'Salida',
                              icon: Icons.remove_circle_outline_rounded,
                              color: AppColors.error,
                              selected: type == 'salida',
                              onTap: () =>
                                  setDialogState(() => type = 'salida'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: AppColors.textPrimaryLight),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      prefixIcon: Icon(Icons.numbers_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: AppColors.textPrimaryLight),
                    decoration: const InputDecoration(
                      labelText: 'Motivo (opcional)',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            AppStrings.cancel,
                            style: const TextStyle(
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                          ),
                          onPressed: () async {
                            final quantity = int.tryParse(quantityCtrl.text);
                            if (quantity == null || quantity <= 0) return;

                            Navigator.pop(ctx);
                            try {
                              await ref
                                  .read(proveedorNotificadorProducto.notifier)
                                  .registrarMovimiento(
                                    productoId: widget.productoId,
                                    tipo: type,
                                    cantidad: quantity,
                                    motivo: reasonCtrl.text.trim().isEmpty
                                        ? null
                                        : reasonCtrl.text.trim(),
                                  );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Movimiento registrado con éxito',
                                    ),
                                  ),
                                );
                                _load();
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight),
        ),
      );
    }

    if (_product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Producto no encontrado')),
      );
    }

    final producto = _product!;
    final stockColor = producto.esCritico
        ? AppColors.stockCritical
        : producto.esBajo
        ? AppColors.stockWarning
        : AppColors.stockOk;

    return Scaffold(
      appBar: AppBar(
        title: Text(producto.nombre),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await context.push(
                '/inventory/edit/${producto.id}',
                extra: producto,
              );
              _load();
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
            onPressed: _delete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showMovementSheet,
        icon: const Icon(Icons.swap_vert_rounded),
        label: Text(
          'Movimiento',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (producto.urlImagen != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CachedNetworkImage(
                    imageUrl: producto.urlImagen!,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      height: 220,
                      color: AppColors.surfaceVariantLight,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryLight,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      height: 140,
                      color: AppColors.surfaceVariantLight,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textHintLight,
                        size: 40,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _StockOverviewCard(producto: producto, stockColor: stockColor),
              const SizedBox(height: 20),
              _ProductPricesCard(producto: producto),
              const SizedBox(height: 20),
              _DetailsCard(producto: producto),
              const SizedBox(height: 24),
              Text(
                'Ultimos movimientos',
                style: GoogleFonts.inter(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              if (_movements.isEmpty)
                Text(
                  'Sin movimientos registrados',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondaryLight,
                    fontSize: 13,
                  ),
                )
              else
                ..._movements.map(_MovementTile.new),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockOverviewCard extends StatelessWidget {
  final Producto producto;
  final Color stockColor;

  const _StockOverviewCard({required this.producto, required this.stockColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            stockColor.withAlpha((0.16 * 255).toInt()),
            AppColors.cardLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stockColor.withAlpha((0.28 * 255).toInt())),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 330;

          return Wrap(
            spacing: 16,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_rounded,
                color: stockColor,
                size: compact ? 34 : 40,
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: compact ? constraints.maxWidth : 0,
                  maxWidth: compact
                      ? constraints.maxWidth
                      : constraints.maxWidth - 56,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${producto.stock} ${producto.unidad}s',
                      style: GoogleFonts.inter(
                        color: stockColor,
                        fontSize: compact ? 24 : 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Mínimo: ${producto.stockMinimo}  •  ${CurrencyUtils.format(producto.precio)}',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondaryLight,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductPricesCard extends ConsumerWidget {
  final Producto producto;

  const _ProductPricesCard({required this.producto});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preciosAsync = ref.watch(proveedorNotificadorPrecios);
    final vendedoresAsync = ref.watch(proveedorNotificadorVendedor);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Precios configurados',
                style: GoogleFonts.inter(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Icon(
                Icons.sell_outlined,
                size: 18,
                color: AppColors.primaryLight,
              ),
            ],
          ),
          const SizedBox(height: 12),
          preciosAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error al cargar precios: $e'),
            data: (precios) {
              final vendedores = vendedoresAsync.asData?.value ?? [];
              final preciosDelProducto = precios
                  .where((p) => p.productoId == producto.id)
                  .toList();

              final precioDistribuidora = preciosDelProducto.firstWhere(
                (p) => p.esDistribuidora,
                orElse: () => PrecioProducto(
                  id: '',
                  productoId: producto.id,
                  precio: producto.precio,
                ),
              );

              return Column(
                children: [
                  _PriceRow(
                    label: 'Distribuidora (Central)',
                    precio: precioDistribuidora.precio,
                    esBase: true,
                  ),
                  ...vendedores.map((vendedor) {
                    final precioVendedor = preciosDelProducto.firstWhere(
                      (p) => p.vendedorId == vendedor.id,
                      orElse: () => PrecioProducto(
                        id: '',
                        productoId: producto.id,
                        vendedorId: vendedor.id,
                        precio: precioDistribuidora.precio,
                      ),
                    );

                    return _PriceRow(
                      label: vendedor.nombre,
                      precio: precioVendedor.precio,
                      esBase: false,
                    );
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final String label;
  final double precio;
  final bool esBase;

  const _PriceRow({
    required this.label,
    required this.precio,
    required this.esBase,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: esBase
                  ? AppColors.textPrimaryLight
                  : AppColors.textSecondaryLight,
              fontSize: 13,
              fontWeight: esBase ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            CurrencyUtils.format(precio),
            style: GoogleFonts.inter(
              color: AppColors.success,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final Producto producto;

  const _DetailsCard({required this.producto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          _InfoRow('Descripción', producto.descripcion ?? 'Sin descripción'),
          _InfoRow('Unidad', producto.unidad),
          _InfoRow('Precio', CurrencyUtils.format(producto.precio)),
          _InfoRow('Creado', AppDateUtils.formatDate(producto.creadoEn)),
          _InfoRow(
            'Actualizado',
            AppDateUtils.formatDate(producto.actualizadoEn),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: AppColors.textHintLight,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimaryLight,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: AppColors.textHintLight,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimaryLight,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  final Map<String, dynamic> movement;

  const _MovementTile(this.movement);

  @override
  Widget build(BuildContext context) {
    final tipo = (movement['tipo'] ?? movement['type'] ?? 'salida') as String;
    final cantidad = (movement['cantidad'] ?? movement['quantity'] ?? 0) as int;
    final motivo = movement['motivo'] ?? movement['reason'];
    final fechaTexto = movement['creado_en'] ?? movement['created_at'];
    final fecha = DateTime.tryParse(fechaTexto as String? ?? '');
    final isEntrada = tipo == 'entrada';
    final color = isEntrada ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isEntrada
                ? Icons.add_circle_outline_rounded
                : Icons.remove_circle_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEntrada ? 'Entrada' : 'Salida',
                  style: GoogleFonts.inter(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (motivo is String && motivo.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    motivo,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondaryLight,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isEntrada ? '+' : '-'}$cantidad',
                style: GoogleFonts.inter(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (fecha != null)
                Text(
                  AppDateUtils.formatRelative(fecha),
                  style: GoogleFonts.inter(
                    color: AppColors.textHintLight,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? color.withAlpha((0.16 * 255).toInt())
              : AppColors.surfaceVariantLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? color : AppColors.textHintLight,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: selected ? color : AppColors.textHintLight,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
