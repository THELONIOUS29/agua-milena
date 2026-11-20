# Checklist de produccion v1.0.2+2004

## Supabase

Ejecuta los SQL en este orden desde Supabase Dashboard > SQL Editor:

1. `supabase/parche_hardening_operaciones_v1_0_2.sql`
2. `supabase/parche_rls_storage_sesion_v1_0_2.sql`
3. `supabase/validar_hardening_v1_0_2.sql`

El tercer archivo debe devolver `ok = true` en todos los chequeos. Si
`credenciales_admin_semilla` devuelve `ok = false`, cambia la clave del usuario
admin antes de entregar produccion.

El parche RLS depende de que la app envie el header
`x-agua-milena-session`. La version actual ya lo aplica cuando guarda o restaura
una sesion local.

## Firma Android real

El repositorio no debe guardar keystores ni contrasenas reales. Para firmar:

1. Crea una carpeta local `android/release`.
2. Genera el keystore:

```powershell
keytool -genkeypair -v `
  -keystore android/release/agua_milena_release.jks `
  -keyalg RSA -keysize 2048 -validity 10000 `
  -alias agua_milena_release
```

3. Copia `android/key.properties.example` a `android/key.properties`.
4. Rellena `storePassword`, `keyPassword`, `keyAlias` y `storeFile`.
5. Compila el release:

```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL=<tu-url> `
  --dart-define=SUPABASE_ANON_KEY=<tu-anon-key>
```

`android/key.properties`, `*.jks` y `*.keystore` ya estan ignorados por Git.

## Validacion final

Antes de distribuir:

- `flutter analyze`
- `flutter test`
- `flutter build apk --release --dart-define=SUPABASE_URL=<tu-url> --dart-define=SUPABASE_ANON_KEY=<tu-anon-key>`
- Login con admin real, crear una venta, registrar movimiento de inventario,
  subir avatar y subir imagen de producto.
- Ejecutar otra vez `supabase/validar_hardening_v1_0_2.sql`.
