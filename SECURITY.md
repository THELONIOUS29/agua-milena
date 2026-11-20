
# Configuración y credenciales

No se incluyen claves de Supabase, tokens, claves privadas, archivos de firma ni configuraciones de Firebase del negocio. La configuración de ejemplo está vacía y los archivos locales están excluidos de Git.

Para Flutter, completar `config/runtime.local.json` a partir del ejemplo y ejecutar `flutter run --dart-define-from-file=config/runtime.local.json`. Usar exclusivamente una clave de cliente anon/publishable. Las claves de servidor/service_role y claves de cifrado nunca se incluyen en el cliente ni en el APK.

Para Firebase Android/iOS, suministrar localmente los archivos de proveedor correspondientes. Para web, completar `web/firebase-config.local.js` a partir del ejemplo; no incorporarlo al repositorio. La API key de Flutter web se suministra con FIREBASE_API_KEY en el archivo local de compilación. La clave VAPID se suministra con FIREBASE_VAPID_KEY.

El historial de las ramas y etiquetas se saneó el 20 de noviembre de 2026. Las credenciales que hubieran sido utilizadas deben revocarse o rotarse en el proveedor; borrar texto de Git no las invalida. Si una clave cifra datos existentes, conservar su acceso en un gestor privado y realizar una migración controlada antes de retirarla.

Después de esta limpieza, volver a clonar el repositorio para colaborar. No fusionar ni subir ramas antiguas: podrían reintroducir las claves. Las aplicaciones desplegadas y las bases reales no fueron modificadas ni certificadas por esta revisión.
