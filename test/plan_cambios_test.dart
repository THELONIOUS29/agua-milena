import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:agua_milena_app/datos/modelos/item_venta.dart';
import 'package:agua_milena_app/datos/modelos/precio_producto.dart';
import 'package:agua_milena_app/datos/modelos/ruta.dart';
import 'package:agua_milena_app/datos/modelos/venta.dart';
import 'package:agua_milena_app/datos/modelos/vendedor.dart';
import 'package:agua_milena_app/datos/servicios/servicio_reporte_pdf.dart';
import 'package:agua_milena_app/presentacion/proveedores/proveedor_venta.dart';

void main() {
  test(
    'El permiso de devoluciones viene del vendedor y se conserva al editarlo',
    () {
      Vendedor vendedor(String nombre, bool permiso) => Vendedor.desdeJson({
        'id': nombre,
        'nombre': nombre,
        'creado_en': '2026-10-12',
        'permite_devoluciones': permiso,
      });
      final yovany = vendedor('Yovany', true);
      expect(yovany.permiteDevoluciones, isTrue);
      expect(yovany.copiarCon(telefono: '123').permiteDevoluciones, isTrue);
      expect(vendedor('Oliver', false).permiteDevoluciones, isFalse);
      expect(Vendedor.distribuidora.permiteDevoluciones, isFalse);
    },
  );
  test('El precio especifico prevalece y respeta un precio de cero', () {
    const precios = [
      PrecioProducto(id: 'd', productoId: 'p', precio: 2),
      PrecioProducto(id: 'a', productoId: 'p', vendedorId: 'a', precio: 1),
      PrecioProducto(id: 'b', productoId: 'p', vendedorId: 'b', precio: 0),
    ];
    double resolver(String? vendedor, {String producto = 'p'}) =>
        PrecioProducto.resolver(
          precios: precios,
          productoId: producto,
          precioBase: 3,
          vendedorId: vendedor,
        );
    expect(resolver('a'), 1);
    expect(resolver('b'), 0);
    expect(resolver('otro'), 2);
    expect(resolver(null), 2);
    expect(resolver('a', producto: 'sin-precio'), 3);
  });

  test('El carrito mantiene devoluciones sin cantidad vendida', () {
    final carrito = NotificadorCarrito();
    addTearDown(carrito.dispose);
    carrito.agregarProducto(
      ItemCarrito(
        productoId: 'p',
        nombreProducto: 'Agua',
        precioUnitario: 2,
        unidad: 'unidad',
        cantidad: 5,
      ),
    );
    carrito.actualizarDevolucion(
      'p',
      3,
      nombreProducto: 'Agua',
      precioUnitario: 2,
      unidad: 'unidad',
    );
    expect(carrito.total, 10);
    expect(carrito.totalDevoluciones, 6);
    carrito.actualizarCantidad('p', 0);
    expect(carrito.state.single.cantidad, 0);
    expect(carrito.state.single.devolucion, 3);
    expect(carrito.state.single.aJsonItemVenta('v')['devolucion'], 3);
    carrito.actualizarDevolucion(
      'p',
      0,
      nombreProducto: 'Agua',
      precioUnitario: 2,
      unidad: 'unidad',
    );
    expect(carrito.state, isEmpty);
  });

  test(
    'Un descuento completo mantiene la ruta en cero aunque tenga ventas',
    () {
      final ruta = Ruta(
        id: 'r',
        vendedorId: 'a',
        nombreVendedor: 'Ana',
        fecha: DateTime(2026, 10, 4),
        creadoEn: DateTime(2026, 10, 4),
        montoTotal: 0,
        montoCobrado: 0,
        estado: EstadoRuta.pagado,
        ventas: [_venta(credito: 0)],
      );
      expect(ruta.totalCalculado, 0);
      expect(ruta.saldoPendiente, 0);
      expect(ruta.tieneSaldoAFavor, isFalse);
    },
  );

  for (final credito in [0.0, 2.0]) {
    test('Genera reporte PDF con credito $credito', () async {
      final bytes = await ServicioReportePdf.generarReporte(
        ventas: [_venta(credito: credito)],
        productos: [],
        fechaInicio: DateTime(2026, 10, 1),
        fechaFin: DateTime(2026, 10, 4),
        generadoPor: 'Prueba local',
      );
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
      final destino = Platform.environment['AGUA_PDF_QA_DIR'];
      if (destino != null) {
        await Directory(destino).create(recursive: true);
        await File(
          '$destino/reporte_${credito == 0 ? 'sin' : 'con'}_credito.pdf',
        ).writeAsBytes(bytes);
      }
    });
  }
}

Venta _venta({required double credito}) => Venta(
  id: 'v',
  fecha: DateTime(2026, 10, 4),
  creadoEn: DateTime(2026, 10, 4, 12),
  total: 8,
  creditoAplicado: credito,
  nombreVendedor: 'Vendedor de prueba',
  items: const [
    ItemVenta(
      id: 'i',
      ventaId: 'v',
      productoId: 'p',
      nombreProducto: 'Agua',
      cantidad: 5,
      devolucion: 1,
      precioUnitario: 2,
      subtotal: 10,
    ),
  ],
);
