import 'package:supabase_flutter/supabase_flutter.dart';

class ServicioConfiguracionBidones {
  final _client = Supabase.instance.client;
  static const _esquema = 'inventario';
  static const _tabla = 'configuracion_app';
  static const _claveTotalBidones = 'total_bidones_empresa';

  SupabaseQueryBuilder _desde(String tabla) =>
      _client.schema(_esquema).from(tabla);

  Future<int> obtenerTotalBidonesEmpresa() async {
    final data = await _desde(
      _tabla,
    ).select('valor_json').eq('clave', _claveTotalBidones).maybeSingle();
    if (data == null) return 0;
    final valorJson = data['valor_json'];
    if (valorJson is Map<String, dynamic>) {
      return valorJson['total'] as int? ?? 0;
    }
    return 0;
  }

  Future<void> establecerTotalBidonesEmpresa(int total) async {
    await _desde(_tabla).upsert({
      'clave': _claveTotalBidones,
      'valor_json': {'total': total},
      'actualizado_en': DateTime.now().toIso8601String(),
    });
  }
}
