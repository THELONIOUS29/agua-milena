import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/constantes/textos_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../datos/modelos/producto.dart';
import '../../../datos/modelos/precio_producto.dart';
import '../../../datos/modelos/item_venta.dart';
import '../../../datos/modelos/vendedor.dart';
import '../../../presentacion/proveedores/proveedor_bidones.dart';
import '../../../presentacion/proveedores/proveedor_producto.dart';
import '../../../presentacion/proveedores/proveedor_precio.dart';
import '../../../presentacion/proveedores/proveedor_ruta.dart';
import '../../../presentacion/proveedores/proveedor_venta.dart';
import '../../../presentacion/proveedores/proveedor_vendedor.dart';

class NewSaleScreen extends ConsumerStatefulWidget {
  final String? preselectedSellerId;

  const NewSaleScreen({super.key, this.preselectedSellerId});

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _notesCtrl = TextEditingController();
  final _vaciosRetornadosCtrl = TextEditingController();
  final _llenosEnCarroCtrl = TextEditingController();
  bool _saving = false;
  String _search = '';
  double _saldoAFavorDisponible = 0;
  bool _cargandoSaldoAFavor = false;
  bool _aplicarSaldoAFavor = false;

  // null/distribuidora => cat?logo distribuidora
  Vendedor? _selectedSeller;
  bool _preselectionApplied = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(proveedorNotificadorPrecios.notifier).cargar();
    });
  }

  Vendedor? _effectiveSelectedSeller(List<Vendedor>? sellers) {
    final selected = _selectedSeller;
    if (selected == null || selected.esDistribuidora) return selected;
    if (sellers == null) return selected;
    for (final v in sellers) {
      if (v.id == selected.id) return v;
    }
    return selected;
  }

  void _seleccionarVendedor(Vendedor? vendedor) {
    final prevSellerSale =
        _selectedSeller != null && _selectedSeller!.esDistribuidora == false;
    final nextSellerSale =
        vendedor != null && vendedor.esDistribuidora == false;
    if (prevSellerSale != nextSellerSale ||
        _selectedSeller?.id != vendedor?.id) {
      ref.read(proveedorCarrito.notifier).limpiar();
    }
    _selectedSeller = vendedor;
    _aplicarSaldoAFavor = false;
    _vaciosRetornadosCtrl.clear();
    if (nextSellerSale) {
      _llenosEnCarroCtrl.text = '${vendedor.bidonesLlenosActuales}';
      _saldoAFavorDisponible = 0;
      _cargandoSaldoAFavor = true;
      Future.microtask(() => _cargarSaldoAFavor(vendedor.id));
    } else {
      _llenosEnCarroCtrl.clear();
      _vaciosRetornadosCtrl.clear();
      _saldoAFavorDisponible = 0;
      _cargandoSaldoAFavor = false;
    }
  }

  Future<void> _cargarSaldoAFavor(String vendedorId) async {
    try {
      final saldo = await ref
          .read(proveedorServicioVenta)
          .obtenerSaldoAFavor(vendedorId);
      if (!mounted || _selectedSeller?.id != vendedorId) return;
      setState(() {
        _saldoAFavorDisponible = saldo;
        _cargandoSaldoAFavor = false;
      });
    } catch (_) {
      if (!mounted || _selectedSeller?.id != vendedorId) return;
      setState(() {
        _saldoAFavorDisponible = 0;
        _cargandoSaldoAFavor = false;
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _vaciosRetornadosCtrl.dispose();
    _llenosEnCarroCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final preciosAsync = ref.read(proveedorNotificadorPrecios);
    if (!preciosAsync.hasValue || preciosAsync.isLoading) return;
    final cart = ref.read(proveedorCarrito);
    final tieneProductos = cart.any((i) => i.cantidad > 0);
    final tieneDevoluciones = cart.any((i) => i.devolucion > 0);
    if (!tieneProductos && !tieneDevoluciones) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un producto o devolución'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final sellers = ref.read(proveedorVendedoresActivos).asData?.value;
    final selectedSeller = _effectiveSelectedSeller(sellers);
    if (tieneDevoluciones && selectedSeller?.permiteDevoluciones != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este vendedor no tiene habilitadas las devoluciones.'),
        ),
      );
      return;
    }
    final bidonesVaciosRecibidos =
        int.tryParse(_vaciosRetornadosCtrl.text.trim()) ?? 0;
    final bidonesLlenosEnCarro =
        int.tryParse(_llenosEnCarroCtrl.text.trim()) ?? 0;

    setState(() => _saving = true);
    try {
      await ref
          .read(proveedorNotificadorVenta.notifier)
          .crearVenta(
            items: cart,
            notas: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text,
            vendedorId: selectedSeller?.esDistribuidora == true
                ? null
                : selectedSeller?.id,
            bidonesLlenosEnCarro: bidonesLlenosEnCarro,
            bidonesVaciosRecibidos: bidonesVaciosRecibidos,
            aplicarSaldoAFavor: _aplicarSaldoAFavor,
          );
      ref.read(proveedorCarrito.notifier).limpiar();
      _vaciosRetornadosCtrl.clear();
      _llenosEnCarroCtrl.clear();
      await ref.read(proveedorNotificadorProducto.notifier).cargar();
      await ref.read(proveedorNotificadorVendedor.notifier).cargar();
      await ref.read(proveedorNotificadorRuta.notifier).cargar();
      ref.invalidate(proveedorVendedoresActivos);
      ref.invalidate(proveedorTotalBidonesEmpresa);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Venta registrada ✓'),
            backgroundColor: AppColors.success,
          ),
        );
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(proveedorNotificadorProducto);
    final preciosAsync = ref.watch(proveedorNotificadorPrecios);
    final cart = ref.watch(proveedorCarrito);
    final total = ref.watch(proveedorTotalCarrito);
    final sellersAsync = ref.watch(proveedorVendedoresActivos);
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    if (!_preselectionApplied &&
        _selectedSeller == null &&
        widget.preselectedSellerId != null) {
      final sellers = sellersAsync.asData?.value;
      if (sellers != null) {
        _preselectionApplied = true;
        final match = sellers.where((s) => s.id == widget.preselectedSellerId);
        if (match.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _seleccionarVendedor(match.first));
          });
        }
      }
    }

    final selectedSeller = _effectiveSelectedSeller(sellersAsync.asData?.value);
    final isSellerSale =
        selectedSeller != null && selectedSeller.esDistribuidora == false;
    final totalDevoluciones = ref.watch(proveedorTotalDevoluciones);
    final bidonesCargados = cart
        .where((item) => item.esBidon)
        .fold<int>(0, (sum, item) => sum + item.cantidad);
    final totalNeto = (total - totalDevoluciones).clamp(0.0, double.infinity);
    final creditoAplicado = isSellerSale && _aplicarSaldoAFavor
        ? (totalNeto < _saldoAFavorDisponible
              ? totalNeto
              : _saldoAFavorDisponible)
        : 0.0;
    final totalFinal = (totalNeto - creditoAplicado)
        .clamp(0, double.infinity)
        .toDouble();
    final productWidgets = productsAsync.when<List<Widget>>(
      loading: () => const [
        SizedBox(
          height: 220,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primaryLight),
          ),
        ),
      ],
      error: (e, _) => [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Center(child: Text('$e')),
        ),
      ],
      data: (products) {
        if (preciosAsync.isLoading) {
          return const [Center(child: CircularProgressIndicator())];
        }
        if (preciosAsync.hasError) {
          return [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No se pudieron cargar los precios. Revisa la conexion y la migracion de la base de datos.',
              ),
            ),
          ];
        }
        final filtered = products
            .where(
              (p) => p.nombre.toLowerCase().contains(_search) && p.stock > 0,
            )
            .toList();

        if (filtered.isEmpty) {
          return [
            SizedBox(
              height: 220,
              child: Center(
                child: Text(
                  _search.isEmpty
                      ? 'Sin productos con stock disponible'
                      : 'Sin resultados para "$_search"',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondaryLight,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ];
        }

        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Productos',
              style: GoogleFonts.inter(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          ...filtered.map((producto) {
            final activePrice = PrecioProducto.resolver(
              precios: preciosAsync.value!,
              productoId: producto.id,
              precioBase: producto.precio,
              vendedorId: isSellerSale ? selectedSeller.id : null,
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ProductSelector(
                producto: producto,
                precioCustom: activePrice,
                cartQty: cart
                    .where((c) => c.productoId == producto.id)
                    .fold(0, (s, c) => s + c.cantidad),
              ),
            );
          }),
        ];
      },
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text(AppStrings.newSale),
        actions: [
          if (cart.isNotEmpty)
            TextButton(
              onPressed: _saving ? null : _confirm,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      AppStrings.confirm,
                      style: GoogleFonts.inter(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          children: [
            _SellerPicker(
              sellersAsync: sellersAsync,
              selected: selectedSeller,
              onChanged: (s) {
                setState(() => _seleccionarVendedor(s));
              },
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isSellerSale
                      ? 'Catálogo aplicado: Vendedores'
                      : 'Catálogo aplicado: Distribuidora',
                  style: GoogleFonts.inter(
                    color: AppColors.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            if (isSellerSale)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isKeyboardOpen) ...[
                      _BidonesVentaSection(
                        vendedor: selectedSeller,
                        bidonesCargados: bidonesCargados,
                        bidonesLlenosEnCarro:
                            int.tryParse(_llenosEnCarroCtrl.text.trim()) ?? 0,
                        vaciosRecibidos:
                            int.tryParse(_vaciosRetornadosCtrl.text.trim()) ??
                            0,
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _vaciosRetornadosCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      onEditingComplete: () {
                        FocusScope.of(context).unfocus();
                        setState(() {});
                      },
                      style: const TextStyle(color: AppColors.textPrimaryLight),
                      scrollPadding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 96,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Vacíos recibidos',
                        hintText: '0',
                        prefixIcon: const Icon(
                          Icons.water_drop_rounded,
                          size: 18,
                        ),
                        suffixIcon: _vaciosRetornadosCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _vaciosRetornadosCtrl.clear();
                                  setState(() {});
                                },
                              ),
                        filled: true,
                        fillColor: AppColors.cardLight,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.primary.withAlpha(
                              (0.3 * 255).toInt(),
                            ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.primary.withAlpha(
                              (0.3 * 255).toInt(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _llenosEnCarroCtrl,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      onEditingComplete: () {
                        FocusScope.of(context).unfocus();
                        setState(() {});
                      },
                      style: const TextStyle(color: AppColors.textPrimaryLight),
                      scrollPadding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 120,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Llenos en el carro',
                        hintText: '0',
                        prefixIcon: const Icon(
                          Icons.inventory_2_rounded,
                          size: 18,
                        ),
                        suffixIcon: _llenosEnCarroCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _llenosEnCarroCtrl.clear();
                                  setState(() {});
                                },
                              ),
                        filled: true,
                        fillColor: AppColors.cardLight,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.primary.withAlpha(
                              (0.3 * 255).toInt(),
                            ),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppColors.primary.withAlpha(
                              (0.3 * 255).toInt(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Devoluciones segun el permiso configurado para el vendedor.
            if (isSellerSale && selectedSeller.permiteDevoluciones)
              _DevolucionesSection(selectedSeller: selectedSeller),

            if (isSellerSale && _saldoAFavorDisponible > 0.009)
              CheckboxListTile(
                title: const Text('Aplicar saldo a favor'),
                subtitle: Text(
                  'Disponible: ${CurrencyUtils.format(_saldoAFavorDisponible)}',
                ),
                value: _aplicarSaldoAFavor,
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _aplicarSaldoAFavor = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _notesCtrl,
                maxLines: 2,
                style: const TextStyle(color: AppColors.textPrimaryLight),
                decoration: InputDecoration(
                  labelText: 'Notas de la venta (visibles al cobrar la ruta)',
                  hintText:
                      'Ej: Cliente pagó en efectivo / dejar nota sobre pago...',
                  prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                  filled: true,
                  fillColor: AppColors.cardLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.primary.withAlpha((0.3 * 255).toInt()),
                    ),
                  ),
                ),
              ),
            ),

            if ((cart.isNotEmpty || totalDevoluciones > 0) && !isKeyboardOpen)
              _CartSection(
                cart: cart,
                total: total,
                totalDevoluciones: totalDevoluciones,
                creditoAplicado: creditoAplicado,
                cargandoSaldoAFavor: _cargandoSaldoAFavor,
              ),

            if (!isKeyboardOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
            const SizedBox(height: 4),
            ...productWidgets,
          ],
        ),
      ),
      bottomNavigationBar:
          (cart.isEmpty && totalDevoluciones <= 0) || isKeyboardOpen
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ElevatedButton(
                  onPressed: _saving ? null : _confirm,
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          '${AppStrings.confirm}  -  ${CurrencyUtils.format(totalFinal)}',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ),
    );
  }
}

class _SellerPicker extends StatelessWidget {
  final AsyncValue<List<Vendedor>> sellersAsync;
  final Vendedor? selected;
  final ValueChanged<Vendedor?> onChanged;

  const _SellerPicker({
    required this.sellersAsync,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return sellersAsync.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(
          child: LinearProgressIndicator(color: AppColors.primaryLight),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (sellers) {
        final distribuidora = Vendedor.distribuidora;
        final allOptions = [distribuidora, ...sellers];
        final current = selected ?? distribuidora;

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.cardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withAlpha((0.3 * 255).toInt()),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<Vendedor>(
              isExpanded: true,
              dropdownColor: AppColors.surfaceLight,
              icon: const Icon(
                Icons.expand_more_rounded,
                color: AppColors.textHintLight,
              ),
              value: allOptions.firstWhere(
                (s) => s.id == current.id,
                orElse: () => distribuidora,
              ),
              items: allOptions.map((s) {
                return DropdownMenuItem<Vendedor>(
                  value: s,
                  child: Row(
                    children: [
                      Icon(
                        s.esDistribuidora
                            ? Icons.store_rounded
                            : Icons.person_rounded,
                        color: AppColors.primaryLight,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        s.nombre,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimaryLight,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        );
      },
    );
  }
}

class _CartSection extends ConsumerWidget {
  final List<ItemCarrito> cart;
  final double total;
  final double totalDevoluciones;
  final double creditoAplicado;
  final bool cargandoSaldoAFavor;

  const _CartSection({
    required this.cart,
    required this.total,
    required this.totalDevoluciones,
    required this.creditoAplicado,
    required this.cargandoSaldoAFavor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsVenta = cart.where((i) => i.cantidad > 0).toList();
    final itemsDevolucion = cart.where((i) => i.devolucion > 0).toList();
    final totalNeto = (total - totalDevoluciones).clamp(0.0, double.infinity);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withAlpha((0.3 * 255).toInt()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (itemsVenta.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Productos (${itemsVenta.length})',
                  style: GoogleFonts.inter(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  CurrencyUtils.format(total),
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...itemsVenta.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.nombreProducto,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimaryLight,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      'x${item.cantidad}  ',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      CurrencyUtils.format(item.subtotal),
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => ref
                          .read(proveedorCarrito.notifier)
                          .eliminarProducto(item.productoId),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (itemsDevolucion.isNotEmpty) ...[
            if (itemsVenta.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Devoluciones (${itemsDevolucion.length})',
                  style: GoogleFonts.inter(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '- ${CurrencyUtils.format(totalDevoluciones)}',
                  style: GoogleFonts.inter(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...itemsDevolucion.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.undo_rounded,
                      size: 13,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.nombreProducto,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimaryLight,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      'x${item.devolucion}  - ${CurrencyUtils.format(item.creditoDevolucion)}',
                      style: GoogleFonts.inter(
                        color: AppColors.warning,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          // Totales
          if (totalDevoluciones > 0 || creditoAplicado > 0.009) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            if (totalDevoluciones > 0) ...[
              _TotalLine(
                label: 'Subtotal productos',
                value: CurrencyUtils.format(total),
                color: AppColors.textSecondaryLight,
              ),
              const SizedBox(height: 4),
              _TotalLine(
                label: 'Devoluciones',
                value: '- ${CurrencyUtils.format(totalDevoluciones)}',
                color: AppColors.warning,
              ),
              const SizedBox(height: 4),
            ],
            if (cargandoSaldoAFavor)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primaryLight,
              )
            else if (creditoAplicado > 0.009) ...[
              _TotalLine(
                label: 'Saldo a favor aplicado',
                value: '- ${CurrencyUtils.format(creditoAplicado)}',
                color: AppColors.success,
              ),
              const SizedBox(height: 6),
            ],
            _TotalLine(
              label: 'Total a cobrar',
              value: CurrencyUtils.format(
                (totalNeto - creditoAplicado).clamp(0, double.infinity),
              ),
              color: AppColors.primaryLight,
              destacado: true,
            ),
          ] else if (cargandoSaldoAFavor) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primaryLight,
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool destacado;

  const _TotalLine({
    required this.label,
    required this.value,
    required this.color,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.textSecondaryLight,
            fontSize: destacado ? 13 : 12,
            fontWeight: destacado ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: color,
            fontSize: destacado ? 14 : 12,
            fontWeight: destacado ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DevolucionesSection extends ConsumerStatefulWidget {
  final Vendedor selectedSeller;

  const _DevolucionesSection({required this.selectedSeller});

  @override
  ConsumerState<_DevolucionesSection> createState() =>
      _DevolucionesSectionState();
}

class _DevolucionesSectionState extends ConsumerState<_DevolucionesSection> {
  bool _expanded = false;
  List<_ProductoDevolucion>? _productosAnteriores;
  bool _cargando = false;
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _cargarProductosDevolucion();
  }

  @override
  void didUpdateWidget(covariant _DevolucionesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedSeller.id != widget.selectedSeller.id) {
      _cargarProductosDevolucion();
    }
  }

  Future<void> _cargarProductosDevolucion() async {
    final vendedorId = widget.selectedSeller.id;
    for (final ctrl in _controllers.values) {
      ctrl.clear();
    }
    setState(() {
      _cargando = true;
      _productosAnteriores = null;
    });
    try {
      final productos = await ref
          .read(proveedorServicioProducto)
          .obtenerTodos();
      final productosMap = {
        for (final producto in productos)
          producto.id: _ProductoDevolucion(
            productoId: producto.id,
            nombreProducto: producto.nombre,
            precioUnitario: producto.precio,
          ),
      };

      if (!mounted || widget.selectedSeller.id != vendedorId) return;
      setState(() {
        _productosAnteriores = productosMap.values.toList();
        _cargando = false;
      });
    } catch (_) {
      if (!mounted || widget.selectedSeller.id != vendedorId) return;
      setState(() {
        _productosAnteriores = [];
        _cargando = false;
      });
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final precios = ref.watch(proveedorNotificadorPrecios);
    final inventario = ref.watch(proveedorNotificadorProducto);
    if (_cargando || precios.isLoading || inventario.isLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: LinearProgressIndicator(
          minHeight: 2,
          color: AppColors.primaryLight,
        ),
      );
    }

    final productos = _productosAnteriores;
    if (productos == null || productos.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF9800).withAlpha((0.4 * 255).toInt()),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.undo_rounded, size: 18, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Devoluciones de productos',
                      style: GoogleFonts.inter(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.warning,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Text(
                'Indica cuántos productos devuelve el vendedor sin vender:',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondaryLight,
                  fontSize: 11,
                ),
              ),
            ),
            ...productos.map((prod) {
              final actuales = inventario.value
                  ?.where((p) => p.id == prod.productoId)
                  .toList();
              final precioDevolucion = PrecioProducto.resolver(
                precios: precios.value ?? [],
                productoId: prod.productoId,
                precioBase: actuales?.isNotEmpty == true
                    ? actuales!.first.precio
                    : prod.precioUnitario,
                vendedorId: widget.selectedSeller.id,
              );
              final ctrl = _controllers.putIfAbsent(
                prod.productoId,
                () => TextEditingController(),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        prod.nombreProducto,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimaryLight,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      height: 34,
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                        decoration: InputDecoration(
                          hintText: '0',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(
                            0xFFFF9800,
                          ).withAlpha((0.08 * 255).toInt()),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.warning.withAlpha(
                                (0.3 * 255).toInt(),
                              ),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: AppColors.warning.withAlpha(
                                (0.3 * 255).toInt(),
                              ),
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          final qty = int.tryParse(val.trim()) ?? 0;
                          ref
                              .read(proveedorCarrito.notifier)
                              .actualizarDevolucion(
                                prod.productoId,
                                qty,
                                nombreProducto: prod.nombreProducto,
                                precioUnitario: precioDevolucion,
                                unidad: '',
                              );
                        },
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ProductoDevolucion {
  final String productoId;
  final String nombreProducto;
  final double precioUnitario;

  const _ProductoDevolucion({
    required this.productoId,
    required this.nombreProducto,
    required this.precioUnitario,
  });
}

class _BidonesVentaSection extends StatelessWidget {
  final Vendedor? vendedor;
  final int bidonesCargados;
  final int bidonesLlenosEnCarro;
  final int vaciosRecibidos;

  const _BidonesVentaSection({
    required this.vendedor,
    required this.bidonesCargados,
    required this.bidonesLlenosEnCarro,
    required this.vaciosRecibidos,
  });

  int get _llenosFinales => bidonesLlenosEnCarro + bidonesCargados;

  int get _prestadosOperacion {
    final value = bidonesCargados - vaciosRecibidos;
    return value > 0 ? value : 0;
  }

  int get _prestadosTrasVenta {
    final sellerBidones = vendedor?.bidonesPropios ?? 0;
    final excedente = _llenosFinales - sellerBidones;
    return excedente > 0 ? excedente : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withAlpha((0.25 * 255).toInt()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.water_rounded,
                color: AppColors.primaryLight,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (vendedor?.bidonesPropios ?? 0) > 0
                      ? 'Bidones (propios: ${vendedor?.bidonesPropios ?? 0})'
                      : 'Bidones',
                  style: GoogleFonts.inter(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if ((vendedor?.bidonesPrestados ?? 0) > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Prestados acumulados: ${vendedor?.bidonesPrestados ?? 0}',
              style: GoogleFonts.inter(
                color: AppColors.stockWarning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BidonInfoChip(
                label: 'Llenos en carro',
                value: '$bidonesLlenosEnCarro',
                color: AppColors.primaryLight,
              ),
              _BidonInfoChip(
                label: 'A subir',
                value: '$bidonesCargados',
                color: AppColors.warning,
              ),
              _BidonInfoChip(
                label: 'Vacíos recibidos',
                value: '$vaciosRecibidos',
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Llenos finales con vendedor:',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondaryLight,
                  fontSize: 11,
                ),
              ),
              Text(
                '$_llenosFinales',
                style: GoogleFonts.inter(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (_prestadosOperacion > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Extra prestado por la empresa: $_prestadosOperacion',
              style: GoogleFonts.inter(
                color: AppColors.stockWarning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_prestadosTrasVenta > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Prestados acumulados tras la venta: $_prestadosTrasVenta',
              style: GoogleFonts.inter(
                color: AppColors.stockWarning,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BidonInfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BidonInfoChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 106),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textSecondaryLight,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductSelector extends ConsumerWidget {
  final Producto producto;
  final double? precioCustom;
  final int cartQty;

  const _ProductSelector({
    required this.producto,
    this.precioCustom,
    required this.cartQty,
  });

  double get _effectivePrice => precioCustom ?? producto.precio;

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: '$cartQty');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text(
          'Cantidad de ${producto.nombre}',
          style: GoogleFonts.inter(
            color: AppColors.textPrimaryLight,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimaryLight),
          decoration: InputDecoration(
            hintText: '0 - ${producto.stock}',
            labelText: 'Cantidad',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              final qty = int.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, qty);
            },
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final nextQty = result.clamp(0, producto.stock);
    if (nextQty == 0) {
      ref.read(proveedorCarrito.notifier).eliminarProducto(producto.id);
      return;
    }
    if (cartQty == 0) {
      ref
          .read(proveedorCarrito.notifier)
          .agregarProducto(
            ItemCarrito(
              productoId: producto.id,
              nombreProducto: producto.nombre,
              precioUnitario: _effectivePrice,
              unidad: producto.unidad,
              cantidad: nextQty,
            ),
          );
      return;
    }
    ref
        .read(proveedorCarrito.notifier)
        .actualizarCantidad(producto.id, nextQty);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = cartQty > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.nombre,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimaryLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${CurrencyUtils.format(_effectivePrice)} / ${producto.unidad}  •  Stock: ${producto.stock}',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondaryLight,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (inCart) ...[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  color: AppColors.error,
                  size: 22,
                ),
                onPressed: () => ref
                    .read(proveedorCarrito.notifier)
                    .actualizarCantidad(producto.id, cartQty - 1),
              ),
              Container(
                width: 30,
                alignment: Alignment.center,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _editQuantity(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Text(
                      '$cartQty',
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Ingresar cantidad',
              icon: const Icon(
                Icons.keyboard_rounded,
                color: AppColors.textHintLight,
                size: 20,
              ),
              onPressed: () => _editQuantity(context, ref),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(
                Icons.add_circle_outline_rounded,
                color: inCart ? AppColors.success : AppColors.primaryLight,
                size: 22,
              ),
              onPressed: cartQty >= producto.stock
                  ? null
                  : () => ref
                        .read(proveedorCarrito.notifier)
                        .agregarProducto(
                          ItemCarrito(
                            productoId: producto.id,
                            nombreProducto: producto.nombre,
                            precioUnitario: _effectivePrice,
                            unidad: producto.unidad,
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
