import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../datos/servicios/servicio_reporte_pdf.dart';
import '../../../datos/modelos/vendedor.dart';
import '../proveedores/proveedor_autenticacion.dart';
import '../proveedores/proveedor_producto.dart';
import '../proveedores/proveedor_venta.dart';
import '../proveedores/proveedor_vendedor.dart';

class DialogoFiltroReporte extends ConsumerStatefulWidget {
  const DialogoFiltroReporte({super.key});

  @override
  ConsumerState<DialogoFiltroReporte> createState() =>
      _DialogoFiltroReporteState();
}

class _DialogoFiltroReporteState extends ConsumerState<DialogoFiltroReporte> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  String? _selectedSellerId;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(proveedorNotificadorVendedor.notifier).cargar(),
    );
  }

  Future<void> _selectStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: _endDate,
    );
    if (date != null) {
      setState(() => _startDate = date);
    }
  }

  Future<void> _selectEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() => _endDate = date);
    }
  }

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    try {
      final sales = ref.read(proveedorNotificadorVenta).value ?? [];
      final products = ref.read(proveedorNotificadorProducto).value ?? [];
      final user = ref.read(proveedorNotificadorAuth).usuario;
      final sellersInfo = ref.read(proveedorNotificadorVendedor).value ?? [];

      String? filterSellerName;
      if (_selectedSellerId != null) {
        if (_selectedSellerId == Vendedor.distribuidora.id) {
          filterSellerName = 'Distribuidora Central';
        } else {
          final selected = sellersInfo.firstWhere(
            (vendedor) => vendedor.id == _selectedSellerId,
            orElse: () => Vendedor.distribuidora,
          );
          filterSellerName = selected.nombre;
        }
      }

      await ServicioReportePdf.generarYCompartirReporte(
        ventas: sales,
        productos: products,
        fechaInicio: _startDate,
        fechaFin: _endDate,
        generadoPor: user?.nombre ?? 'Administrador',
        filtroVendedorId: _selectedSellerId,
        filtroNombreVendedor: filterSellerName,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar el PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(
        'Exportar reporte',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: compact ? 19 : 21,
        ),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 320 : 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seleccione el rango de fechas para evaluar las ventas del reporte PDF.',
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
                  value: _formatDate(_startDate),
                  onTap: _isGenerating ? null : _selectStartDate,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: 'Hasta',
                  value: _formatDate(_endDate),
                  onTap: _isGenerating ? null : _selectEndDate,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Desde',
                        value: _formatDate(_startDate),
                        onTap: _isGenerating ? null : _selectStartDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        label: 'Hasta',
                        value: _formatDate(_endDate),
                        onTap: _isGenerating ? null : _selectEndDate,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Consumer(
                builder: (context, ref, child) {
                  final sellersAsync = ref.watch(proveedorNotificadorVendedor);
                  return sellersAsync.when(
                    data: (sellers) {
                      final allSellers = [Vendedor.distribuidora, ...sellers];
                      return DropdownButtonFormField<String?>(
                        initialValue: _selectedSellerId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Filtro por vendedor',
                          prefixIcon: Icon(Icons.storefront_rounded),
                        ),
                        selectedItemBuilder: (context) {
                          return [
                            const _DropdownLabel('Todos los vendedores'),
                            ...allSellers.map(
                              (vendedor) => _DropdownLabel(
                                vendedor.esDistribuidora
                                    ? 'Distribuidora Central'
                                    : vendedor.nombre,
                              ),
                            ),
                          ];
                        },
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: _DropdownLabel('Todos los vendedores'),
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
                        onChanged: _isGenerating
                            ? null
                            : (value) {
                                setState(() => _selectedSellerId = value);
                              },
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => Text(
                      'Error cargando vendedores: $err',
                      style: GoogleFonts.inter(
                        color: AppColors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
              if (_isGenerating)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Center(child: CircularProgressIndicator()),
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
              onPressed: _isGenerating
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: _isGenerating ? null : _generate,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(compact ? 'Generar PDF' : 'Generar / Compartir'),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DateField({required this.label, required this.value, this.onTap});

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
