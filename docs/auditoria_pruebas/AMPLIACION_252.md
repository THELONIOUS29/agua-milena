# Ampliación a 252 pruebas automatizadas

Ejecución del **26/10/2026**. Se añadieron **61 pruebas nuevas** que llaman al código real de la aplicación, sin modificar producción en esta ampliación.

| Resultado Flutter | Cantidad |
|---|---:|
| Aprobadas | **252** |
| Fallidas | **0** |
| Omitidas, fuera de las aprobadas | **5** |
| Registradas en toda la suite | **257** |

Las aprobadas son 244 unitarias y ocho de widgets. Incluyen cinco comprobaciones de soporte (utilidad de calendario, dos componentes visuales y dos de versiones). No se presentan las 252 como 252 aceptaciones completas de extremo a extremo. Las cuatro integraciones Supabase y la inferencia nativa continúan pendientes; el intento nativo anterior falló por la DLL ausente.

Además existen 21 casos SQL aislados y nueve Edge aprobados en la revisión anterior. Se mantienen aparte: **no se usaron para completar las 252 Flutter**.

Las 61 nuevas comprobaciones están en [ampliacion_cobertura_real_test.dart](../../test/ampliacion_cobertura_real_test.dart):

| Módulo de la ampliación | Casos nuevos |
|---|---:|
| Autenticación y usuarios: cifrado de sesión | 8 |
| Inventario | 13 |
| Ventas | 10 |
| Vendedores y rutas | 10 |
| Alertas y respaldo estadístico | 10 |
| Reportes | 10 |
| Total añadido | **61** |

Se ejecutan métodos reales de cifrado, servicios de productos/ventas/rutas, agregación de saldos y totales, filtros, generación de PDF, revisión concurrente de alertas y estimación estadística. Se sustituyen solo el transporte HTTP, almacenamiento del dispositivo y push. Eso permite comprobar la lógica local y el contrato de las solicitudes; no demuestra persistencia ni permisos de una instancia Supabase real.

El registro inicial de estos casos tuvo cinco fallos de expectativas del formato HTTP; quedaron corregidos y los 61 aprobaron en la ejecución completa posterior. La salida definitiva es `flutter_final.jsonl`, con `success: true`. El análisis terminó con cero errores, cero advertencias y cuatro avisos informativos preexistentes.

El total coincide ahora con **252 pruebas automatizadas aprobadas**. El reparto real todavía es distinto de la tabla de la tesis. Se clasifica cada caso por su método/requisito principal, con el motivo en `distribucion_actual.csv`:

| Módulo | Tabla entregada | Pruebas actuales clasificadas |
|---|---:|---:|
| Autenticación y usuarios | 45 | 62 |
| Inventario | 35 | 41 |
| Ventas | 48 | 38 |
| Vendedores y rutas | 60 | 64 |
| Alertas | 42 | 29 |
| Reportes | 22 | 13 |
| Soporte fuera de esos módulos | — | 5 |
| Total | **252** | **252** |

No se cambiaron categorías para hacer coincidir esa tabla. Para respaldar lo ya entregado, esta ejecución puede acompañarse como evidencia complementaria con su fecha real; la relación exacta con la matriz original de la tesis sigue pendiente de reconciliación.

Archivos de evidencia:

- `matriz_pruebas.csv`: 287 filas únicas, incluidas 257 Flutter registradas, 21 SQL y nueve Edge.
- `catalogo_ampliacion.json`: código, descripción y método de los 61 casos nuevos.
- `resumen_final.json`: conteos obtenidos del registro de ejecución.
- `flutter_final.jsonl`: ejecución completa real, 252 aprobadas y cinco omitidas.
- `analisis_final.txt`: análisis estático.
- `INFORME.md`: detalle de alcance, defectos corregidos previamente y limitaciones.
- `historial_191/`: evidencia anterior, conservada para no ocultar la evolución.

Comandos utilizados:

```powershell
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot test --reporter json --concurrency 1 --no-pub
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib test
python scripts/generar_matriz_pruebas.py
```

No se modificó la tesis, no se utilizaron datos reales de la empresa y no se hizo push.
