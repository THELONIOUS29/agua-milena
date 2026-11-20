// Instrumenta los exports del fuente real, sin reescribir sus reglas.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,unlinkSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const carpeta='outputs/auditoria_edge';mkdirSync(carpeta,{recursive:true});
const archivo=carpeta+'/fuente_real.ts';
const fuente=readFileSync('supabase/functions/enviar-notificaciones/index.ts','utf8');
writeFileSync(archivo,fuente.replace(/^import \{ serve \}.*$/m,'const serve = (_handler: unknown) => {};')+
 '\nexport { construirAvisosOperativos, validarPermisoRevisionOperativa, rolPermitido, usuarioPermitido, resolverTokens };\n');
let productos=[],rutas=[];
const solicitudes=[];
globalThis.Deno={env:{get:nombre=>({SUPABASE_URL:'http://127.0.0.1:54321',SUPABASE_SERVICE_ROLE_KEY:'CONFIGURAR_LOCALMENTE'}[nombre])}};
globalThis.fetch=async (url,opciones={})=>{
  assert.equal(new URL(url).hostname,'127.0.0.1');
  solicitudes.push({url:String(url),body:opciones.body});
  const path=new URL(url).pathname;
  const data=path.endsWith('/productos')?productos:path.endsWith('/rutas')?rutas:[];
  return new Response(JSON.stringify(data),{status:200,headers:{'content-type':'application/json'}});
};
const resultados=[];
async function caso(codigo,nombre,ejecutar){
 try{productos=[];rutas=[];solicitudes.length=0;await ejecutar();resultados.push({codigo,nombre,resultado:'aprobado'});}
 catch(error){resultados.push({codigo,nombre,resultado:'fallido',error:String(error)});process.exitCode=1;}
 console.log(codigo,resultados.at(-1).resultado,nombre);
}
try {
 const real=await import(pathToFileURL(process.cwd()+'/'+archivo));
 await caso('EDGE_A01','stock mínimo activa urgente con contenido del producto',async()=>{
  productos=[{nombre:'Bidón prueba',stock:5,stock_minimo:5,stock_bajo_calculado:8}];
  const avisos=await real.construirAvisosOperativos();
  const alerta=avisos.find(a=>a.datos.tipo==='stock_urgente');
  assert.ok(alerta);assert.match(alerta.cuerpo,/Bidón prueba: quedan 5/);
  assert.equal(avisos.filter(a=>a.datos.tipo==='stock_bajo').length,0);
 });
 await caso('EDGE_A02','stock preventivo activa bajo',async()=>{
  productos=[{nombre:'Bidón prueba',stock:8,stock_minimo:5,stock_bajo_calculado:8}];
  const avisos=await real.construirAvisosOperativos();
  assert.equal(avisos.filter(a=>a.datos.tipo==='stock_bajo').length,1);
 });
 await caso('EDGE_A03','stock suficiente no activa alerta de stock',async()=>{
  productos=[{nombre:'Bidón prueba',stock:9,stock_minimo:5,stock_bajo_calculado:8}];
  const avisos=await real.construirAvisosOperativos();
  assert.equal(avisos.filter(a=>a.datos.tipo?.startsWith('stock_')).length,0);
 });
 await caso('EDGE_A04','saldo positivo activa cobro con importe real',async()=>{
  rutas=[{id:'r1',fecha:'2026-10-25',monto_total:100,monto_cobrado:40,estado:'parcial'}];
  const avisos=await real.construirAvisosOperativos();
  const a=avisos.find(a=>a.datos.tipo==='cobros_pendientes');
  assert.ok(a);assert.match(a.cuerpo,/60\.00/);assert.equal(a.datos.ruta_id,'r1');
 });
 await caso('EDGE_A05','saldo cero no activa cobro',async()=>{
  rutas=[{id:'r1',fecha:'2026-10-25',monto_total:100,monto_cobrado:100,estado:'pagado'}];
  assert.equal((await real.construirAvisosOperativos()).filter(a=>a.datos.tipo==='cobros_pendientes').length,0);
 });
 for(const rol of ['admin','planta','vendedor']){
  await caso(`EDGE_P01_${rol}`,'permisos reales de revisión operativa',async()=>{
   const ejecutar=()=>real.validarPermisoRevisionOperativa({id:'u1',rol,activo:true});
   if(rol==='vendedor')assert.throws(ejecutar,/No autorizado/);else assert.doesNotThrow(ejecutar);
  });
 }
 await caso('EDGE_A06','destinatarios construidos por resolverTokens',async()=>{
  await real.resolverTokens({rol:'planta'});
  assert.deepEqual(JSON.parse(solicitudes[0].body),{p_rol:'planta',p_usuario_id:null});
 });
}finally{
 unlinkSync(archivo);
 writeFileSync('docs/auditoria_pruebas/edge_casos.json',JSON.stringify(resultados,null,2));
}
