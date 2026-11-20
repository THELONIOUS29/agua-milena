import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/constantes/textos_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../nucleo/utilidades/utilidades_fecha.dart';
import '../../../datos/modelos/venta.dart';
import '../../../datos/modelos/item_venta.dart';
import '../../../dominio/entidades/rol_usuario.dart';
import '../../../presentacion/proveedores/proveedor_autenticacion.dart';
import '../../../presentacion/proveedores/proveedor_venta.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  final String saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  Venta? _sale;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref
          .read(proveedorServicioVenta)
          .obtenerPorId(widget.saleId);
      if (!mounted) return;
      setState(() {
        _sale = s;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final rol = ref.read(proveedorNotificadorAuth).usuario?.rol;
    if (rol != RolUsuario.admin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Solo el administrador puede eliminar ventas.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text(
          'Eliminar venta',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '¿Deseas eliminar esta venta? El stock no se revertirá.',
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
    if (confirm == true && mounted) {
      await ref
          .read(proveedorNotificadorVenta.notifier)
          .eliminar(widget.saleId);
      if (mounted) context.pop();
    }
  }

  Future<void> _editNote(Venta venta) async {
    final noteCtrl = TextEditingController(text: venta.notas ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text(
          'Nota de la venta',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimaryLight),
          decoration: const InputDecoration(
            hintText: 'Escribe una nota para esta venta...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textHintLight),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final nota = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (saved == true && mounted) {
      try {
        await ref
            .read(proveedorNotificadorVenta.notifier)
            .actualizarNota(venta.id, nota.isEmpty ? null : nota);
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nota de venta actualizada ✓'),
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
      }
    }
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

    if (_sale == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Venta no encontrada')),
      );
    }

    final s = _sale!;
    final esAdministrador =
        ref.watch(proveedorNotificadorAuth).usuario?.rol == RolUsuario.admin;

    return Scaffold(
      appBar: AppBar(
        title: Text('Venta #${s.id.substring(0, 8).toUpperCase()}'),
        actions: [
          if (esAdministrador)
            IconButton(
              tooltip: 'Eliminar venta',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Resumen ------------------------------------------------------
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.success.withAlpha((0.15 * 255).toInt()),
                    AppColors.cardLight,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.success.withAlpha((0.3 * 255).toInt()),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha((0.15 * 255).toInt()),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_rounded,
                      color: AppColors.success,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CurrencyUtils.format(s.total),
                        style: GoogleFonts.inter(
                          color: AppColors.success,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${AppDateUtils.formatDate(s.fecha)}  •  ${AppDateUtils.formatTime(s.creadoEn)}',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondaryLight,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.primaryLight,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            s.mostrarVendedor,
                            style: GoogleFonts.inter(
                              color: AppColors.primaryLight,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- Notas de venta interactivas -----------------------------------
            Container(
              width: double.infinity,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.note_alt_rounded,
                            color: AppColors.primaryLight,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Nota de esta venta',
                            style: GoogleFonts.inter(
                              color: AppColors.primaryLight,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.primaryLight,
                          size: 18,
                        ),
                        onPressed: () => _editNote(s),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (s.notas != null && s.notas!.trim().isNotEmpty)
                        ? s.notas!
                        : 'Sin nota',
                    style: GoogleFonts.inter(
                      color: (s.notas != null && s.notas!.trim().isNotEmpty)
                          ? AppColors.textPrimaryLight
                          : AppColors.textHintLight,
                      fontSize: 13,
                      fontStyle: (s.notas != null && s.notas!.trim().isNotEmpty)
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // -- ítems --------------------------------------------------------
            if (s.vendedorId != null &&
                (s.bidonesCargados > 0 ||
                    s.bidonesVaciosRecibidos > 0 ||
                    s.bidonesPrestadosEmpresa > 0)) ...[
              _BidonesVentaResumen(venta: s),
              const SizedBox(height: 16),
            ],

            Text(
              'Productos',
              style: GoogleFonts.inter(
                color: AppColors.primaryLight,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            if (s.items.isEmpty)
              Text(
                'Sin ítems',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondaryLight,
                  fontSize: 13,
                ),
              )
            else
              ...s.items.map((item) => _ItemTile(item: item)),

            const Divider(color: AppColors.surfaceVariantLight, height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimaryLight,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  CurrencyUtils.format(s.total),
                  style: GoogleFonts.inter(
                    color: AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
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
            ),
          ),
        ),
      ],
    ),
  );
}

class _BidonesVentaResumen extends StatelessWidget {
  final Venta venta;

  const _BidonesVentaResumen({required this.venta});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withAlpha((0.25 * 255).toInt()),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bidones de la venta',
            style: GoogleFonts.inter(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          _InfoRow('A subir', '${venta.bidonesCargados}'),
          _InfoRow('Vacíos recibidos', '${venta.bidonesVaciosRecibidos}'),
          if (venta.bidonesPrestadosEmpresa > 0)
            _InfoRow('Extra prestado', '${venta.bidonesPrestadosEmpresa}'),
        ],
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final ItemVenta item;
  const _ItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.water_drop_outlined,
            color: AppColors.primaryLight,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.nombreProducto,
              style: GoogleFonts.inter(
                color: AppColors.textPrimaryLight,
                fontSize: 13,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyUtils.format(item.subtotal),
                style: GoogleFonts.inter(
                  color: AppColors.textPrimaryLight,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                '${CurrencyUtils.format(item.precioUnitario)} c/u',
                style: GoogleFonts.inter(
                  color: AppColors.textHintLight,
                  fontSize: 10,
                ),
              ),
              if (item.devolucion > 0)
                Text(
                  'Devueltos: ${item.devolucion} (-${CurrencyUtils.format(item.creditoDevolucion)})',
                  style: GoogleFonts.inter(
                    color: AppColors.warning,
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
