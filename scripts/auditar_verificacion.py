"""Conserva evidencia de la revisión inicial y retira lógica recreada de test/."""
import collections
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/auditoria_pruebas'
OUT.mkdir(exist_ok=True)

def llamadas(texto, nombre):
    patron = re.compile(r'\b' + nombre + r'\(')
    for m in patron.finditer(texto):
        inicio, nivel, comilla, escape = m.end(), 1, None, False
        for i in range(inicio, len(texto)):
            c = texto[i]
            if comilla:
                if escape: escape = False
                elif c == '\\': escape = True
                elif c == comilla: comilla = None
            elif c in "'\"": comilla = c
            elif c == '(': nivel += 1
            elif c == ')':
                nivel -= 1
                if nivel == 0:
                    yield texto[m.start():i + 1]
                    break

def normalizar(exp):
    return re.sub(r'\s+', '', exp.replace('vf.', '')).rstrip(',')

def modulo(hu):
    n = int(hu.split('-')[1])
    return ('Autenticación y usuarios' if n <= 4 else 'Inventario' if n <= 6
            else 'Ventas' if n == 7 else 'Vendedores y rutas' if n <= 11
            else 'Alertas' if n <= 14 else 'Reportes')

# Solo estos auxiliares construyen datos o llaman producción, sin decidir reglas.
permitidos = {'verificaHashCorrecto', 'verificaHashIncorrecto', 'lanzaRolInvalido',
    'usuarioAdmin', 'usuarioVendedor', 'usuarioDesdeJsonEspanol',
    'usuarioDesdeJsonIngles', 'productoBase', 'itemCarrito', 'itemRutaCerrado',
    'rutaConItemsAbierta', 'rutaCerrada', 'rutaSaldoParcial', 'rutaPagada',
    'sinAlertaStock', 'rutaConSaldoAFavor', 'rutaBidones', 'rutaBidonesNegativos', 'rutaSinBidones'}
original = (OUT / 'original.dart.txt').read_text(encoding='utf-8')
ampliado = (OUT / 'ampliado.dart.txt').read_text(encoding='utf-8')
# Copias de evidencia, nunca descubiertas como tests por Flutter.
for nombre, contenido in [('original.dart.txt', original), ('ampliado.dart.txt', ampliado)]:
    destino = OUT / nombre
    if not destino.exists(): destino.write_text(contenido, encoding='utf-8')

cabecera = original[:original.index('void main()')]
funciones = set(re.findall(r'^(?:bool|String|int|double|List<[^>]+>|Map<[^>]+>) (\w+)\(', cabecera, re.M))
prohibidos = funciones - permitidos
filas, vistos, conservados = [], {}, []
for llamada in llamadas(original[original.index('final casos ='):], 'CasoVerificacion'):
    m = re.match(r"CasoVerificacion\('([^']+)', '([^']+)', '([^']+)', \(\) => (.*)\)$", llamada, re.S)
    assert m, llamada
    codigo, hu, nombre, exp = m.groups()
    malos = [f for f in prohibidos if re.search(r'\b' + f + r'\b', exp)]
    clave = normalizar(exp)
    duplicado = vistos.get(clave, '')
    estado = 'retirada: lógica local' if malos else 'duplicada' if duplicado else 'conservada'
    if not malos and not duplicado:
        vistos[clave] = codigo
        conservados.append(llamada)
    filas.append(dict(codigo=codigo, hu_declarada_no_confirmada=hu, modulo=modulo(hu),
        nombre=nombre, expresion=exp, expresion_previa=exp, decision=estado, duplicada_de=duplicado,
        auxiliares_locales=', '.join(malos)))

extendidos = []
# Revisión manual de expresiones inline que el inventario de auxiliares no detecta.
reemplazos = {
    'PVF_018_E01': "productoBase(stock: 20, minimo: 5).nombre == 'Bidón de agua'",
    'PVF_032_E02': "itemCarrito('Bidón retornable', 1.5, 1).esBidon",
    'PVF_052_E03': 'itemRutaCerrado().vendidos == 8',
    'PVF_052_E04': 'itemRutaCerrado().copiarConRetorno(cantidadSinVender: 2, cantidadRetornoVacio: 8).faltantes == 0',
}
solo_sdk_o_fixture = {'PVF_032_E04', 'PVF_034_E02', 'PVF_034_E03', 'PVF_034_E04'}
for bloque in llamadas(ampliado[ampliado.index(') => ['):], 'RequisitoFuncionalVerificacion'):
    codigo, hu = re.search(r"codigo: '([^']+)'", bloque)[1], re.search(r"historia: '([^']+)'", bloque)[1]
    for i, escenario in enumerate(llamadas(bloque, 'EscenarioVerificacion'), 1):
        m = re.match(r"EscenarioVerificacion\(\s*'([^']+)',\s*\(\) =>\s*(.*),\s*\)$", escenario, re.S)
        if not m: m = re.match(r"EscenarioVerificacion\(\s*'([^']+)',\s*\(\) =>\s*(.*)\)$", escenario, re.S)
        if not m:
            m = re.match(r"EscenarioVerificacion\(\s*'([^']+)',\s*(.*)\)$", escenario, re.S)
            assert m, escenario
            nombre, cierre = m.groups()
            exp = '(' + cierre.rstrip(',').strip() + ')()'
        else:
            nombre, exp = m.groups()
        exp = re.sub(r'\bvf\s*\.\s*', '', exp.strip())
        caso = f'PVF_{codigo[4:]}_E{i:02}'
        previa = exp
        exp = reemplazos.get(caso, exp)
        if caso == 'PVF_052_E04': nombre = 'Retorno completo no genera faltante'
        malos = [f for f in prohibidos if re.search(r'\b' + f + r'\b', exp)]
        if caso in solo_sdk_o_fixture: malos.append('solo SDK Dart o fixture; no verifica regla de produccion')
        clave = normalizar(exp)
        duplicado = vistos.get(clave, '')
        caso = f'PVF_{codigo[4:]}_E{i:02}'
        estado = 'retirada: lógica local' if malos else 'duplicada' if duplicado else 'reemplazada' if caso in reemplazos else 'conservada'
        if not malos and not duplicado:
            vistos[clave] = caso
            extendidos.append((caso, nombre, exp))
        filas.append(dict(codigo=caso, hu_declarada_no_confirmada=hu, modulo=modulo(hu),
            nombre=nombre, expresion=exp, expresion_previa=previa, decision=estado, duplicada_de=duplicado,
            auxiliares_locales=', '.join(malos)))

with (OUT / 'revision_inicial.csv').open('w', encoding='utf-8-sig', newline='') as f:
    w = csv.DictWriter(f, fieldnames=filas[0].keys()); w.writeheader(); w.writerows(filas)
resumen = {fuente: dict(collections.Counter(f['modulo'] for f in filas if f['codigo'].startswith(prefijo)))
    for fuente, prefijo in [('original', 'PAVF_'), ('ampliado', 'PVF_')]}
resumen['decisiones'] = dict(collections.Counter(f['decision'] for f in filas))
(OUT / 'conteo_inicial.json').write_text(json.dumps(resumen, ensure_ascii=False, indent=2), encoding='utf-8')

print(json.dumps(resumen, ensure_ascii=False, indent=2))
if '--regenerar' not in sys.argv:
    raise SystemExit(0)

# Se conservan los fixtures y las llamadas a producción. Se eliminan TODAS las reglas locales.
lineas = cabecera.splitlines(keepends=True)
limpia = ''.join(l for l in lineas if not any(re.match(r'^(?:bool|String|int|double|List<[^>]+>|Map<[^>]+>) ' + f + r'\(', l) for f in prohibidos))
# Quitar también cuerpos de funciones locales de varias líneas mediante sus límites de nivel superior.
for f in prohibidos:
    patron = re.compile(r'^(?:bool|String|int|double|List<[^>]+>|Map<[^>]+>) ' + f + r'\(', re.M)
    m = patron.search(cabecera)
    if not m: continue
    fin = re.search(r'\n(?=[A-Za-z])', cabecera[m.end():])
    bloque = cabecera[m.start():m.end() + fin.start() + 1] if fin else cabecera[m.start():]
    cabecera = cabecera.replace(bloque, '')
cabecera = cabecera.replace("unidad: nombre.toLowerCase().contains('funda') ? 'funda' : 'bidón',", "unidad: 'unidad',")
cabecera += "\nvoid main() {\n  TestWidgetsFlutterBinding.ensureInitialized();\n  final auth = ServicioAutenticacion();\n  final casos = <CasoVerificacion>[\n"
cabecera += ''.join('    ' + c + ',\n' for c in conservados)
cabecera += "  ];\n  for (final caso in casos) {\n    test('${caso.codigo} - ${caso.nombre}', () {\n      expect(caso.ejecutar(), isTrue);\n    });\n  }\n}\n"
(ROOT / 'test/verificacion_funcional_test.dart').write_text(cabecera, encoding='utf-8')
salida = "import 'package:flutter_test/flutter_test.dart';\nimport 'package:agua_milena_app/datos/modelos/ruta.dart';\nimport 'package:agua_milena_app/dominio/entidades/rol_usuario.dart';\nimport 'package:agua_milena_app/datos/servicios/servicio_autenticacion.dart';\nimport 'verificacion_funcional_test.dart';\n\nvoid main() {\n  TestWidgetsFlutterBinding.ensureInitialized();\n  final auth = ServicioAutenticacion();\n"
for codigo, nombre, exp in extendidos:
    salida += f"  test('{codigo} - {nombre}', () {{\n    expect({exp}, isTrue);\n  }});\n"
salida += '}\n'
(ROOT / 'test/verificacion_funcional_ampliada_test.dart').write_text(salida, encoding='utf-8')
print(json.dumps(resumen, ensure_ascii=False, indent=2))

