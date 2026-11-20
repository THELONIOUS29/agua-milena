# Auditoría de pruebas de Agua Milena

Actualización del 26/10/2026: se añadieron 61 casos nuevos y se volvió a ejecutar la suite completa. El resultado actual es **252 aprobadas Flutter y cinco integraciones omitidas aparte**. La evidencia de la revisión anterior, de 191 aprobadas, se conserva en `historial_191/`. Estas evidencias tienen la fecha real de su ejecución; no se atribuyen a la fecha de entrega de la tesis.

Se corrigieron las pruebas en el proyecto y se ejecutó código de producción sin acceder a datos de la empresa. No se modificaron documentos Word, no se hicieron commits, publicaciones ni push. Se respetaron los cambios que ya existían en el directorio al comenzar. No se encontraron archivos AGENTS.md en el proyecto ni en sus directorios ascendentes consultados; se leyó README.md y la implementación Dart, SQL y Edge pertinente.

**Resultado reproducible**

| Ejecución | Aprobadas | Fallidas | Omitidas/no ejecutadas |
|---|---:|---:|---:|
| Flutter final, suite completa | 252 | 0 | 5 |
| SQL real en PGlite efímero, casos identificados | 21 | 0 | 0 |
| Función Edge real, transporte y entorno sustituidos | 9 | 0 | 0 |
| Intento explícito del intérprete nativo TFLite | 0 | 1 por infraestructura | 0 |

Las 252 aprobadas Flutter comprenden 244 unitarias y 8 de widgets. Las cinco omitidas son cuatro integraciones Supabase y una integración nativa. El caso nativo tiene además un intento explícito fallido, registrado en `modelo_nativo_intento.jsonl`: falta `libtensorflowlite_c-win.dll` (error 126). No se cuenta como aprobado ni se oculta ese intento al indicar que la suite normal lo omite.

Los 21 casos SQL y 9 Edge pertenecen a ejecutores distintos; no se suman a Flutter para afirmar cobertura independiente de requisitos ni para reproducir los 252 de la tesis. El verificador SQL preexistente también se ejecutó y terminó correctamente; se conserva su salida en `sql_existente.txt`, sin convertir cada assert de ese script en una prueba adicional.

**Archivos para revisar**

- `matriz_pruebas.csv`: 287 filas, una por caso registrado final (257 Flutter, 21 SQL y 9 Edge), con código, requisito relacionado, módulo, tipo, producción verificada, expectativa y ejecución. La prueba nativa tiene su intento fallido anotado en su misma fila.
- `catalogo_ampliacion.json`: los 61 casos nuevos con identificador, expectativa y método real.
- `distribucion_actual.csv`: clasificación de las pruebas aprobadas por módulo, sin ajustar los resultados a la tabla.
- `revision_caso_por_caso.csv`: las 378 comprobaciones funcionales previas, su expresión, auxiliares locales, decisión, repetición exacta y familia de sustitución o pendiente. Las familias de sustitución NO implican equivalencia uno a uno.
- `revision_inicial.csv`, `original.dart.txt` y `ampliado.dart.txt`: evidencia anterior a la corrección. No son archivos ejecutables de prueba.
- `requisitos_manual.csv`, `aceptacion_manual.csv`, `tablas_fuente.json` y `documentos_consultados.json`: trazabilidad documental y sus límites.
- `flutter_inicial.jsonl`, `flutter_final.jsonl`, `sql_casos.json`, `edge_casos.json`, `resumen_final.json`, `analisis_final.txt`: resultados y evidencia verificable.

**Conteo inicial y deduplicación**

Flutter registró 126 casos en `verificacion_funcional_test.dart` y 253 en el ampliado: 252 escenarios funcionales y una prueba auxiliar sobre la estructura de la matriz. Los ciclos que llaman a `test()` sí registran pruebas individuales. Importar el archivo original desde el ampliado no ejecuta su `main()`: la suite ampliada registró 253, no 379. Al ejecutar ambos archivos hubo 379 registros, 378 funcionales más uno auxiliar. La aserción `casos.length == 126` estaba dentro de cada caso del original; no era otra prueba registrada.

El inventario previo tenía 63 bloques RFV con exactamente cuatro escenarios cada uno. La prueba auxiliar decía «4 o 5» y permitía ambos valores, pero los datos reales eran cuatro. No se conserva una aserción artificial que obligue a mantener 63 bloques o 252 escenarios.

De las 378 comprobaciones previas:

- Se conservaron 106: 53 del original y 53 del ampliado. Se reemplazaron además dos expresiones inline por getters reales de ItemRuta. Incluyen llamadas a métodos/modelos de producción y auxiliares que solo construyen datos o consultan esos modelos.
- Se retiraron 221 que decidían reglas dentro de `test/` o comprobaban únicamente el SDK/fixture, sin ejecutar la implementación que afirmaban validar: 73 del original y 148 del ampliado.
- Se consolidaron 49 repeticiones: 47 de expresiones normalizadas y dos detectadas después de sustituir aserciones permisivas por comprobaciones exactas. De ellas, 47 repiten casos del original y dos repiten expresiones dentro del ampliado. Es una consolidación documentada de comprobaciones, no una afirmación de que las restantes sean requisitos independientes. Variantes de datos o aserciones sobre el mismo getter pueden seguir compartiendo cobertura.
- Se eliminó una prueba auxiliar de estructura. Se quitó la lógica que infería la unidad en el fixture del carrito: ahora las pruebas de identificación de bidón dependen del nombre y del método real, sin que una unidad prefijada oculte errores.
- Se añadieron 114 pruebas Flutter ejecutadas: 53 durante la depuración (44 de servicios y nueve de permisos) y 61 en esta ampliación. También se prepararon cinco integraciones condicionadas y se ejecutaron 21 casos SQL y nueve Edge en la revisión anterior. Los ejecutores SQL/Edge no se repitieron ahora porque sus fuentes no cambiaron; sus resultados se mantienen separados de las 252 Flutter. Las otras 30 pruebas Flutter que ya existían se conservaron y ejecutaron.

Identidades: 378 - 221 - 49 = 108 (106 conservadas y dos reemplazadas); 108 + 114 + 30 = 252 aprobadas Flutter; 252 + 5 omitidas = 257 registradas. Los dos archivos principales contienen finalmente 53 + 55 = 108 casos, todos aprobados. No se sustituyeron todos los 221 casos locales por aceptaciones equivalentes completas: los huecos están marcados como pendientes o cobertura parcial en los CSV.

**Ampliación de cobertura hasta 252 aprobadas**

Los 61 casos nuevos están en `test/ampliacion_cobertura_real_test.dart`: ocho de cifrado y compatibilidad de sesión, trece de inventario, diez de ventas, diez de rutas/abonos, diez de alertas/predicciones y diez de reportes. No se añadieron nuevas reglas a `lib/` en esta ampliación. Cada caso llama a métodos existentes; el registro `caso(...)` solo asigna código/nombre y llama a `test()`.

La ampliación comprueba AES-GCM real (Unicode, IV aleatorio, reutilización de clave, manipulación y clave incorrecta), consultas/altas/ediciones y transporte de imágenes de inventario, agregación real del total diario y saldos, ramas de respuesta del RPC de ventas, validaciones de importes/bidones, filtros y respaldo real del resumen de reportes, generación real de PDF vacío, consultas/abonos anidados de rutas, liberación del bloqueo de revisión de alertas tras errores, exclusión de revisiones simultáneas y ausencia de fuga de ventas futuras en el respaldo estadístico. El almacenamiento seguro del dispositivo, HTTP y push siguen sustituidos: esto no certifica Keystore, persistencia Supabase ni Firebase.

En la primera ejecución de la ampliación pasaron 56 y fallaron cinco expectativas del formato de transporte. Se ajustaron a la implementación instalada: orden PostgREST con `nullslast` y subida de imágenes multipart con los bytes/MIME dentro de la parte del archivo. Se conserva esa salida en `flutter_ampliacion_intento1.jsonl`. Después se ejecutó la suite completa y aprobaron los 61 casos nuevos y los 191 anteriores, sin cambiar la lógica de producción ni las expectativas de negocio.

**Qué verifica realmente el trabajo**

Ventas: el carrito real calcula cantidades, total y crédito por devoluciones. El servicio real construye el RPC y deserializa la respuesta, propaga el rechazo por stock y evita escrituras alternativas ante falta de sesión/RPC o respuesta inválida. El transporte guionado devuelve datos fijos: NO calcula stock, totales, permisos ni transacciones. La evidencia de total, descuento de stock y ausencia de cambios parciales proviene de ejecutar `fn_crear_venta_segura` en PGlite con tablas reales. Incluye un primer producto válido y un segundo sin stock. Se comparan ventas, items, productos, movimientos, rutas y vendedores antes y después del fallo, sin que el test haga rollback para conseguir la igualdad. Cada llamada SQL se ejecuta en autocommit en el motor efímero. No demuestra concurrencia entre sesiones, recuperación ante pérdida de red ni despliegue en Supabase.

Inventario: se ejecutan `ServicioProducto.registrarMovimiento` y el RPC real de movimientos. Se verifican entradas, salidas, historial, tipo inválido, cantidad cero/negativa, stock insuficiente y rol vendedor. El servicio ahora rechaza entradas inválidas antes de cualquier dependencia externa, y bloquea caminos sin sesión o sin RPC seguro.

Permisos: las pruebas llaman a la función que usa `GoRouter.redirect`, extraída sin cambiar sus decisiones, y a los notificadores reales de ventas/rutas. Los dobles de los servicios de esas pruebas solo registran llamadas; no deciden permisos. Las funciones SQL verifican sesiones/roles reales dentro de PGlite. Nada de ello certifica políticas RLS, grants o seguridad de un despliegue Supabase. Los cuatro casos de integración Supabase quedan preparados y omitidos.

Rutas, abonos y bidones: se conservan getters y serialización reales; los pagos parciales/completos ejecutados en SQL cambian monto y estado reales en el motor aislado. Se prueba rechazo de importes no positivos/no finitos en `registrarAbono`, y los permisos de invocación de los notificadores. Los modelos construidos directamente con estado pagado/parcial solo prueban conservación de ese dato y sus cálculos; no prueban que un cierre o abono se haya persistido. El cierre completo con retornos/bidones y sus efectos de servidor queda pendiente de integración completa.

Alertas: se ejecutan las condiciones y el contenido de `construirAvisosOperativos` del fuente real de la función Edge: mínimo exacto, umbral preventivo, stock suficiente y saldo pendiente/cero. También se prueba selección de rol para consultar tokens y permiso de revisión. El ejecutor añade exports temporalmente al fuente y sustituye solo el registro HTTP `serve`, `Deno.env` y `fetch`; no reimplementa las condiciones. Las pruebas Dart verifican diferencias entre claves previas/nuevas y envíos a admin/planta con contenido exacto. El texto recibido por el doble de push es un fixture: su generación se comprueba aparte en Edge. No se verificó entrega Firebase a un teléfono, autorización del despliegue Edge, permisos Android ni todas las inconsistencias operativas.

Predicciones: se prueba el respaldo real cuando el intérprete devuelve ausencia o lanza error. El servicio registra la incidencia y usa «Estimación estadística». También se conservaron calibración, respaldo diario y preparación real de filas de predicciones. Preparar filas no demuestra haberlas guardado en base de datos. El intento nativo carga los metadatos y el asset, pero falla al abrir la DLL antes de completar inferencia. No hay evidencia de inferencia nativa exitosa ni de precisión predictiva; harían falta runtime compatible, datos de evaluación independientes y métricas calculadas. Los errores al cargar los metadatos, distintos de la ausencia del intérprete, siguen propagándose y no están cubiertos por el respaldo probado.

Reportes: se conserva generación real de bytes PDF en `plan_cambios_test.dart` y se prueba la construcción real de filtros de consulta del servicio. El doble HTTP no prueba que el servidor filtre correctamente ni que el archivo se comparta en un dispositivo. La cabecera/tamaño del PDF tampoco certifica visualmente todas sus cifras.

**Defectos corregidos y límites**

1. Inventario aceptaba tipo desconocido o cantidad no positiva antes de entrar en sus caminos de persistencia. Ahora lanza `ArgumentError` sin IO.
2. Ventas aceptaba carrito vacío/cantidades inválidas al comenzar el servicio y podía llegar a escrituras separadas sin sesión o ante una respuesta RPC no reconocida. Ahora valida y exige sesión/respuesta válida. El error por RPC ausente ya existía y su prueba se conserva. Un RPC que devuelve una cadena vacía tampoco se acepta como ID.
3. Inventario podía recurrir a actualización de stock más inserción de historial separadas si faltaba sesión o RPC. Ahora falla explícitamente en esas condiciones; no se usa esa alternativa. Se mantuvo el bloque antiguo para limitar el cambio, pero el helper ya no devuelve `false` en ningún camino normal.
4. `registrarAbono` enviaba montos inválidos directamente a la inserción. Ahora rechaza cero, negativos, NaN e infinito antes de escribir.
5. La ausencia/error del intérprete nativo de ML se propagaba y podía bloquear la predicción en vez de usar su respaldo existente. Se captura en el límite del intérprete y se utiliza el respaldo estadístico.

Se añadieron constructores con dependencias opcionales para sustituir únicamente conexiones, sesión y push. Sus valores por defecto siguen siendo los servicios reales. `http` se declaró dependencia de desarrollo directa usando la versión que ya estaba instalada; `pub get --offline` solo actualizó su clasificación en el lockfile.

Un error de lectura después de que un RPC haya confirmado una venta no equivale a rollback de la venta ya confirmada. Tampoco se ha demostrado idempotencia de ventas ante reintentos de red. El método antiguo de abonos todavía tiene inserción y actualización separadas; se validó su entrada, pero su atomicidad completa no queda demostrada. Los flujos actualmente basados en pago seguro se verificaron aparte mediante SQL. No se presenta una prueba de modelos ni un mock como solución a esas limitaciones.

**Correspondencia documental y tesis**

Se inspeccionaron, solo en lectura, los tres DOCX locales del manual técnico. El respaldo previo a la ampliación contiene 15 requisitos funcionales RF-01…RF-15 y 63 pruebas de aceptación PA_01…PA_63. Esos 63 elementos son pruebas de aceptación, no 63 requisitos funcionales. Se extrajeron su texto y expectativa originales; la palabra «Exitosa» que figura en el manual es un resultado histórico documental, NO una ejecución reproducida en esta auditoría.

La relación temática con los RF del manual se identifica como parcial en la matriz. El código RFV del test no se traduce automáticamente al PA del mismo número: por ejemplo, RFV_001 prueba política de contraseña y PA_01 exige ingresar con credenciales de un usuario activo; RFV_063 prueba helpers de permisos/filtros y PA_63 exige generar y compartir un PDF. No son pruebas equivalentes.

| Módulo | Tabla de tesis indicada por el usuario | Ampliado ejecutado inicialmente | PA del manual × 4, solo hipótesis aritmética |
|---|---:|---:|---:|
| Autenticación y usuarios | 45 | 68 | 68 |
| Inventario | 35 | 36 | 36 |
| Ventas | 48 | 32 | 20 |
| Vendedores y rutas | 60 | 72 | 68 |
| Alertas | 42 | 40 | 48 |
| Reportes | 22 | 4 | 12 |
| Total funcional | 252 | 252 | 252 |

La agrupación de la segunda columna ejecutada usa las HU declaradas por los archivos (HU01–04, 05–06, 07, 08–11, 12–14, 15). La última columna usa 17, 9, 5, 17, 12 y 3 PA documentales multiplicadas por cuatro: NO se ejecutaron esas 252 aceptaciones ni se presume que deban existir cuatro escenarios para cada PA. El total coincidente no demuestra correspondencia con la tesis. La ampliación actual también alcanza 252, pero no equivale automáticamente a las 252 aceptaciones que pudieran haberse declarado antes de esta ejecución. La distribución actual, incluida la separación de soporte, está en `AMPLIACION_252.md` y `distribucion_actual.csv`.

El manual también contiene diferencias que requieren reconciliación con la tesis original: RF-09 atribuye rutas a administrador/vendedor, mientras el notificador permite gestión operativa a administrador/planta y bloquea al vendedor; RF-15 enumera los tres roles, pero PA_63 describe generación como administrador y la interfaz limita exportación; RF-10 describe excedentes, mientras algunos RPC de pago rechazan sobrepago y el método antiguo admite otras operaciones. No se cambió la aplicación para encajar una copia documental ambigua.

No se encontró una tesis original identificable que confirme la tabla 45/35/48/60/42/22 ni una matriz aprobada que vincule cada escenario a ella. Esa correspondencia sigue pendiente aunque el manual proporcione requisitos y PA útiles. Para sustentar lo ya entregado puede adjuntarse esta evidencia nueva, con su fecha real, a un anexo o aclaración según indique el tutor. La tabla por módulos todavía necesita reconciliación con la matriz original; no se presenta como corregida por alcanzar el total. Se deben distinguir aceptación completa, comprobaciones unitarias, soporte e integraciones pendientes.

**Comandos y entorno**

Ejecutados desde `C:\dev\agua_milena_app` con Dart 3.12.1. El lanzador `flutter.bat` quedó sin salida en intentos iniciales; se ejecutó el motor instalado de Flutter directamente mediante su snapshot. Las ejecuciones requirieron permiso para acceder al bloqueo/cache del SDK. No se descargaron dependencias.

```powershell
# Conteo inicial, antes de modificar los tests:
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot test test/verificacion_funcional_test.dart test/verificacion_funcional_ampliada_test.dart --reporter json --concurrency 1 --no-pub
# Dependencia de desarrollo ya disponible en cache:
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot pub get --offline
# Suite final:
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot test --reporter json --concurrency 1 --no-pub
# Intento nativo explícito, FALLIDO por DLL:
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe C:\src\flutter\bin\cache\flutter_tools.snapshot test test/integracion_modelo_test.dart --dart-define=RUN_NATIVE_MODEL=true --reporter json --no-pub
# Análisis:
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib test
# SQL aislado:
node scripts/verificar_funciones_aisladas.mjs outputs/sql_saldo_tests/node_modules/@electric-sql/pglite/dist/index.js
# Verificador SQL que ya existía:
node scripts/verificar_plan_sql.mjs outputs/sql_saldo_tests/node_modules/@electric-sql/pglite/dist/index.js
# Reglas Edge reales, sin red:
node --experimental-strip-types scripts/verificar_alertas_reales.mjs
# Regenerar el informe tabular desde resultados ya ejecutados, sin correr pruebas:
python scripts/generar_matriz_pruebas.py
```

El análisis final terminó con cero errores, cero advertencias y cuatro avisos informativos: tres usos preexistentes de `cacheExtent` obsoleto en pantallas y una sugerencia de sintaxis en el fixture conservado. No se alteraron pantallas ajenas para silenciarlos. La salida íntegra está guardada. Hubo fallos intermedios del transporte de pruebas, corregidos antes de la ejecución final; no se cambiaron las expectativas de negocio para lograr aprobación.

El ejecutor SQL crea PGlite en memoria, extrae las tablas del esquema de HEAD, aplica los parches reales y carga del SQL actual la función real de inventario. Así reproduce las funciones concretas, pero NO instala el esquema completo, triggers, RLS, grants ni PostgREST de Supabase. Su helper de sesión por header es un stub del fixture; no certifica ese mecanismo. La comprobación de roles de las funciones usa sesiones reales en las tablas efímeras y `fn_usuario_sesion` real. La clave de cifrado que usa el fixture ya existe en el SQL del repositorio y solo se usa en ese motor efímero.

**Integraciones preparadas, todavía sin aprobación**

Los casos `DB_V01`, `DB_V02`, `DB_P01` y `DB_P02` están en `test/integracion_supabase_aislada_test.dart`. Solo se habilitan con `RUN_SUPABASE_INTEGRATION=true`; además exigen URL localhost/127.0.0.1/::1, claves de ese proyecto y `TEST_ISOLATED_CONFIRM=PROYECTO_DESECHABLE`. Preparar previamente un Supabase local desechable dedicado, con esquema/parches y `supabase/pruebas/fixture_aislado.sql`. Ese fixture no es una migración y jamás debe aplicarse en la empresa. Los casos escriben únicamente si el operador los habilita en ese proyecto local; no se ejecutaron aquí porque falta ese entorno y sus credenciales. El fixture preparado tampoco se reporta como validado en Supabase real.

Ejemplo pendiente (valores de claves omitidos deliberadamente):

```powershell
flutter test test/integracion_supabase_aislada_test.dart --concurrency 1 `
  --dart-define=RUN_SUPABASE_INTEGRATION=true `
  --dart-define=TEST_ISOLATED_CONFIRM=PROYECTO_DESECHABLE `
  --dart-define=TEST_SUPABASE_URL=http://127.0.0.1:54321 `
  --dart-define=TEST_SUPABASE_ANON_KEY=<clave_local> `
  --dart-define=TEST_SUPABASE_SERVICE_KEY=<clave_servicio_local>
```

Estos cuatro casos no agotan la seguridad: quedan pendientes permisos por tabla/rol y relaciones propias/ajenas, rutas completas, expiración de sesión, concurrencia, PostgREST y entrega Firebase. Tampoco se ejecutó la aplicación completa de extremo a extremo en un dispositivo Android.

**Qué decir en la defensa**

Puedes afirmar: «Revisé las pruebas contra la implementación. La suite local final aprobó 252 casos Flutter y comprobé aparte 21 casos de funciones SQL en una base efímera y nueve de las reglas reales de alertas. Separé los duplicados, las validaciones auxiliares y las integraciones pendientes. Las pruebas SQL aisladas verifican el total, el inventario y el rechazo sin cambios parciales en las funciones ensayadas».

Todavía no puedes afirmar: «Demostré 252 aceptaciones independientes, cobertura completa de la tesis, persistencia y seguridad de Supabase en producción, entrega de notificaciones a dispositivos, inferencia nativa exitosa o precisión predictiva». La inferencia nativa fue intentada y está bloqueada por la DLL; cuatro integraciones Supabase no se ejecutaron y la trazabilidad con la tesis original debe reconciliarse.
