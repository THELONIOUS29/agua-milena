import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../datos/modelos/vendedor.dart';
import '../../datos/servicios/servicio_configuracion_bidones.dart';
import 'proveedor_vendedor.dart';

class ResumenBidones {
  final int totalEmpresa;
  final int bidonesConVendedores;
  final int bidonesPrestados;
  final int bidonesLlenosConVendedores;
  final int bidonesVaciosConVendedores;
  final int bidonesEnPlanta;
  final int bidonesFaltantes;

  const ResumenBidones({
    required this.totalEmpresa,
    required this.bidonesConVendedores,
    required this.bidonesPrestados,
    required this.bidonesLlenosConVendedores,
    required this.bidonesVaciosConVendedores,
    required this.bidonesEnPlanta,
    required this.bidonesFaltantes,
  });
}

final proveedorServicioConfigBidones = Provider<ServicioConfiguracionBidones>(
  (ref) => ServicioConfiguracionBidones(),
);
final proveedorTotalBidonesEmpresa = FutureProvider<int>(
  (ref) async =>
      ref.watch(proveedorServicioConfigBidones).obtenerTotalBidonesEmpresa(),
);

final proveedorResumenBidones = Provider<AsyncValue<ResumenBidones>>((ref) {
  final vendedoresAsync = ref.watch(proveedorNotificadorVendedor);
  final totalAsync = ref.watch(proveedorTotalBidonesEmpresa);
  if (vendedoresAsync.isLoading || totalAsync.isLoading) {
    return const AsyncLoading();
  }
  if (vendedoresAsync.hasError) {
    return AsyncError(
      vendedoresAsync.error!,
      vendedoresAsync.stackTrace ?? StackTrace.current,
    );
  }
  if (totalAsync.hasError) {
    return AsyncError(
      totalAsync.error!,
      totalAsync.stackTrace ?? StackTrace.current,
    );
  }

  final vendedores = vendedoresAsync.asData?.value ?? const <Vendedor>[];
  final totalEmpresa = totalAsync.asData?.value ?? 0;
  final llenos = vendedores.fold<int>(0, (s, v) => s + v.bidonesLlenosActuales);
  final vacios = vendedores.fold<int>(0, (s, v) => s + v.bidonesVaciosActuales);
  final prestados = vendedores.fold<int>(0, (s, v) => s + v.bidonesPrestados);
  final conVendedores = llenos + vacios;
  final enPlanta = totalEmpresa - conVendedores;

  return AsyncData(
    ResumenBidones(
      totalEmpresa: totalEmpresa,
      bidonesConVendedores: conVendedores,
      bidonesPrestados: prestados,
      bidonesLlenosConVendedores: llenos,
      bidonesVaciosConVendedores: vacios,
      bidonesEnPlanta: enPlanta > 0 ? enPlanta : 0,
      bidonesFaltantes: enPlanta < 0 ? enPlanta.abs() : 0,
    ),
  );
});
