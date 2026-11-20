import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../modelos/producto.dart';
import '../modelos/venta.dart';

class ServicioReportePdf {
  static final _fmtMoneda = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 2,
  );
  static final _fmtFecha = DateFormat('dd/MM/yyyy HH:mm');
  static final _fmtFechaCorta = DateFormat('dd/MM/yyyy');

  static Future<void> generarYCompartirReporte({
    required List<Venta> ventas,
    required List<Producto> productos,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required String generadoPor,
    String? filtroVendedorId,
    String? filtroNombreVendedor,
  }) async {
    final bytes = await generarReporte(
      ventas: ventas,
      productos: productos,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      generadoPor: generadoPor,
      filtroVendedorId: filtroVendedorId,
      filtroNombreVendedor: filtroNombreVendedor,
    );
    final filename =
        'Reporte_AguaMilena_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<Uint8List> generarReporte({
    required List<Venta> ventas,
    required List<Producto> productos,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required String generadoPor,
    String? filtroVendedorId,
    String? filtroNombreVendedor,
  }) async {
    final pdf = pw.Document();
    final ventasFiltradas = ventas.where((v) {
      final matchFecha =
          v.fecha.isAfter(fechaInicio.subtract(const Duration(seconds: 1))) &&
          v.fecha.isBefore(fechaFin.add(const Duration(days: 1)));
      final matchVendedor =
          filtroVendedorId == null || v.vendedorId == filtroVendedorId;
      return matchFecha && matchVendedor;
    }).toList()..sort((a, b) => b.fecha.compareTo(a.fecha));

    final totalVentas = ventasFiltradas.fold(0.0, (s, v) => s + v.total);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 20),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 2),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'AGUA MILENA',
                style: pw.TextStyle(
                  color: PdfColors.blue800,
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Reporte Gerencial',
                style: const pw.TextStyle(
                  color: PdfColors.grey700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text(
            'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 12),
          ),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 20),
          _filaInfo(
            'Período:',
            '${_fmtFechaCorta.format(fechaInicio)} - ${_fmtFechaCorta.format(fechaFin)}',
          ),
          if (filtroNombreVendedor != null)
            _filaInfo('Filtro Vendedor:', filtroNombreVendedor),
          _filaInfo('Generado por:', generadoPor),
          _filaInfo('Fecha de emisión:', _fmtFecha.format(DateTime.now())),
          pw.SizedBox(height: 30),
          pw.Text(
            'Resumen Financiero',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total de Ventas Brutas:',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _fmtMoneda.format(totalVentas),
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
              ],
            ),
          ),
          /*pw.SizedBox(height: 30),
          pw.Text(
            'Estado del Inventario (Distribuidora)',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(height: 10),
          _tablaInventario(
            productos
                .where((p) => p.catalogo == CatalogoProducto.distribuidora)
                .toList(),
          ),*/
          pw.SizedBox(height: 30),
          pw.Text(
            'Desglose de Ventas del Período',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(height: 10),
          _tablaVentas(ventasFiltradas),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _filaInfo(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 120,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.Text(value),
      ],
    ),
  );

  /*static pw.Widget _tablaInventario(List<Producto> productos) {
    if (productos.isEmpty) {
      return pw.Text(
        'No hay productos registrados.',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: ['Producto', 'Unidad', 'Stock Actual', 'Mínimo', 'Estado'],
      data: productos
          .map(
            (p) => [
              p.nombre,
              p.unidad,
              p.stock.toString(),
              p.stockMinimo.toString(),
              p.esCritico
                  ? 'Crítico'
                  : p.esBajo
                  ? 'Bajo'
                  : 'Óptimo',
            ],
          )
          .toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey600),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
      ),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.center,
      },
    );
  }*/

  static pw.Widget _tablaVentas(List<Venta> ventas) {
    if (ventas.isEmpty) {
      return pw.Text(
        'No hay ventas en el período.',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }

    final hayDescuento = ventas.any((v) => v.creditoAplicado > 0);

    if (!hayDescuento) {
      return pw.TableHelper.fromTextArray(
        headers: ['Fecha y hora', 'Responsable', 'Productos', 'Total a Pagar'],
        data: ventas
            .map(
              (v) => [
                _fmtFecha.format(v.creadoEn.toLocal()),
                v.mostrarVendedor,
                _resumenProductosVenta(v),
                _fmtMoneda.format(v.total),
              ],
            )
            .toList(),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.35),
          1: pw.FlexColumnWidth(1.45),
          2: pw.FlexColumnWidth(2.6),
          3: pw.FlexColumnWidth(1.05),
        },
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey600),
        rowDecoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
        ),
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: {3: pw.Alignment.centerRight},
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: [
        'Fecha y hora',
        'Responsable',
        'Productos',
        'Subtotal',
        'Descuento',
        'Total a Pagar',
      ],
      data: ventas
          .map(
            (v) => [
              _fmtFecha.format(v.creadoEn.toLocal()),
              v.mostrarVendedor,
              _resumenProductosVenta(v),
              _fmtMoneda.format(v.total),
              v.creditoAplicado > 0
                  ? '- ${_fmtMoneda.format(v.creditoAplicado)}'
                  : '-',
              _fmtMoneda.format(v.totalEfectivo),
            ],
          )
          .toList(),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.25),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(0.95),
        4: pw.FlexColumnWidth(0.95),
        5: pw.FlexColumnWidth(0.95),
      },
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 8,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey600),
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
      ),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
    );
  }

  static String _resumenProductosVenta(Venta venta) {
    if (venta.items.isEmpty) return 'Sin detalle';

    return venta.items
        .map(
          (item) =>
              '${item.cantidad} ${item.nombreProducto}'
              '${item.devolucion > 0 ? ' (devueltos: ${item.devolucion})' : ''}',
        )
        .join('\n');
  }
}
