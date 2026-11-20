import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../nucleo/constantes/colores_app.dart';
import '../../../datos/modelos/vendedor.dart';
import '../../../presentacion/proveedores/proveedor_ruta.dart';
import '../../../presentacion/proveedores/proveedor_vendedor.dart';

/// Pantalla de Nueva Ruta.
/// Puede recibir [preselectedSellerId] cuando se activa
/// desde la pantalla de Nueva Venta al escoger un vendedor.
class NewRutaScreen extends ConsumerStatefulWidget {
  final String? preselectedSellerId;
  const NewRutaScreen({super.key, this.preselectedSellerId});

  @override
  ConsumerState<NewRutaScreen> createState() => _NewRutaScreenState();
}

class _NewRutaScreenState extends ConsumerState<NewRutaScreen> {
  Vendedor? _seller;
  DateTime _fecha = DateTime.now();
  final _notasCtrl = TextEditingController();
  bool _saving = false;

  final _cargadosHoyCtrl = TextEditingController(text: '0');

  int get _cargadosHoy => int.tryParse(_cargadosHoyCtrl.text) ?? 0;

  @override
  void dispose() {
    _notasCtrl.dispose();
    _cargadosHoyCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_seller == null) {
      _error('Selecciona un vendedor');
      return;
    }

    setState(() => _saving = true);
    try {
      final ruta = await ref
          .read(proveedorNotificadorRuta.notifier)
          .crear(
            vendedorId: _seller!.id,
            items: const [],
            notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text,
            bidonesCargadosHoy: _cargadosHoy,
          );
      await ref.read(proveedorNotificadorVendedor.notifier).cargar();
      ref.invalidate(proveedorVendedoresActivos);

      if (!mounted) return;
      context.pushReplacement('/rutas/detail/${ruta.id}?showAbono=1');
    } catch (e) {
      if (mounted) _error('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _error(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppColors.error),
  );

  @override
  Widget build(BuildContext context) {
    final sellersAsync = ref.watch(proveedorVendedoresActivos);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _seller == null ? 'Nuevo despacho' : 'Despacho - ${_seller!.nombre}',
        ),
        actions: [
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
                    'Confirmar',
                    style: GoogleFonts.inter(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              sellersAsync.when(
                loading: () => const LinearProgressIndicator(
                  color: AppColors.primaryLight,
                ),
                error: (_, _) => const SizedBox.shrink(),
                data: (sellers) {
                  if (_seller == null && widget.preselectedSellerId != null) {
                    try {
                      _seller = sellers.firstWhere(
                        (s) => s.id == widget.preselectedSellerId,
                      );
                    } catch (_) {}
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cardLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(
                          (0.35 * 255).toInt(),
                        ),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        dropdownColor: AppColors.surfaceLight,
                        icon: const Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.textHintLight,
                        ),
                        hint: Row(
                          children: [
                            const Icon(
                              Icons.person_rounded,
                              color: AppColors.primaryLight,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Seleccionar vendedor',
                              style: GoogleFonts.inter(
                                color: AppColors.textHintLight,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        value: sellers.any((s) => s.id == _seller?.id)
                            ? _seller!.id
                            : null,
                        items: sellers.map((s) {
                          return DropdownMenuItem<String>(
                            value: s.id,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.primaryLight,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  s.nombre,
                                  style: GoogleFonts.inter(
                                    color: AppColors.textPrimaryLight,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (id) => setState(
                          () => _seller = sellers.firstWhere(
                            (vendedor) => vendedor.id == id,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _fecha,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(ctx).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: AppColors.primaryLight,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (d != null) setState(() => _fecha = d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withAlpha((0.3 * 255).toInt()),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        color: AppColors.primaryLight,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_fecha.day.toString().padLeft(2, '0')}/${_fecha.month.toString().padLeft(2, '0')}/${_fecha.year}',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimaryLight,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _BidonesSection(
                vendedor: _seller,
                cargadosHoyCtrl: _cargadosHoyCtrl,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notasCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimaryLight),
                decoration: const InputDecoration(hintText: 'Notas (opcional)'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
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
                          'Confirmar despacho',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
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

class _BidonesSection extends StatelessWidget {
  final Vendedor? vendedor;
  final TextEditingController cargadosHoyCtrl;
  final VoidCallback onChanged;

  const _BidonesSection({
    required this.vendedor,
    required this.cargadosHoyCtrl,
    required this.onChanged,
  });

  int get _cargadosHoy => int.tryParse(cargadosHoyCtrl.text) ?? 0;

  int get _prestadosEnRuta {
    final propios = vendedor?.bidonesPropios ?? 0;
    final totalFinal =
        (vendedor?.bidonesLlenosActuales ?? 0) +
        (vendedor?.bidonesVaciosActuales ?? 0) +
        _cargadosHoy;
    final excedente = totalFinal - propios;
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
          const SizedBox(height: 12),
          if ((vendedor?.bidonesPrestados ?? 0) > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.stockWarning.withAlpha((0.1 * 255).toInt()),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Prestados acumulados:',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondaryLight,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '${vendedor?.bidonesPrestados ?? 0}',
                    style: GoogleFonts.inter(
                      color: AppColors.stockWarning,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BidonSummaryChip(
                label: 'Llenos actuales',
                value: '${vendedor?.bidonesLlenosActuales ?? 0}',
                color: AppColors.primaryLight,
              ),
              _BidonSummaryChip(
                label: 'Vacíos actuales',
                value: '${vendedor?.bidonesVaciosActuales ?? 0}',
                color: AppColors.teal,
              ),
              _BidonSummaryChip(
                label: 'En vehículo',
                value:
                    '${(vendedor?.bidonesLlenosActuales ?? 0) + (vendedor?.bidonesVaciosActuales ?? 0)}',
                color: AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _BidonField(
            ctrl: cargadosHoyCtrl,
            label: 'Bidones llenos cargados hoy',
            hint: 'Ej: 20',
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha((0.1 * 255).toInt()),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total estimado en vehículo tras la carga:',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondaryLight,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '${(vendedor?.bidonesLlenosActuales ?? 0) + (vendedor?.bidonesVaciosActuales ?? 0) + _cargadosHoy}',
                  style: GoogleFonts.inter(
                    color: AppColors.primaryLight,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (_prestadosEnRuta > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Prestados estimados después de este despacho: $_prestadosEnRuta',
              style: GoogleFonts.inter(
                color: AppColors.stockWarning,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BidonSummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BidonSummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
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

class _BidonField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final VoidCallback onChanged;

  const _BidonField({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      onChanged: (_) => onChanged(),
      style: const TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          fontSize: 11,
          color: AppColors.textHintLight,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.primary.withAlpha((0.3 * 255).toInt()),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: AppColors.primary.withAlpha((0.3 * 255).toInt()),
          ),
        ),
      ),
    );
  }
}
