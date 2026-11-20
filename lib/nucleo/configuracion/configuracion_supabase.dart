// Los valores se suministran en un archivo local excluido de Git.
class SupabaseConfig {
  SupabaseConfig._();
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get isConfigured =>
      url.startsWith('https://') &&
      !url.contains('PROYECTO') &&
      anonKey.isNotEmpty &&
      !anonKey.startsWith('sb_secret_') &&
      !anonKey.startsWith('CONFIGURAR_');
}
