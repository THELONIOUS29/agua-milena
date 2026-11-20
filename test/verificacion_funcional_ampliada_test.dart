import 'package:flutter_test/flutter_test.dart';
import 'package:agua_milena_app/datos/modelos/ruta.dart';
import 'package:agua_milena_app/dominio/entidades/rol_usuario.dart';
import 'package:agua_milena_app/datos/servicios/servicio_autenticacion.dart';
import 'verificacion_funcional_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = ServicioAutenticacion();
  test('PVF_002_E01 - Genera hash con formato PBKDF2 esperado', () {
    expect(
      auth.hashContrasena('Agua2026!').startsWith('pbkdf2_sha256\$210000\$'),
      isTrue,
    );
  });
  test('PVF_005_E02 - Convierte admin abreviado a admin', () {
    expect(RolUsuario.desdeTexto('admin') == RolUsuario.admin, isTrue);
  });
  test('PVF_006_E02 - Rechaza cadena vacia', () {
    expect(
      (() {
        try {
          RolUsuario.desdeTexto('');
          return false;
        } catch (_) {
          return true;
        }
      })(),
      isTrue,
    );
  });
  test('PVF_006_E03 - Rechaza rol con espacios', () {
    expect(
      (() {
        try {
          RolUsuario.desdeTexto(' admin ');
          return false;
        } catch (_) {
          return true;
        }
      })(),
      isTrue,
    );
  });
  test('PVF_006_E04 - Rechaza rol tecnico no definido', () {
    expect(
      (() {
        try {
          RolUsuario.desdeTexto('tecnico');
          return false;
        } catch (_) {
          return true;
        }
      })(),
      isTrue,
    );
  });
  test('PVF_007_E01 - Lee usuario con campos en espanol', () {
    expect(usuarioDesdeJsonEspanol().nombre == 'Administrador', isTrue);
  });
  test('PVF_007_E02 - Lee rol desde JSON en espanol', () {
    expect(usuarioDesdeJsonEspanol().rol == RolUsuario.admin, isTrue);
  });
  test('PVF_007_E03 - Lee usuario con campos en ingles', () {
    expect(usuarioDesdeJsonIngles().nombre == 'Planta', isTrue);
  });
  test('PVF_007_E04 - Lee rol desde JSON en ingles', () {
    expect(usuarioDesdeJsonIngles().rol == RolUsuario.planta, isTrue);
  });
  test('PVF_008_E01 - Serializa nombre del usuario', () {
    expect(usuarioAdmin().aJson()['name'] == 'Administrador', isTrue);
  });
  test('PVF_008_E02 - Serializa rol del usuario', () {
    expect(usuarioAdmin().aJson()['role'] == 'admin', isTrue);
  });
  test('PVF_008_E03 - Mantiene vendedor asociado en rol vendedor', () {
    expect(usuarioVendedor().vendedorId == 'v-01', isTrue);
  });
  test('PVF_010_E03 - Bloquea nueva contrasena sin numero', () {
    expect(!auth.esContrasenaValida('NuevaClave!'), isTrue);
  });
  test('PVF_010_E04 - Bloquea nueva contrasena sin simbolo', () {
    expect(!auth.esContrasenaValida('Nueva2026'), isTrue);
  });
  test('PVF_018_E02 - Conserva stock al serializar', () {
    expect(productoBase(stock: 20, minimo: 5).aJson()['stock'] == 20, isTrue);
  });
  test('PVF_018_E03 - Conserva stock minimo al serializar', () {
    expect(
      productoBase(stock: 20, minimo: 5).aJson()['stock_minimo'] == 5,
      isTrue,
    );
  });
  test('PVF_018_E04 - Conserva precio unitario', () {
    expect(productoBase(stock: 20, minimo: 5).precio == 1.50, isTrue);
  });
  test('PVF_019_E03 - No marca critico sobre el minimo', () {
    expect(!productoBase(stock: 6, minimo: 5).esCritico, isTrue);
  });
  test('PVF_019_E04 - Prioriza critico sobre stock bajo', () {
    expect(productoBase(stock: 5, minimo: 5, bajo: 8).esCritico, isTrue);
  });
  test('PVF_020_E02 - No confunde bajo con critico', () {
    expect(!productoBase(stock: 7, minimo: 5, bajo: 8).esCritico, isTrue);
  });
  test('PVF_020_E03 - No alerta stock suficiente', () {
    expect(sinAlertaStock(productoBase(stock: 20, minimo: 5, bajo: 8)), isTrue);
  });
  test('PVF_020_E04 - No marca bajo si no hay umbral bajo', () {
    expect(!productoBase(stock: 7, minimo: 5).esBajo, isTrue);
  });
  test('PVF_022_E01 - Acepta catalogo vendedor', () {
    expect(
      productoBase(
            stock: 10,
            minimo: 2,
            catalogo: 'vendedor',
          ).aJson()['catalogo'] ==
          'vendedor',
      isTrue,
    );
  });
  test('PVF_022_E02 - Acepta catalogo distribuidora por defecto', () {
    expect(
      productoBase(stock: 10, minimo: 2).aJson()['catalogo'] == 'distribuidora',
      isTrue,
    );
  });
  test('PVF_022_E03 - Copia producto actualizando precio', () {
    expect(
      productoBase(stock: 20, minimo: 5).copiarCon(precio: 2.0).precio == 2.0,
      isTrue,
    );
  });
  test('PVF_022_E04 - Copia producto actualizando stock', () {
    expect(
      productoBase(stock: 20, minimo: 5).copiarCon(stock: 30).stock == 30,
      isTrue,
    );
  });
  test('PVF_027_E01 - Calcula subtotal de bidon', () {
    expect(itemCarrito('Bidon de agua', 1.5, 4).subtotal == 6.0, isTrue);
  });
  test('PVF_027_E02 - Calcula subtotal de funda', () {
    expect(itemCarrito('Funda', 0.25, 4).subtotal == 1.0, isTrue);
  });
  test('PVF_027_E03 - Subtotal cero con cantidad cero', () {
    expect(itemCarrito('Bidon', 1.5, 0).subtotal == 0, isTrue);
  });
  test('PVF_027_E04 - Subtotal conserva decimales', () {
    expect(itemCarrito('Funda', 0.25, 3).subtotal == 0.75, isTrue);
  });
  test('PVF_033_E01 - Incluye subtotal en JSON', () {
    expect(
      itemCarrito('Bidon', 1.5, 3).aJsonItemVenta('venta-01')['subtotal'] ==
          4.5,
      isTrue,
    );
  });
  test('PVF_033_E02 - Incluye id de venta en JSON', () {
    expect(
      itemCarrito('Bidon', 1.5, 3).aJsonItemVenta('venta-01')['venta_id'] ==
          'venta-01',
      isTrue,
    );
  });
  test('PVF_033_E03 - Incluye cantidad en JSON', () {
    expect(
      itemCarrito('Bidon', 1.5, 3).aJsonItemVenta('venta-01')['cantidad'] == 3,
      isTrue,
    );
  });
  test('PVF_033_E04 - Incluye precio unitario en JSON', () {
    expect(
      itemCarrito(
            'Bidon',
            1.5,
            3,
          ).aJsonItemVenta('venta-01')['precio_unitario'] ==
          1.5,
      isTrue,
    );
  });
  test('PVF_039_E04 - Convierte sin cierre', () {
    expect(
      EstadoRutaExt.desdeTexto('sin_cierre') == EstadoRuta.sinCierre,
      isTrue,
    );
  });
  test('PVF_040_E03 - Etiqueta pendiente no esta vacia', () {
    expect(EstadoRuta.pendiente.etiqueta.isNotEmpty, isTrue);
  });
  test('PVF_040_E04 - Etiqueta pagado no esta vacia', () {
    expect(EstadoRuta.pagado.etiqueta.isNotEmpty, isTrue);
  });
  test('PVF_041_E02 - Ruta sin items suma cero', () {
    expect(rutaSinBidones().totalProductosSalida == 0, isTrue);
  });
  test('PVF_041_E03 - Suma dos items cargados', () {
    expect(rutaConItemsAbierta().items.length == 2, isTrue);
  });
  test('PVF_041_E04 - Total de salida es mayor que cero cuando hay carga', () {
    expect(rutaConItemsAbierta().totalProductosSalida > 0, isTrue);
  });
  test('PVF_042_E03 - Ruta pagada conserva estado pagado', () {
    expect(rutaPagada().estado == EstadoRuta.pagado, isTrue);
  });
  test('PVF_044_E04 - Ruta conserva vendedor asignado', () {
    expect(rutaConItemsAbierta().vendedorId == 'v-01', isTrue);
  });
  test('PVF_045_E03 - Monto cobrado parcial es menor al total', () {
    expect(
      rutaSaldoParcial().montoCobrado < rutaSaldoParcial().montoTotal,
      isTrue,
    );
  });
  test('PVF_045_E04 - Estado parcial se conserva', () {
    expect(rutaSaldoParcial().estado == EstadoRuta.parcial, isTrue);
  });
  test('PVF_046_E01 - Ruta pagada tiene saldo pendiente cero', () {
    expect(rutaPagada().saldoPendienteVisible == 0, isTrue);
  });
  test('PVF_046_E04 - Calcula excedente como saldo a favor', () {
    expect(rutaConSaldoAFavor().saldoAFavor == 30, isTrue);
  });
  test('PVF_049_E04 - Ruta con bidones reporta existencia', () {
    expect(rutaBidones().tieneBidones, isTrue);
  });
  test('PVF_050_E04 - Prestados finales son mayores o iguales a cero', () {
    expect(rutaBidones().bidonesPrestadosFinales! >= 0, isTrue);
  });
  test('PVF_051_E03 - Ruta sin bidones no calcula vendidos sin cierre', () {
    expect(rutaSinBidones().bidonesVendidos == null, isTrue);
  });
  test(
    'PVF_051_E04 - Ruta sin bidones no calcula vacios finales sin cierre',
    () {
      expect(rutaSinBidones().bidonesVaciosFinales == null, isTrue);
    },
  );
  test('PVF_052_E02 - Faltantes no son negativos', () {
    expect(itemRutaCerrado().faltantes! >= 0, isTrue);
  });
  test('PVF_052_E03 - Cantidad vendida mas sin vender respeta salida', () {
    expect(itemRutaCerrado().vendidos == 8, isTrue);
  });
  test('PVF_052_E04 - Retorno completo no genera faltante', () {
    expect(
      itemRutaCerrado()
              .copiarConRetorno(cantidadSinVender: 2, cantidadRetornoVacio: 8)
              .faltantes ==
          0,
      isTrue,
    );
  });
  test('PVF_053_E04 - Stock critico dispara alerta antes que bajo', () {
    expect(productoBase(stock: 4, minimo: 5, bajo: 8).esCritico, isTrue);
  });
  test('PVF_054_E04 - Calcula saldo a favor positivo', () {
    expect(rutaConSaldoAFavor().saldoAFavor > 0, isTrue);
  });
}
