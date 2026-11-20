import 'package:supabase_flutter/supabase_flutter.dart';
import 'servicio_info_dispositivo.dart';

/// Servicio de auditoría que complementa los triggers de PostgreSQL
class ServicioAuditoria {
  final _client = Supabase.instance.client;
  static const _esquema = 'auditoria';

  SupabaseQueryBuilder _desde(String tabla) =>
      _client.schema(_esquema).from(tabla);

  Future<void> enriquecerUltimoLog({
    required String tabla,
    required String registroId,
    String? usuarioId,
    String? usuarioEmail,
  }) async {
    try {
      final device = ServicioInfoDispositivo.instance;
      final logs = await _desde('log_auditoria')
          .select('id')
          .eq('tabla', tabla)
          .eq('registro_id', registroId)
          .order('creado_en', ascending: false)
          .limit(1);

      if ((logs as List).isNotEmpty) {
        final logId = logs[0]['id'] as String;
        await _desde('log_auditoria')
            .update({
              'usuario_id': usuarioId,
              'usuario_email': usuarioEmail,
              'dispositivo': device.nombreDispositivo,
              'version_app': device.versionApp,
            })
            .eq('id', logId);
      }
    } catch (_) {}
  }
}
