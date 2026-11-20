import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/constantes/textos_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../datos/modelos/producto.dart';
import '../../../presentacion/proveedores/proveedor_producto.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(proveedorNotificadorProducto);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.products),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => context.push('/inventory/add'),
            tooltip: AppStrings.addProduct,
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight),
        ),
        error: (e, _) => _ErrorView(
          msg: e.toString(),
          onRetry: () =>
              ref.read(proveedorNotificadorProducto.notifier).cargar(),
        ),
        data: (products) {
          final filtered = products
              .where((p) => p.nombre.toLowerCase().contains(_search))
              .toList();

          return RefreshIndicator(
            color: AppColors.primaryLight,
            backgroundColor: AppColors.surfaceLight,
            onRefresh: () =>
                ref.read(proveedorNotificadorProducto.notifier).cargar(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      style: const TextStyle(color: AppColors.textPrimaryLight),
                      decoration: InputDecoration(
                        hintText: AppStrings.search,
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => setState(() => _search = ''),
                              )
                            : null,
                      ),
                      onChanged: _actualizarBusqueda,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 100,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 56,
                              color: AppColors.textHintLight,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _search.isEmpty
                                  ? 'Sin productos aún'
                                  : 'Sin resultados para "$_search"',
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondaryLight,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    sliver: SliverList.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) =>
                          _ProductCard(producto: filtered[index]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/inventory/add'),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          AppStrings.addProduct,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _actualizarBusqueda(String value) {
    final normalized = value.toLowerCase();
    if (normalized == _search) return;
    setState(() => _search = normalized);
  }
}

class _ProductCard extends ConsumerWidget {
  final Producto producto;

  const _ProductCard({required this.producto});

  Color get _stockColor {
    if (producto.esCritico) return AppColors.stockCritical;
    if (producto.esBajo) return AppColors.stockWarning;
    return AppColors.stockOk;
  }

  Widget _stockIconFallback() => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: _stockColor.withAlpha((0.12 * 255).toInt()),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.inventory_2_rounded, color: _stockColor, size: 24),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/inventory/detail/${producto.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 360;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: producto.urlImagen != null
                        ? CachedNetworkImage(
                            imageUrl: producto.urlImagen!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              width: 48,
                              height: 48,
                              color: AppColors.surfaceVariantLight,
                              child: const Icon(
                                Icons.inventory_2_rounded,
                                color: AppColors.textHintLight,
                                size: 22,
                              ),
                            ),
                            errorWidget: (_, _, _) => _stockIconFallback(),
                          )
                        : _stockIconFallback(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          producto.nombre,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimaryLight,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${producto.unidad}  •  ${CurrencyUtils.format(producto.precio)}',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondaryLight,
                            fontSize: 12,
                          ),
                        ),
                        if (compact) ...[
                          const SizedBox(height: 10),
                          _StockBadge(
                            stock: producto.stock,
                            minStock: producto.stockMinimo,
                            stockColor: _stockColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    _StockBadge(
                      stock: producto.stock,
                      minStock: producto.stockMinimo,
                      stockColor: _stockColor,
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHintLight,
                    size: 20,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  final int stock;
  final int minStock;
  final Color stockColor;

  const _StockBadge({
    required this.stock,
    required this.minStock,
    required this.stockColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: stockColor.withAlpha((0.15 * 255).toInt()),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$stock',
            style: GoogleFonts.inter(
              color: stockColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'mín. $minStock',
          style: GoogleFonts.inter(
            color: AppColors.textHintLight,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;

  const _ErrorView({required this.msg, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Error al cargar',
              style: GoogleFonts.inter(
                color: AppColors.textPrimaryLight,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              msg,
              style: GoogleFonts.inter(
                color: AppColors.textSecondaryLight,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(AppStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}
