from pathlib import Path
import csv,json,collections,re
ROOT=Path(__file__).resolve().parents[1]; OUT=ROOT/'docs/auditoria_pruebas'
def eventos(path):
    result=[]
    for linea in path.read_text(encoding='utf-8-sig').splitlines():
        try: result.append(json.loads(linea))
        except ValueError: pass
    return result

def registrar(path):
    ev=eventos(path)
    suites={e['suite']['id']:e['suite']['path'] for e in ev if e.get('type')=='suite'}
    tests={e['test']['id']:e['test'] for e in ev if e.get('type')=='testStart'}
    return [(tests[e['testID']],suites[tests[e['testID']]['suiteID']],e) for e in ev
            if e.get('type')=='testDone' and not e.get('hidden')]

def escribir(nombre,filas):
    with (OUT/nombre).open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=filas[0].keys());w.writeheader();w.writerows(filas)

# Metadatos de los casos nuevos, extraidos de su registro sin ejecutar otra vez los tests.
fuente_ampliacion=(ROOT/'test/ampliacion_cobertura_real_test.dart').read_text(encoding='utf-8-sig')
registros_ampliacion=re.findall(r"caso\(\s*'([^']+)',\s*'([^']+)',\s*'([^']+)'",fuente_ampliacion)
ampliacion={codigo:{'codigo':codigo,'nombre':nombre,'metodo_real':metodo} for codigo,nombre,metodo in registros_ampliacion}
(OUT/'catalogo_ampliacion.json').write_text(json.dumps(list(ampliacion.values()),ensure_ascii=False,indent=2),encoding='utf-8')
revision=list(csv.DictReader((OUT/'revision_inicial.csv').open(encoding='utf-8-sig')))
original={f['codigo']:f for f in revision}
fuente=json.loads((OUT/'tablas_fuente.json').read_text(encoding='utf-8'))
requisitos=[];aceptaciones=[]
for tabla in fuente:
    filas=tabla['filas'];contenido=' '.join(' '.join(f) for f in filas)
    if re.fullmatch(r'RF-\d+',filas[0][0]):
        requisitos.append({'codigo':filas[0][0],'descripcion':filas[1][-1],
            'roles':next(f[-1] for f in filas if f[0].startswith('Roles capaces')),
            'fuente':'Manual técnico COPIA_backup_pre_verificacion_ampliada; no tesis original'})
    m=re.search(r'PA_\d+_HU_(\d+)_\d+',contenido)
    if m:
        numero=int(re.search(r'PA_(\d+)',m[0])[1])
        parciales={3,8,9,12,15,16,18,19,20,23,24,25,27,28,29,30,37,38,41,42,43,45,46,47,48,49,50,51,53,54,55,56,57,61,62,63}
        aceptaciones.append({'codigo':m[0],'requisito_manual':f'RF-{int(m[1]):02}',
            'nombre':next(f[0] for f in filas if f[0].startswith('Nombre:')),
            'resultado_esperado':next(f[0] for f in filas if f[0].startswith('Resultado esperado:')),
            'cobertura':'parcial; ver matriz; no aceptación completa' if numero in parciales else 'pendiente: flujo de aceptación completo no ejecutado',
            'evaluacion_documental_no_reproducida':next((f[-1] for f in filas if f[0]=='Evaluación de la prueba'),'sin dato')})
escribir('requisitos_manual.csv',requisitos);escribir('aceptacion_manual.csv',aceptaciones)

def produccion(exp):
    if 'auth.' in exp or 'Hash' in exp:return 'lib/datos/servicios/servicio_autenticacion.dart: esContrasenaValida/hashContrasena/verificarContrasena'
    if any(n in exp for n in ['usuario','RolUsuario','lanzaRol']):return 'lib/dominio/entidades/rol_usuario.dart: desdeTexto; UsuarioApp.desdeJson/aJson/copiarCon'
    if 'productoBase' in exp or 'sinAlertaStock' in exp:return 'lib/datos/modelos/producto.dart: desdeJson y propiedades de stock/catálogo'
    if 'itemCarrito' in exp:return 'lib/datos/modelos/item_venta.dart: ItemCarrito.subtotal/esBidon (sin registrar venta)'
    if 'itemRuta' in exp:return 'lib/datos/modelos/item_ruta.dart: subtotal/vendidos/faltantes/copiarConRetorno'
    return 'lib/datos/modelos/ruta.dart: propiedades calculadas y estado del modelo; sin cierre ni abono persistido'

casos=[];por_archivo=collections.Counter();tipos=collections.Counter();estado=collections.Counter()
for t,ruta,fin in registrar(OUT/'flutter_final.jsonl'):
    nombre=t['name'];archivo=Path(ruta).name;por_archivo[archivo]+=1
    prefijo=re.search(r'((?:PAVF|PVF|REAL|OP|DB|NATIVO|AMP)_.+?) - ',nombre)
    codigo=prefijo[1] if prefijo else f'EXIST_{Path(archivo).stem}_{por_archivo[archivo]:02}'
    tipo='widgets' if t.get('root_url') else 'unitaria'
    resultado='omitida / no ejecutada' if fin.get('skipped') else 'aprobada' if fin['result']=='success' else 'fallida'
    requisito='Pendiente de asociación documental';modulo='Transversal'
    esperado=nombre.split(' - ',1)[-1]
    if codigo in original:
        f=original[codigo];exp=f['expresion'];hu=int(f['hu_declarada_no_confirmada'].split('-')[1]);
        # Asociación temática contrastada con las descripciones del manual, sin certificar aceptación.
        requisito=f'RF-{hu:02} (manual local; contribución parcial)';modulo=f['modulo'];real=produccion(exp);esperado=exp+' => true'
    elif codigo in ampliacion:
        familia=codigo.split('_')[1][:2]
        modulo,rf={'AU':('Autenticación y usuarios','RF-01/RF-03'),
          'IN':('Inventario','RF-05/RF-06'),'VE':('Ventas','RF-07'),
          'RE':('Reportes','RF-15'),'RU':('Vendedores y rutas','RF-09/RF-10'),
          'AL':('Alertas','RF-12/RF-13')}[familia]
        requisito=rf+' (manual local; contribución parcial)'
        metodo=ampliacion[codigo]['metodo_real']
        clases={'ServicioCriptografia':'lib/datos/servicios/servicio_criptografia.dart',
          'ServicioProducto':'lib/datos/servicios/servicio_producto.dart',
          'ServicioVenta':'lib/datos/servicios/servicio_venta.dart',
          'ServicioReportePdf':'lib/datos/servicios/servicio_reporte_pdf.dart',
          'ServicioRuta':'lib/datos/servicios/servicio_ruta.dart',
          'Ruta':'lib/datos/modelos/ruta.dart',
          'AvisoPushRemoto':'lib/datos/servicios/servicio_push_remoto.dart',
          'ResultadoPushRemoto':'lib/datos/servicios/servicio_push_remoto.dart',
          'ServicioAlertasAutomaticas':'lib/datos/servicios/servicio_alertas_automaticas.dart',
          'ServicioModeloAlertas':'lib/datos/servicios/servicio_modelo_alertas.dart'}
        real=clases[metodo.split('.')[0]]+': '+metodo
        esperado=ampliacion[codigo]['nombre']
    elif codigo.startswith('REAL_V'):
        modulo='Ventas';requisito='RF-07 (manual local; parcial)';real='lib/datos/servicios/servicio_venta.dart: crearVenta/_crearVentaSegura'
        if codigo.startswith('REAL_V07'):real='lib/presentacion/proveedores/proveedor_venta.dart: NotificadorCarrito.agregarProducto/actualizarCantidad/actualizarDevolucion/total'
    elif codigo.startswith('REAL_I'):
        modulo='Inventario';requisito='RF-06 (manual local; parcial)';real='lib/datos/servicios/servicio_producto.dart: registrarMovimiento/_registrarMovimientoSeguro'
    elif codigo.startswith('REAL_R'):
        modulo='Vendedores y rutas';requisito='RF-10 (manual local; parcial)';real='lib/datos/servicios/servicio_ruta.dart: registrarAbono'
    elif codigo.startswith('REAL_P'):
        modulo='Permisos';requisito='RF-01/RF-02 (manual local; parcial)';real='lib/nucleo/enrutador/enrutador_app.dart: redirigirAutenticacion, invocada por GoRouter.redirect'
    elif codigo.startswith('OP_'):
        modulo='Permisos';requisito='RF-07/RF-09/RF-10 (manual local; parcial)';real='lib/presentacion/proveedores/proveedor_venta.dart o proveedor_ruta.dart: eliminar/registrarAbono; dependencia externa de servicio sustituida'
    elif codigo.startswith('REAL_A'):
        modulo='Alertas';requisito='RF-12 (manual local; parcial)';real='lib/datos/servicios/servicio_alertas_automaticas.dart: capturarEstadoActual/notificarAlertasNuevas; push sustituido'
    elif codigo.startswith('REAL_M'):
        modulo='Predicciones';requisito='RF-13 (manual local; parcial)';real='lib/datos/servicios/servicio_modelo_alertas.dart: cargar/predecir/_intentarPrediccionML; solo intérprete sustituido'
    elif codigo.startswith('REAL_F'):
        modulo='Reportes';requisito='RF-15 (manual local; parcial)';real='lib/datos/servicios/servicio_venta.dart: consultarPorFiltros (consulta HTTP; sin persistencia)'
    elif codigo.startswith('NATIVO'):
        tipo='integración nativa';modulo='Predicciones';requisito='RF-13; PA_54_HU_13_01 (manual local)';real='ejecutor_tflite_nativo.dart: ejecutarInferenciaML + assets/modelos/*.tflite'
        resultado+='; intento explícito adicional FALLÓ: falta libtensorflowlite_c-win.dll'
    elif codigo.startswith('DB_'):
        tipo='integración Supabase';modulo='Ventas/Permisos';requisito='RF-06/RF-07 (manual local)';real='servicios Dart y RPC/tablas reales de Supabase; endpoint local desechable obligatorio'
    else:
        mapa={
          'widget_test.dart':('Widgets/utilidades','UtilidadesFecha; FondoAguaAmbiental; TarjetaApp'),
          'grilla_inicio_test.dart':('Inicio','lib/presentacion/componentes/grilla_inicio.dart'),
          'vincular_vendedor_test.dart':('Usuarios','UserFormScreen; datos de usuario/vendedor sustituidos'),
          'saldo_favor_despacho_test.dart':('Vendedores y rutas','ResumenSaldoDespacho.calcular; SelectorSaldoDespacho'),
          'modelo_alertas_test.dart':('Predicciones','ServicioModeloAlertas.calibrarPrediccionDiaria/estimarPrediccionEstadistica/construirFilasPrediccionesTflite'),
          'plan_cambios_test.dart':('Ventas/Reportes','Vendedor/PrecioProducto.resolver/NotificadorCarrito/Ruta/ServicioReportePdf.generarReporte'),
          'seguridad_config_test.dart':('Autenticación/configuración','ServicioAutenticacion.esContrasenaValida; ServicioConfigApp.compararVersiones/requiereActualizar')}
        modulo,real=mapa.get(archivo,('Transversal',archivo))
        if archivo=='widget_test.dart':
            real='lib/nucleo/utilidades/utilidades_fecha.dart: AppDateUtils.weekdayInitial' if 'weekdayInitial' in nombre else 'lib/presentacion/componentes/fondo_agua_ambiental.dart: FondoAguaAmbiental.build' if 'ambient' in nombre else 'lib/presentacion/componentes/tarjeta_app.dart: TarjetaApp.build/onTap'
        if archivo=='plan_cambios_test.dart':
            if 'precio' in nombre.lower(): real='lib/datos/modelos/precio_producto.dart: PrecioProducto.resolver'; requisito='RF-07 (manual local; parcial)'
            elif 'carrito' in nombre.lower(): real='lib/presentacion/proveedores/proveedor_venta.dart: NotificadorCarrito'; requisito='RF-07 (manual local; parcial)'
            elif 'PDF' in nombre: real='lib/datos/servicios/servicio_reporte_pdf.dart: ServicioReportePdf.generarReporte'; requisito='RF-15 (manual local; parcial; no compartir)'
            elif 'ruta' in nombre.lower(): real='lib/datos/modelos/ruta.dart: totalCalculado/saldoPendiente/tieneSaldoAFavor'; requisito='RF-09/RF-10 (manual local; parcial)'
            else: real='lib/datos/modelos/vendedor.dart: Vendedor.desdeJson/copiarCon/permiteDevoluciones'; requisito='RF-08 (manual local; parcial)'
        rf_archivos={'grilla_inicio_test.dart':'RF-04','vincular_vendedor_test.dart':'RF-02',
            'saldo_favor_despacho_test.dart':'RF-10','modelo_alertas_test.dart':'RF-13'}
        if archivo in rf_archivos: requisito=rf_archivos[archivo]+' (manual local; parcial)'

    tipos[tipo]+=1;estado['omitidas' if fin.get('skipped') else 'aprobadas' if fin['result']=='success' else 'fallidas']+=1
    casos.append(dict(codigo=codigo,requisito_asociado=requisito,modulo=modulo,tipo=tipo,
        codigo_real_verificado=real,resultado_esperado=esperado,resultado_ejecucion=resultado,archivo=archivo))
for fichero,tipo in [('sql_casos.json','integración SQL aislada PGlite'),('edge_casos.json','unitaria Edge con transporte sustituido')]:
    for f in json.loads((OUT/fichero).read_text(encoding='utf-8')):
        es_sql=fichero.startswith('sql');codigo=f['codigo'];modulo='Alertas' if not es_sql else 'Inventario' if codigo.startswith('SQL_I') else 'Vendedores y rutas' if codigo.startswith('SQL_R') else 'Ventas/Permisos'
        requisito='RF-12/RF-14' if not es_sql else 'RF-06' if codigo.startswith('SQL_I') else 'RF-10' if codigo.startswith('SQL_R') else 'RF-07'
        real='supabase/functions/enviar-notificaciones/index.ts: construirAvisosOperativos/resolverTokens/validarPermisoRevisionOperativa' if not es_sql else 'SQL real: fn_crear_venta_segura/fn_registrar_pago_con_descuento/fn_registrar_movimiento_seguro; tablas persistidas en PGlite efímero'
        casos.append(dict(codigo=codigo,requisito_asociado=requisito+' (manual local; parcial)',modulo=modulo,tipo=tipo,
            codigo_real_verificado=real,resultado_esperado=f['nombre'],resultado_ejecucion=f['resultado'],archivo='scripts/verificar_funciones_aisladas.mjs' if es_sql else 'scripts/verificar_alertas_reales.mjs'))
escribir('matriz_pruebas.csv',casos)
# Correspondencia de lo retirado a familias de pruebas reales; no equivale a sustitución uno a uno.
for f in revision:
    aux=f['auxiliares_locales'];sustitucion=''
    if f['decision']=='retirada: lógica local':
        if any(x in aux for x in ['ventaConStock','stockDespues','ventaPermitida','totalCarrito']):sustitucion='REAL_V*, SQL_V*: cobertura parcial; ver matriz'
        elif any(x in aux for x in ['Movimiento','movimiento','aplicarMovimiento']):sustitucion='REAL_I*, SQL_I*: servicio/RPC; no UI/historial completo'
        elif any(x in aux for x in ['puedeAcceder','destinoInicial']):sustitucion='REAL_P*: redirecciones reales; no flujo completo de navegación'
        elif any(x in aux for x in ['puedeEliminar','puedeRegistrarAbono']):sustitucion='OP_R*: permisos del notificador real'
        elif 'montoAbono' in aux:sustitucion='REAL_R*, SQL_R*: validación y estados reales'
        elif any(x in aux for x in ['prediccion','cargaRecomendada','Modelo','Historicos','porcentajeRiesgo','ventaAlta']):sustitucion='REAL_M*, modelo_alertas_test.dart, NATIVO_M01 bloqueado; sin precisión demostrada'
        elif any(x in aux for x in ['Alerta','alerta','ordenarPrioridades']):sustitucion='REAL_A*, EDGE_*: solo condiciones/contenido/envíos cubiertos; otras condiciones pendientes'
        elif any(x in aux for x in ['Ventas','ventasEnRango']):sustitucion='REAL_F01: construcción de consulta; PDF en plan_cambios_test; sin filtro persistido demostrado'
        else:sustitucion='Pendiente: no existe reemplazo equivalente ejecutado'
    if f['decision']=='reemplazada': sustitucion='Mismo codigo, ahora llama ItemRuta.vendidos o copiarConRetorno(...).faltantes; expresion previa conservada'
    f['sustitucion_o_pendiente']=sustitucion
    f['codigo_real_original']=produccion(f['expresion']) if f['decision'] in ['conservada','reemplazada'] else 'sin evidencia adicional' if f['decision']=='duplicada' else 'ninguno: auxiliar local de test/'
    if f['decision']=='reemplazada': f['codigo_real_original']='Solo campos del modelo y calculo inline en test; sustituido por getter real'
escribir('revision_caso_por_caso.csv',revision)
resumen={'flutter':dict(estado),'por_archivo':dict(por_archivo),'por_tipo':dict(tipos),
 'sql_aislado':len(json.loads((OUT/'sql_casos.json').read_text(encoding='utf-8'))),
 'edge':len(json.loads((OUT/'edge_casos.json').read_text(encoding='utf-8'))),
 'matriz_filas':len(casos),'requisitos_manual':len(requisitos),'aceptaciones_manual':len(aceptaciones),
 'ampliacion_nueva':len(ampliacion),'duplicadas_cruzadas':sum(f['decision']=='duplicada' and f['duplicada_de'].startswith('PAVF_') and f['codigo'].startswith('PVF_') for f in revision)}
(OUT/'resumen_final.json').write_text(json.dumps(resumen,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(resumen,ensure_ascii=False,indent=2))

# Distribución descriptiva de casos Flutter aprobados, independiente de objetivos numéricos.
clasificados=[]
for f in casos:
    if f['tipo'] not in ['unitaria','widgets'] or f['resultado_ejecucion']!='aprobada': continue
    mod=f['modulo']; codigo=f['codigo']; nombre=f['resultado_esperado'].lower()
    motivo='Modulo principal del metodo o requisito verificado.'
    if mod in ['Inicio','Usuarios']:
        mod='Autenticación y usuarios'; motivo='Panel HU-04 o usuarios HU-02, agrupados como en la revision inicial.'
    elif mod=='Predicciones':
        mod='Alertas'; motivo='Predicciones RF-13 del modulo de alertas.'
    elif mod=='Autenticación/configuración':
        mod='Autenticación y usuarios' if 'contras' in nombre else 'Soporte fuera de la tabla'
        motivo='Politica de contrasenas o configuracion de versiones fuera de los seis modulos.'
    elif mod=='Widgets/utilidades':
        mod='Soporte fuera de la tabla'; motivo='Utilidad de calendario o componente visual, sin requisito funcional confirmado.'
    elif mod=='Permisos':
        mod='Ventas' if codigo.startswith('OP_V') else 'Vendedores y rutas' if codigo.startswith('OP_R') else 'Autenticación y usuarios'
        motivo='Permiso del notificador de ventas/rutas o redireccion de autenticacion.'
    elif mod=='Ventas/Reportes':
        mod='Reportes' if 'pdf' in nombre else 'Ventas' if ('precio' in nombre or 'carrito' in nombre) else 'Vendedores y rutas'
        motivo='PDF, precio/carrito o modelo de vendedor/ruta, segun el caso.'
    clasificados.append(dict(codigo=codigo,modulo_actual=mod,motivo=motivo))
escribir('distribucion_actual.csv',clasificados)
(OUT/'distribucion_actual.json').write_text(json.dumps(dict(collections.Counter(f['modulo_actual'] for f in clasificados)),ensure_ascii=False,indent=2),encoding='utf-8')
