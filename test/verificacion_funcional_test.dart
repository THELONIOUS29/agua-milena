import 'package:flutter_test/flutter_test.dart';

import 'package:agua_milena_app/dominio/entidades/rol_usuario.dart';
import 'package:agua_milena_app/datos/modelos/producto.dart';
import 'package:agua_milena_app/datos/modelos/item_venta.dart';
import 'package:agua_milena_app/datos/modelos/item_ruta.dart';
import 'package:agua_milena_app/datos/modelos/ruta.dart';
import 'package:agua_milena_app/datos/servicios/servicio_autenticacion.dart';

class CasoVerificacion {
  final String codigo;
  final String historia;
  final String nombre;
  final bool Function() ejecutar;

  const CasoVerificacion(
    this.codigo,
    this.historia,
    this.nombre,
    this.ejecutar,
  );
}

bool verificaHashCorrecto(ServicioAutenticacion auth) {
  final hash = auth.hashContrasena('Agua2026!');
  return hash.startsWith('pbkdf2_sha256\$210000\$') &&
      auth.verificarContrasena('Agua2026!', hash);
}

bool verificaHashIncorrecto(ServicioAutenticacion auth) {
  final hash = auth.hashContrasena('Agua2026!');
  return !auth.verificarContrasena('Mala2026!', hash);
}

bool lanzaRolInvalido() {
  try {
    RolUsuario.desdeTexto('supervisor');
    return false;
  } catch (_) {
    return true;
  }
}

UsuarioApp usuarioAdmin() => const UsuarioApp(
  id: 'u-admin',
  email: 'admin@aguamilena.com',
  nombre: 'Administrador',
  rol: RolUsuario.admin,
);

UsuarioApp usuarioVendedor() => const UsuarioApp(
  id: 'u-vendedor',
  email: 'vendedor@aguamilena.com',
  nombre: 'Vendedor',
  rol: RolUsuario.vendedor,
  vendedorId: 'v-01',
  telefono: 'TELEFONO_DE_EJEMPLO',
  urlAvatar: 'https://aguamilena.com/avatar.png',
);

UsuarioApp usuarioDesdeJsonEspanol() => UsuarioApp.desdeJson({
  'id': 'u-01',
  'email': 'admin@aguamilena.com',
  'nombre': 'Administrador',
  'rol': 'admin',
});

UsuarioApp usuarioDesdeJsonIngles() => UsuarioApp.desdeJson({
  'id': 'u-02',
  'email': 'planta@aguamilena.com',
  'name': 'Planta',
  'role': 'planta',
});

Producto productoBase({
  required int stock,
  required int minimo,
  int? bajo,
  String catalogo = 'distribuidora',
}) => Producto.desdeJson({
  'id': 'p-01',
  'nombre': 'Bidón de agua',
  'descripcion': 'Bidón de 20 litros',
  'unidad': 'bidón',
  'precio': 1.50,
  'stock': stock,
  'stock_minimo': minimo,
  if (bajo != null) 'stock_bajo_calculado': bajo,
  'catalogo': catalogo,
  'url_imagen': 'https://aguamilena.com/producto.png',
  'creado_en': '2026-06-01T10:00:00',
  'actualizado_en': '2026-06-01T11:00:00',
});

ItemCarrito itemCarrito(String nombre, double precio, int cantidad) =>
    ItemCarrito(
      productoId: 'p-01',
      nombreProducto: nombre,
      precioUnitario: precio,
      unidad: 'unidad',
      cantidad: cantidad,
    );

ItemRuta itemRutaCerrado() => const ItemRuta(
  id: 'ir-cerrado',
  rutaId: 'r-01',
  productoId: 'p-01',
  nombreProducto: 'Bidón',
  unidad: 'unidad',
  precioUnitario: 1.50,
  cantidadSalida: 10,
  cantidadSinVender: 2,
  cantidadRetornoVacio: 6,
);

Ruta rutaConItemsAbierta() => Ruta(
  id: 'r-abierta',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  fecha: DateTime(2026, 6, 1),
  montoTotal: 20,
  montoCobrado: 0,
  estado: EstadoRuta.pendiente,
  creadoEn: DateTime(2026, 6, 1),
  items: const [
    ItemRuta(
      id: 'ir-01',
      rutaId: 'r-abierta',
      productoId: 'p-01',
      nombreProducto: 'Bidón',
      unidad: 'unidad',
      precioUnitario: 1.50,
      cantidadSalida: 5,
    ),
    ItemRuta(
      id: 'ir-02',
      rutaId: 'r-abierta',
      productoId: 'p-02',
      nombreProducto: 'Funda',
      unidad: 'funda',
      precioUnitario: 0.25,
      cantidadSalida: 10,
    ),
  ],
);

Ruta rutaCerrada() => Ruta(
  id: 'r-cerrada',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  fecha: DateTime(2026, 6, 1),
  montoTotal: 20,
  montoCobrado: 20,
  estado: EstadoRuta.pagado,
  creadoEn: DateTime(2026, 6, 1),
  items: const [
    ItemRuta(
      id: 'ir-01',
      rutaId: 'r-cerrada',
      productoId: 'p-01',
      nombreProducto: 'Bidón',
      unidad: 'unidad',
      precioUnitario: 1.50,
      cantidadSalida: 10,
      cantidadSinVender: 2,
      cantidadRetornoVacio: 8,
    ),
  ],
);

Ruta rutaSaldoParcial() => Ruta(
  id: 'r-parcial',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  fecha: DateTime(2026, 6, 1),
  montoTotal: 100,
  montoCobrado: 40,
  estado: EstadoRuta.parcial,
  creadoEn: DateTime(2026, 6, 1),
);

Ruta rutaPagada() => Ruta(
  id: 'r-pagada',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  fecha: DateTime(2026, 6, 1),
  montoTotal: 100,
  montoCobrado: 100,
  estado: EstadoRuta.pagado,
  creadoEn: DateTime(2026, 6, 1),
);

Ruta rutaConSaldoAFavor() => Ruta(
  id: 'r-excedente',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  fecha: DateTime(2026, 6, 1),
  montoTotal: 100,
  montoCobrado: 130,
  estado: EstadoRuta.pagado,
  creadoEn: DateTime(2026, 6, 1),
);

Ruta rutaBidones() => Ruta(
  id: 'r-bidones',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  vendedorBidonesPropios: 5,
  fecha: DateTime(2026, 6, 1),
  montoTotal: 20,
  montoCobrado: 20,
  estado: EstadoRuta.pagado,
  creadoEn: DateTime(2026, 6, 1),
  bidonesLlenosIniciales: 6,
  bidonesVaciosIniciales: 2,
  bidonesCargadosHoy: 4,
  items: const [
    ItemRuta(
      id: 'ir-01',
      rutaId: 'r-bidones',
      productoId: 'p-01',
      nombreProducto: 'Bidón',
      unidad: 'unidad',
      precioUnitario: 1.50,
      cantidadSalida: 10,
      cantidadSinVender: 3,
      cantidadRetornoVacio: 7,
    ),
  ],
);

Ruta rutaBidonesNegativos() => Ruta(
  id: 'r-negativos',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  vendedorBidonesPropios: 20,
  fecha: DateTime(2026, 6, 1),
  montoTotal: 20,
  montoCobrado: 20,
  estado: EstadoRuta.pagado,
  creadoEn: DateTime(2026, 6, 1),
  bidonesLlenosIniciales: 2,
  bidonesVaciosIniciales: 0,
  bidonesCargadosHoy: 0,
  items: const [
    ItemRuta(
      id: 'ir-01',
      rutaId: 'r-negativos',
      productoId: 'p-01',
      nombreProducto: 'Bidón',
      unidad: 'unidad',
      precioUnitario: 1.50,
      cantidadSalida: 10,
      cantidadSinVender: 0,
      cantidadRetornoVacio: 10,
    ),
  ],
);

Ruta rutaSinBidones() => Ruta(
  id: 'r-sin-bidones',
  vendedorId: 'v-01',
  nombreVendedor: 'Vendedor',
  fecha: DateTime(2026, 6, 1),
  montoTotal: 0,
  montoCobrado: 0,
  estado: EstadoRuta.pendiente,
  creadoEn: DateTime(2026, 6, 1),
);

bool sinAlertaStock(Producto p) => !p.esCritico && !p.esBajo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = ServicioAutenticacion();
  final casos = <CasoVerificacion>[
    CasoVerificacion(
      'PAVF_001_HU_01_V01',
      'HU-01',
      'Aceptar contraseña segura',
      () => auth.esContrasenaValida('Agua2026!'),
    ),
    CasoVerificacion(
      'PAVF_002_HU_01_V02',
      'HU-01',
      'Rechazar contraseña corta',
      () => !auth.esContrasenaValida('A1!'),
    ),
    CasoVerificacion(
      'PAVF_003_HU_01_V03',
      'HU-01',
      'Rechazar contraseña sin número',
      () => !auth.esContrasenaValida('AguaMilena!'),
    ),
    CasoVerificacion(
      'PAVF_004_HU_01_V04',
      'HU-01',
      'Rechazar contraseña sin carácter especial',
      () => !auth.esContrasenaValida('AguaMilena2026'),
    ),
    CasoVerificacion(
      'PAVF_005_HU_01_V05',
      'HU-01',
      'Validar hash con contraseña correcta',
      () => verificaHashCorrecto(auth),
    ),
    CasoVerificacion(
      'PAVF_006_HU_01_V06',
      'HU-01',
      'Rechazar hash con contraseña incorrecta',
      () => verificaHashIncorrecto(auth),
    ),
    CasoVerificacion(
      'PAVF_007_HU_01_V07',
      'HU-01',
      'Rechazar hash mal formado',
      () => !auth.verificarContrasena('Agua2026!', 'hash-invalido'),
    ),
    CasoVerificacion(
      'PAVF_011_HU_02_V01',
      'HU-02',
      'Convertir texto administrador a rol admin',
      () => RolUsuario.desdeTexto('administrador') == RolUsuario.admin,
    ),
    CasoVerificacion(
      'PAVF_012_HU_02_V02',
      'HU-02',
      'Convertir texto planta a rol planta',
      () => RolUsuario.desdeTexto('planta') == RolUsuario.planta,
    ),
    CasoVerificacion(
      'PAVF_013_HU_02_V03',
      'HU-02',
      'Convertir texto vendedor a rol vendedor',
      () => RolUsuario.desdeTexto('vendedor') == RolUsuario.vendedor,
    ),
    CasoVerificacion(
      'PAVF_014_HU_02_V04',
      'HU-02',
      'Rechazar rol inexistente',
      () => lanzaRolInvalido(),
    ),
    CasoVerificacion(
      'PAVF_015_HU_02_V05',
      'HU-02',
      'Crear usuario desde JSON en español',
      () =>
          usuarioDesdeJsonEspanol().rol == RolUsuario.admin &&
          usuarioDesdeJsonEspanol().nombre == 'Administrador',
    ),
    CasoVerificacion(
      'PAVF_016_HU_02_V06',
      'HU-02',
      'Crear usuario desde JSON en inglés',
      () =>
          usuarioDesdeJsonIngles().rol == RolUsuario.planta &&
          usuarioDesdeJsonIngles().nombre == 'Planta',
    ),
    CasoVerificacion(
      'PAVF_017_HU_02_V07',
      'HU-02',
      'Serializar usuario a JSON',
      () =>
          usuarioAdmin().aJson()['role'] == 'admin' &&
          usuarioAdmin().aJson()['name'] == 'Administrador',
    ),
    CasoVerificacion(
      'PAVF_018_HU_02_V08',
      'HU-02',
      'Limpiar asociación de vendedor al cambiar rol',
      () =>
          usuarioVendedor()
              .copiarCon(rol: RolUsuario.planta, limpiarVendedorId: true)
              .vendedorId ==
          null,
    ),
    CasoVerificacion(
      'PAVF_022_HU_03_V01',
      'HU-03',
      'Aceptar nueva contraseña segura',
      () => auth.esContrasenaValida('Nueva2026!'),
    ),
    CasoVerificacion(
      'PAVF_023_HU_03_V02',
      'HU-03',
      'Bloquear nueva contraseña corta',
      () => !auth.esContrasenaValida('N1!'),
    ),
    CasoVerificacion(
      'PAVF_037_HU_05_V01',
      'HU-05',
      'Crear producto desde JSON válido',
      () => productoBase(stock: 20, minimo: 5).nombre == 'Bidón de agua',
    ),
    CasoVerificacion(
      'PAVF_038_HU_05_V02',
      'HU-05',
      'Serializar producto para guardar',
      () =>
          productoBase(stock: 20, minimo: 5).aJson()['stock'] == 20 &&
          productoBase(stock: 20, minimo: 5).aJson()['stock_minimo'] == 5,
    ),
    CasoVerificacion(
      'PAVF_039_HU_05_V03',
      'HU-05',
      'Clasificar stock crítico',
      () => productoBase(stock: 5, minimo: 5).esCritico,
    ),
    CasoVerificacion(
      'PAVF_040_HU_05_V04',
      'HU-05',
      'Clasificar stock bajo no crítico',
      () =>
          productoBase(stock: 7, minimo: 5, bajo: 8).esBajo &&
          !productoBase(stock: 7, minimo: 5, bajo: 8).esCritico,
    ),
    CasoVerificacion(
      'PAVF_041_HU_05_V05',
      'HU-05',
      'No alertar stock suficiente',
      () =>
          !productoBase(stock: 20, minimo: 5, bajo: 8).esCritico &&
          !productoBase(stock: 20, minimo: 5, bajo: 8).esBajo,
    ),
    CasoVerificacion(
      'PAVF_045_HU_05_V09',
      'HU-05',
      'Aceptar catálogo vendedor',
      () =>
          productoBase(stock: 10, minimo: 2, catalogo: 'vendedor').catalogo ==
          CatalogoProducto.vendedor,
    ),
    CasoVerificacion(
      'PAVF_046_HU_05_V10',
      'HU-05',
      'Copiar producto actualizando valores',
      () =>
          productoBase(
            stock: 20,
            minimo: 5,
          ).copiarCon(precio: 2.0, stock: 30, stockMinimo: 10).stock ==
          30,
    ),
    CasoVerificacion(
      'PAVF_056_HU_07_V01',
      'HU-07',
      'Calcular subtotal de item',
      () => itemCarrito('Bidón de agua', 1.5, 4).subtotal == 6.0,
    ),
    CasoVerificacion(
      'PAVF_062_HU_07_V07',
      'HU-07',
      'Identificar bidón sin tilde',
      () => itemCarrito('Bidon de agua', 1.5, 1).esBidon,
    ),
    CasoVerificacion(
      'PAVF_063_HU_07_V08',
      'HU-07',
      'Identificar bidón con tilde',
      () => itemCarrito('Bidón retornable', 1.5, 1).esBidon,
    ),
    CasoVerificacion(
      'PAVF_064_HU_07_V09',
      'HU-07',
      'No identificar funda como bidón',
      () => !itemCarrito('Funda de agua', 0.25, 1).esBidon,
    ),
    CasoVerificacion(
      'PAVF_065_HU_07_V10',
      'HU-07',
      'Convertir carrito a item de venta JSON',
      () =>
          itemCarrito('Bidón', 1.5, 3).aJsonItemVenta('venta-01')['subtotal'] ==
          4.5,
    ),
    CasoVerificacion(
      'PAVF_074_HU_09_V01',
      'HU-09',
      'Convertir estado pendiente',
      () => EstadoRutaExt.desdeTexto('pendiente') == EstadoRuta.pendiente,
    ),
    CasoVerificacion(
      'PAVF_075_HU_09_V02',
      'HU-09',
      'Convertir estado parcial',
      () => EstadoRutaExt.desdeTexto('parcial') == EstadoRuta.parcial,
    ),
    CasoVerificacion(
      'PAVF_076_HU_09_V03',
      'HU-09',
      'Convertir estado pagado',
      () => EstadoRutaExt.desdeTexto('pagado') == EstadoRuta.pagado,
    ),
    CasoVerificacion(
      'PAVF_077_HU_09_V04',
      'HU-09',
      'Asignar sin cierre ante estado desconocido',
      () => EstadoRutaExt.desdeTexto('desconocido') == EstadoRuta.sinCierre,
    ),
    CasoVerificacion(
      'PAVF_078_HU_09_V05',
      'HU-09',
      'Mostrar etiqueta de ruta parcial',
      () => EstadoRuta.parcial.etiqueta == 'Abono parcial',
    ),
    CasoVerificacion(
      'PAVF_079_HU_09_V06',
      'HU-09',
      'Calcular total de productos de salida',
      () => rutaConItemsAbierta().totalProductosSalida == 15,
    ),
    CasoVerificacion(
      'PAVF_080_HU_09_V07',
      'HU-09',
      'Identificar ruta cerrada',
      () => rutaCerrada().estaCerrada,
    ),
    CasoVerificacion(
      'PAVF_081_HU_09_V08',
      'HU-09',
      'Identificar ruta abierta',
      () => !rutaConItemsAbierta().estaCerrada,
    ),
    CasoVerificacion(
      'PAVF_084_HU_10_V01',
      'HU-10',
      'Calcular saldo pendiente parcial',
      () => rutaSaldoParcial().saldoPendienteVisible == 60,
    ),
    CasoVerificacion(
      'PAVF_085_HU_10_V02',
      'HU-10',
      'Marcar pagado con abono total',
      () =>
          rutaPagada().estado == EstadoRuta.pagado &&
          rutaPagada().saldoPendienteVisible == 0,
    ),
    CasoVerificacion(
      'PAVF_089_HU_10_V06',
      'HU-10',
      'Gestionar excedente como saldo a favor',
      () =>
          rutaConSaldoAFavor().tieneSaldoAFavor &&
          rutaConSaldoAFavor().saldoAFavor == 30,
    ),
    CasoVerificacion(
      'PAVF_093_HU_11_V01',
      'HU-11',
      'Calcular bidones vendidos',
      () => rutaBidones().bidonesVendidos == 7,
    ),
    CasoVerificacion(
      'PAVF_094_HU_11_V02',
      'HU-11',
      'Calcular bidones llenos finales',
      () => rutaBidones().bidonesLlenosFinales == 3,
    ),
    CasoVerificacion(
      'PAVF_095_HU_11_V03',
      'HU-11',
      'Calcular bidones vacíos finales',
      () => rutaBidones().bidonesVaciosFinales == 9,
    ),
    CasoVerificacion(
      'PAVF_096_HU_11_V04',
      'HU-11',
      'Calcular prestados iniciales',
      () => rutaBidones().bidonesPrestadosIniciales == 3,
    ),
    CasoVerificacion(
      'PAVF_097_HU_11_V05',
      'HU-11',
      'Calcular prestados finales',
      () => rutaBidones().bidonesPrestadosFinales == 7,
    ),
    CasoVerificacion(
      'PAVF_098_HU_11_V06',
      'HU-11',
      'Evitar llenos finales negativos',
      () => rutaBidonesNegativos().bidonesLlenosFinales == 0,
    ),
    CasoVerificacion(
      'PAVF_099_HU_11_V07',
      'HU-11',
      'Identificar ruta sin bidones',
      () => !rutaSinBidones().tieneBidones,
    ),
    CasoVerificacion(
      'PAVF_100_HU_11_V08',
      'HU-11',
      'Calcular faltantes de retorno',
      () => itemRutaCerrado().faltantes == 2,
    ),
    CasoVerificacion(
      'PAVF_101_HU_12_V01',
      'HU-12',
      'Detectar stock crítico',
      () => productoBase(stock: 2, minimo: 5).esCritico,
    ),
    CasoVerificacion(
      'PAVF_102_HU_12_V02',
      'HU-12',
      'Detectar stock bajo preventivo',
      () => productoBase(stock: 7, minimo: 5, bajo: 8).esBajo,
    ),
    CasoVerificacion(
      'PAVF_103_HU_12_V03',
      'HU-12',
      'No alertar stock suficiente',
      () => sinAlertaStock(productoBase(stock: 30, minimo: 5, bajo: 8)),
    ),
    CasoVerificacion(
      'PAVF_104_HU_12_V04',
      'HU-12',
      'Detectar cobro pendiente',
      () => rutaSaldoParcial().saldoPendienteVisible > 0,
    ),
    CasoVerificacion(
      'PAVF_105_HU_12_V05',
      'HU-12',
      'Detectar saldo a favor',
      () => rutaConSaldoAFavor().tieneSaldoAFavor,
    ),
  ];
  for (final caso in casos) {
    test('${caso.codigo} - ${caso.nombre}', () {
      expect(caso.ejecutar(), isTrue);
    });
  }
}
