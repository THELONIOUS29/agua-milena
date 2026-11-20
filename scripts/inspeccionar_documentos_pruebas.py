from pathlib import Path
import zipfile,xml.etree.ElementTree as E,json
ns={'w':'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
res=[]
for p in Path('docs').glob('*.docx'):
 with zipfile.ZipFile(p) as z:
  root=E.fromstring(z.read('word/document.xml'))
  parrafos=[''.join(x.itertext()) for x in []]
  parrafos=[''.join(t.text or '' for t in x.findall('.//w:t',ns)) for x in root.findall('.//w:p',ns)]
  indices=[i for i,t in enumerate(parrafos) if any(k in t.lower() for k in ['63 requisitos','252','matriz','hu-01','rf-01','45','pruebas funcionales'])]
  contexto=[]
  for i in indices:
   contexto.extend(parrafos[max(0,i-1):min(len(parrafos),i+3)])
  res.append({'archivo':str(p),'parrafos':len(parrafos),'extractos':list(dict.fromkeys(contexto))[:130]})
Path('docs/auditoria_pruebas/documentos_consultados.json').write_text(json.dumps(res,ensure_ascii=False,indent=2),encoding='utf-8')
for r in res:
 print(r['archivo'],r['parrafos'])
 print('\n'.join(r['extractos'])[:4500])
