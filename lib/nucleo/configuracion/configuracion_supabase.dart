// Configuracion de Supabase cargada por variables de compilacion.

class SupabaseConfig {
  SupabaseConfig._();

  static const String _urlPorDefecto =
      'https://PROYECTO.supabase.co';
  static const String _anonKeyPorDefecto =
      'CONFIGURAR_LOCALMENTE';

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _urlPorDefecto,
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _anonKeyPorDefecto,
  );

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
