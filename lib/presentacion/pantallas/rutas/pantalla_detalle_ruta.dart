import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import '../../componentes/saldo_favor_despacho.dart';

import '../../../nucleo/constantes/colores_app.dart';
import '../../../nucleo/utilidades/utilidades_moneda.dart';
import '../../../nucleo/utilidades/utilidades_fecha.dart';
import '../../../datos/modelos/ruta.dart';
import '../../../dominio/entidades/rol_usuario.dart';
import '../../../presentacion/proveedores/proveedor_autenticacion.dart';
import '../../../presentacion/proveedores/proveedor_ruta.dart';

double _parsearDecimal(String text) {
  return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
}

class RutaDetailScreen extends ConsumerStatefulWidget {
  final String rutaId;
  final bool showAbonoOnOpen;

  const RutaDetailScreen({
    super.key,
    required this.rutaId,
    this.showAbonoOnOpen = false,
  });

  @override
  ConsumerState<RutaDetailScreen> createState() => _RutaDetailScreenState();
}

class _RutaDetailScreenState extends ConsumerState<RutaDetailScreen> {
  Ruta? _ruta;
  bool _loading = true;
  bool _showAbono = false;
  bool _guardando = false;
  double? _saldoDisponible;
  bool _errorSaldo = false;
  String? _operacionSaldoId;
  String? _solicitudSaldo;

  final _abonoCtrl = TextEditingController();
  final _abonoNotaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final rol = ref.read(proveedorNotificadorAuth).usuario?.rol;
    _showAbono =
        widget.showAbonoOnOpen && rol != null && rol != RolUsuario.vendedor;
    _load();
  }

  @override
  void dispose() {
    _abonoCtrl.dispose();
    _abonoNotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ruta = await ref
          .read(proveedorServicioRuta)
          .obtenerPorId(widget.rutaId);
      final usuario = ref.read(proveedorNotificadorAuth).usuario;
      if (usuario?.rol == RolUsuario.vendedor &&
          ruta.vendedorId != usuario?.vendedorId) {
        throw StateError('No tienes acceso a este despacho.');
      }
      if (!mounted) return;
      setState(() {
        _ruta = ruta;
        _loading = false;
      });
      try {
        final saldo = await ref
            .read(proveedorServicioRuta)
            .obtenerSaldoAFavorDisponible(ruta);
        if (mounted) {
          setState(() {
            _saldoDisponible = saldo;
            _errorSaldo = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _errorSaldo = true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _abonar({double descuento = 0, double credito = 0}) async {
    if (_guardando) return;
    final rol = ref.read(proveedorNotificadorAuth).usuario?.rol;
    if (rol == RolUsuario.vendedor) {
      _error('El rol Vendedor no puede registrar abonos.');
      return;
    }

    final montoEfectivo = _parsearDecimal(_abonoCtrl.text);
    if (!montoEfectivo.isFinite ||
        !descuento.isFinite ||
        !credito.isFinite ||
        credito < 0 ||
        montoEfectivo < 0 ||
        descuento < 0 ||
        descuento + credito > (_ruta?.saldoPendienteVisible ?? 0) + 0.001) {
      _error(
        'Revisa el pago y el descuento. El descuento no puede superar el saldo.',
      );
      return;
    }

    if (montoEfectivo <= 0 && descuento <= 0 && credito <= 0) {
      _error('Ingresa un monto cobrado o un valor de descuento');
      return;
    }

    setState(() => _guardando = true);
    try {
      final notaFinal = _abonoNotaCtrl.text.trim().isEmpty
          ? null
          : _abonoNotaCtrl.text.trim();
      final solicitud = '$credito|$montoEfectivo|$descuento|$notaFinal';
      if (_solicitudSaldo != solicitud) {
        _solicitudSaldo = solicitud;
        _operacionSaldoId = const Uuid().v4();
      }

      final ruta = await ref
          .read(proveedorNotificadorRuta.notifier)
          .registrarPagoConDescuento(
            rutaId: widget.rutaId,
            montoEfectivo: montoEfectivo,
            descuento: descuento,
            nota: notaFinal,
            credito: credito,
            operacionId: _operacionSaldoId,
          );
      _abonoCtrl.clear();
      _abonoNotaCtrl.clear();
      if (!mounted) return;
      setState(() {
        _ruta = ruta;
        _showAbono = false;
        _guardando = false;
        _saldoDisponible = ((_saldoDisponible ?? 0) - credito).clamp(
          0,
          double.infinity,
        );
        _solicitudSaldo = null;
        _operacionSaldoId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (credito > 0
                ? 'Saldo a favor aplicado y pago registrado correctamente'
                : descuento > 0
                ? 'Descuento y pago aplicados correctamente'
                : 'Pago registrado correctamente'),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      _error('$e');
    }
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _confirmDelete() async {
    final rol = ref.read(proveedorNotificadorAuth).usuario?.rol;
    if (rol != RolUsuario.admin) {
      _error('Solo el administrador puede eliminar despachos.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text(
          'Eliminar despacho',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '¿Eliminar este despacho y sus pagos?',
          style: GoogleFonts.inter(color: AppColors.textSecondaryLight),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textSecondaryLight),
            ),
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

    if (ok == true && mounted) {
      await ref.read(proveedorNotificadorRuta.notifier).eliminar(widget.rutaId);
      if (mounted) context.pop();
    }
  }

  Future<void> _editNote(Ruta ruta) async {
    final rol = ref.read(proveedorNotificadorAuth).usuario?.rol;
    if (rol == RolUsuario.vendedor) {
      _error('El rol Vendedor no puede editar despachos.');
      return;
    }

    final noteCtrl = TextEditingController(text: ruta.notas);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text(
          'Nota de despacho',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimaryLight),
          decoration: const InputDecoration(
            hintText: 'Añadir observación o nota...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.textHintLight),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      try {
        await ref
            .read(proveedorNotificadorRuta.notifier)
            .actualizarNota(ruta.id, noteCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nota actualizada correctamente'),
              backgroundColor: AppColors.success,
            ),
          );
          _load();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al actualizar: $e'),
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

    if (_ruta == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Despacho no encontrado')),
      );
    }

    final ruta = _ruta!;
    final rol = ref.watch(proveedorNotificadorAuth).usuario?.rol;
    final esAdministrador = rol == RolUsuario.admin;
    final esVendedor = rol == RolUsuario.vendedor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Despacho - ${ruta.nombreVendedor}'),
        actions: [
          if (esAdministrador)
            IconButton(
              tooltip: 'Eliminar despacho',
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderCard(
              ruta: ruta,
              onEditNote: esVendedor ? null : () => _editNote(ruta),
            ),
            if (ruta.ventas.isNotEmpty) ...[
              const SizedBox(height: 12),
              _VentasRutaCard(ruta: ruta),
            ],
            if (!esVendedor && ruta.tieneBidones) ...[
              const SizedBox(height: 12),
              _BidonesSummaryCard(ruta: ruta),
            ],
            const SizedBox(height: 12),
            if (!esVendedor && ruta.estado != EstadoRuta.pagado) ...[
              _AbonoCard(
                ruta: ruta,
                expanded: _showAbono,
                abonoCtrl: _abonoCtrl,
                notaCtrl: _abonoNotaCtrl,
                guardando: _guardando,
                saldoDisponible: _saldoDisponible,
                errorSaldo: _errorSaldo,
                onRecargarSaldo: _load,
                onToggle: () => setState(() => _showAbono = !_showAbono),
                onAbonar: _abonar,
                onTodo: () => setState(
                  () => _abonoCtrl.text = ruta.saldoPendienteVisible
                      .toStringAsFixed(2),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!esVendedor &&
                widget.showAbonoOnOpen &&
                ruta.montoCobrado == 0 &&
                ruta.saldoPendiente > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '¿El vendedor dejó algún pago inicial?',
                  style: GoogleFonts.inter(
                    color: AppColors.stockWarning,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (ruta.abonos.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _SectionTitle('Historial de pagos'),
              const SizedBox(height: 8),
              ...ruta.abonos.map((abono) => _AbonoHistTile(abono: abono)),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.inter(
        color: AppColors.primaryLight,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Ruta ruta;
  final VoidCallback? onEditNote;

  const _HeaderCard({required this.ruta, required this.onEditNote});

  Color get _color {
    switch (ruta.estado) {
      case EstadoRuta.pagado:
        return AppColors.success;
      case EstadoRuta.parcial:
        return AppColors.stockWarning;
      case EstadoRuta.pendiente:
        return AppColors.error;
      case EstadoRuta.sinCierre:
        return AppColors.textHintLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_color.withAlpha((0.15 * 255).toInt()), AppColors.cardLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withAlpha((0.3 * 255).toInt())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                ruta.nombreVendedor,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimaryLight,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _color.withAlpha((0.2 * 255).toInt()),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ruta.estado.etiqueta,
                  style: GoogleFonts.inter(
                    color: _color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppDateUtils.formatDate(ruta.fecha),
            style: GoogleFonts.inter(
              color: AppColors.textSecondaryLight,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _Stat(
                'Total estimado',
                CurrencyUtils.format(ruta.totalCalculado),
                AppColors.textPrimaryLight,
              ),
              _Stat(
                'Cobrado',
                CurrencyUtils.format(ruta.montoCobrado),
                AppColors.success,
              ),
              _Stat(
                ruta.tieneSaldoAFavor ? 'A favor' : 'Pendiente',
                CurrencyUtils.format(
                  ruta.tieneSaldoAFavor
                      ? ruta.saldoAFavor
                      : ruta.saldoPendienteVisible,
                ),
                ruta.tieneSaldoAFavor ? AppColors.success : AppColors.error,
              ),
            ],
          ),
          if (ruta.notas != null && ruta.notas!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Nota / Observación',
                        style: GoogleFonts.inter(
                          color: AppColors.textHintLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (onEditNote != null)
                        InkWell(
                          onTap: onEditNote,
                          child: const Icon(
                            Icons.edit_note_rounded,
                            color: AppColors.primaryLight,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ruta.notas!,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondaryLight,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (onEditNote != null) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: onEditNote,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_comment_rounded,
                      color: AppColors.primaryLight,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Añadir una nota o comentario',
                      style: GoogleFonts.inter(
                        color: AppColors.primaryLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BidonesSummaryCard extends StatelessWidget {
  final Ruta ruta;

  const _BidonesSummaryCard({required this.ruta});

  @override
  Widget build(BuildContext context) {
    final finalLlenos = ruta.bidonesLlenosFinales;
    final finalVacios = ruta.bidonesVaciosFinales;
    final prestadosFinales = ruta.bidonesPrestadosFinales;

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
          Text(
            'Movimiento de bidones',
            style: GoogleFonts.inter(
              color: AppColors.primaryLight,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Se muestra lo que el vendedor tenía al iniciar, la carga nueva del día y cómo quedó el vehículo al cerrar.',
            style: GoogleFonts.inter(
              color: AppColors.textSecondaryLight,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BidonesStatChip(
                label: 'Inicio',
                value:
                    '${ruta.bidonesLlenosIniciales}L / ${ruta.bidonesVaciosIniciales}V',
                color: AppColors.primaryLight,
              ),
              _BidonesStatChip(
                label: 'Carga hoy',
                value: '${ruta.bidonesCargadosHoy} llenos',
                color: AppColors.warning,
              ),
              _BidonesStatChip(
                label: 'Recogidos',
                value: '${ruta.bidonesVaciosRecogidos} vacíos',
                color: AppColors.info,
              ),
              _BidonesStatChip(
                label: 'Final',
                value: finalLlenos == null
                    ? 'Sin cierre'
                    : '${finalLlenos}L / ${finalVacios ?? 0}V',
                color: finalLlenos == null
                    ? AppColors.textHintLight
                    : AppColors.teal,
              ),
              _BidonesStatChip(
                label: 'Prestados iniciales',
                value: '${ruta.bidonesPrestadosIniciales}',
                color: AppColors.stockWarning,
              ),
              if (prestadosFinales != null)
                _BidonesStatChip(
                  label: 'Prestados finales',
                  value: '$prestadosFinales',
                  color: AppColors.stockWarning,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VentasRutaCard extends StatelessWidget {
  final Ruta ruta;

  const _VentasRutaCard({required this.ruta});

  @override
  Widget build(BuildContext context) {
    final creditoAplicado = ruta.ventas.fold<double>(
      0,
      (sum, venta) => sum + venta.creditoAplicado,
    );

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
          Text(
            'Ventas del despacho',
            style: GoogleFonts.inter(
              color: AppColors.primaryLight,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (creditoAplicado > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Saldo a favor aplicado: ${CurrencyUtils.format(creditoAplicado)}. Este valor ya se descontó del total pendiente del despacho.',
                style: GoogleFonts.inter(
                  color: AppColors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          ...ruta.ventas.map(
            (venta) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.primaryLight,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppDateUtils.formatDate(venta.fecha),
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimaryLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${venta.bidonesCargados} bidones subidos  •  ${venta.bidonesVaciosRecibidos} vacíos recibidos',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondaryLight,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    CurrencyUtils.format(venta.totalEfectivo),
                    style: GoogleFonts.inter(
                      color: AppColors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BidonesStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BidonesStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha((0.16 * 255).toInt()),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textHintLight,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.textHintLight,
            fontSize: 10,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _AbonoCard extends StatefulWidget {
  final Ruta ruta;
  final bool expanded;
  final bool guardando;
  final TextEditingController abonoCtrl;
  final TextEditingController notaCtrl;
  final VoidCallback onToggle;
  final void Function({double descuento, double credito}) onAbonar;
  final double? saldoDisponible;
  final bool errorSaldo;
  final VoidCallback onRecargarSaldo;
  final VoidCallback onTodo;

  const _AbonoCard({
    required this.ruta,
    required this.expanded,
    required this.guardando,
    required this.abonoCtrl,
    required this.notaCtrl,
    required this.onToggle,
    required this.onAbonar,
    required this.onTodo,
    required this.saldoDisponible,
    required this.errorSaldo,
    required this.onRecargarSaldo,
  });

  @override
  State<_AbonoCard> createState() => _AbonoCardState();
}

class _AbonoCardState extends State<_AbonoCard> {
  final _descuentoCtrl = TextEditingController();
  bool _aplicarSaldo = false;

  @override
  void didUpdateWidget(covariant _AbonoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guardando && !widget.guardando && !widget.expanded) {
      _descuentoCtrl.clear();
      _aplicarSaldo = false;
    }
  }

  @override
  void dispose() {
    _descuentoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resumen = ResumenSaldoDespacho.calcular(
      saldo: widget.saldoDisponible ?? 0,
      pendiente: widget.ruta.saldoPendienteVisible,
      descuento: _parsearDecimal(_descuentoCtrl.text).isFinite
          ? _parsearDecimal(_descuentoCtrl.text)
          : 0,
      aplicar: _aplicarSaldo,
    );
    final notasVentas = widget.ruta.ventas
        .where((v) => v.notas != null && v.notas!.trim().isNotEmpty)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.success.withAlpha((0.4 * 255).toInt()),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withAlpha((0.2 * 255).toInt()),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.payments_rounded,
                      color: AppColors.success,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registrar pago / Descuento',
                          style: GoogleFonts.inter(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          widget.ruta.tieneSaldoAFavor
                              ? 'Saldo a favor: ${CurrencyUtils.format(widget.ruta.saldoAFavor)}'
                              : 'Saldo pendiente: ${CurrencyUtils.format(widget.ruta.saldoPendienteVisible)}',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondaryLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    widget.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppColors.textHintLight,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.errorSaldo)
                    TextButton(
                      onPressed: widget.guardando
                          ? null
                          : widget.onRecargarSaldo,
                      child: const Text(
                        'No se pudo consultar el saldo a favor. Reintentar',
                      ),
                    )
                  else if (widget.saldoDisponible == null)
                    const LinearProgressIndicator()
                  else if (widget.saldoDisponible! > 0.009 &&
                      widget.ruta.saldoPendienteVisible > 0)
                    SaldoFavorDespacho(
                      disponible: widget.saldoDisponible!,
                      resumen: resumen,
                      seleccionado: _aplicarSaldo,
                      onChanged: widget.guardando
                          ? null
                          : (value) => setState(() => _aplicarSaldo = value),
                    ),
                  if (notasVentas.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.stockWarning.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.stockWarning.withAlpha(50),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.note_alt_rounded,
                                color: AppColors.stockWarning,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Notas de ventas en este despacho:',
                                style: GoogleFonts.inter(
                                  color: AppColors.stockWarning,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...notasVentas.map(
                            (v) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${v.notas}',
                                style: GoogleFonts.inter(
                                  color: AppColors.textPrimaryLight,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.abonoCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            color: AppColors.textPrimaryLight,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Monto cobrado',
                            prefixIcon: Icon(
                              Icons.attach_money_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          final saldo = resumen.pendiente;
                          widget.abonoCtrl.text = saldo
                              .clamp(0, double.infinity)
                              .toStringAsFixed(2);
                        },
                        child: Text(
                          'Todo',
                          style: GoogleFonts.inter(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descuentoCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: AppColors.textPrimaryLight),
                    decoration: const InputDecoration(
                      labelText: 'Descuento (pago directo al dueño)',
                      prefixIcon: Icon(Icons.money_off_rounded, size: 18),
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.notaCtrl,
                    style: const TextStyle(color: AppColors.textPrimaryLight),
                    decoration: const InputDecoration(
                      labelText: 'Nota de cobro (opcional)',
                      prefixIcon: Icon(Icons.notes_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.guardando
                          ? null
                          : () {
                              final desc = _parsearDecimal(_descuentoCtrl.text);
                              widget.onAbonar(
                                descuento: desc,
                                credito: resumen.aplicado,
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                      ),
                      child: widget.guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Registrar pago'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AbonoHistTile extends StatelessWidget {
  final dynamic abono;

  const _AbonoHistTile({required this.abono});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.success.withAlpha((0.2 * 255).toInt()),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_rounded,
            color: AppColors.success,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppDateUtils.formatDate(abono.fecha),
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimaryLight,
                    fontSize: 12,
                  ),
                ),
                if (abono.nota != null)
                  Text(
                    abono.nota!,
                    style: GoogleFonts.inter(
                      color: AppColors.textHintLight,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            CurrencyUtils.format(abono.monto),
            style: GoogleFonts.inter(
              color: AppColors.success,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
