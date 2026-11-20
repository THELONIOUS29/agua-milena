# Agua Milena

Aplicación Flutter y Supabase para ventas, inventario, rutas y gestión de una distribuidora de agua.

## Sobre esta copia

Instantánea preparada el 20 de noviembre de 2026 para organizar un portafolio profesional. Repositorio privado. No incluye el historial Git original.

Se omitieron configuraciones locales, credenciales, datos operativos, instalaciones y archivos generados. Los valores `CONFIGURAR_LOCALMENTE`, `CONFIGURAR_TOKEN_LOCALMENTE` y `CONFIGURAR_SECRETO_LOCALMENTE` deben reemplazarse mediante configuración local antes de ejecutar. En scripts SQL se omitieron bloques de datos `INSERT` y `COPY`; en notebooks se borraron salidas guardadas.

El respaldo no constituye una validación de funcionamiento: no se ejecutaron los programas ni sus suites de pruebas durante esta preparación. Dependencias, recursos y configuración pueden requerir restauración. No se añade una licencia nueva ni se atribuyen en exclusiva los trabajos grupales o sus dependencias.

## Documentación del proyecto original

# Agua Milena App 💧

Aplicación móvil de gestión integral para la distribución de agua purificada **Agua Milena**, desarrollada con **Flutter** y **Supabase**.

## Características principales

- **Panel de control** con estadísticas en tiempo real
- **Gestión de inventario** de productos (garrafones, paquetes, etc.)
- **Control de ventas** con detalle por vendedor
- **Gestión de rutas** de distribución
- **Sistema de alertas** inteligente con modelo TensorFlow Lite
- **Administración de usuarios** con roles (administrador, vendedor, planta)
- **Control de bidones** (propios y de empresa)
- **Reportes PDF** con filtros por vendedor y rango de fechas
- **Seguridad avanzada**: cifrado PII, RBAC, autenticación biométrica MFA
- **Auditoría** de todas las operaciones

## Arquitectura

```
lib/
├── datos/           # Capa de datos (servicios, modelos)
│   ├── modelos/     # Modelos de datos (Dart)
│   └── servicios/   # Servicios de acceso a Supabase
├── dominio/         # Capa de dominio
│   ├── entidades/   # Entidades de negocio
│   └── repositorios/ # Interfaces de repositorios
├── nucleo/          # Configuración central
│   ├── configuracion/
│   ├── constantes/
│   ├── enrutador/
│   └── tema/
├── presentacion/    # Capa de presentación
│   ├── componentes/ # Widgets reutilizables
│   ├── pantallas/   # Pantallas de la app
│   └── proveedores/ # State management (Riverpod)
└── main.dart
```

## Tecnologías

| Tecnología | Uso |
|---|---|
| Flutter 3.x | Framework UI multiplataforma |
| Dart | Lenguaje de programación |
| Supabase | Backend (PostgreSQL, Auth, RPC) |
| Riverpod | Estado reactivo |
| GoRouter | Navegación declarativa |
| TensorFlow Lite | Modelo predictivo de alertas |
| Google Fonts | Tipografía (Outfit) |

## Base de datos

El esquema completo de la base de datos se encuentra en:
```
supabase/base_datos_completa_agua_milena.sql
```

Incluye schemas: `inventario`, `ventas`, `vendedores`, `rutas`, `auditoria`, `usuarios`, y funciones RPC para operaciones seguras.

Para preparar la version `1.0.2+2004` en produccion, sigue el checklist en:
```
docs/PRODUCCION_1_0_2.md
```

## Configuración

1. Clonar el repositorio
2. Ejecutar `flutter pub get`
3. Ejecutar con `--dart-define=SUPABASE_URL=<tu-url> --dart-define=SUPABASE_ANON_KEY=<tu-anon-key>`
4. Ejecutar el SQL de `supabase/base_datos_completa_agua_milena.sql` en tu proyecto Supabase
5. `flutter run`

## Licencia

Proyecto académico — Universidad. Todos los derechos reservados.
