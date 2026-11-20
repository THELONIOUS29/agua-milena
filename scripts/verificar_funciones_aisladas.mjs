import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';

// Pass the PGlite entrypoint as an argument, or install @electric-sql/pglite.
const moduleUrl = process.argv[2] ? pathToFileURL(process.argv[2]).href : '@electric-sql/pglite';
const { PGlite } = await import(moduleUrl);
const { pgcrypto } = await import(process.argv[2]
  ? new URL('./contrib/pgcrypto.js', moduleUrl).href
  : '@electric-sql/pglite/contrib/pgcrypto');
const db = new PGlite({ extensions: { pgcrypto } });
const anterior = execFileSync('git', ['show', 'HEAD:supabase/base_datos_completa_agua_milena.sql'], { encoding: 'utf8' });
const migracion = readFileSync('supabase/parche_plan_v1_0_5.sql', 'utf8');
const tabla = (nombre) => {
  const inicio = anterior.indexOf('CREATE TABLE ' + nombre + ' (');
  assert.ok(inicio >= 0, nombre);
  return anterior.slice(inicio, anterior.indexOf('\n);', inicio) + 3);
};
await db.exec(`
  CREATE ROLE anon;
  CREATE ROLE authenticated;
  CREATE SCHEMA inventario;
  CREATE SCHEMA ventas;
  CREATE SCHEMA rutas;
  CREATE SCHEMA vendedores;
  CREATE SCHEMA usuarios;
  CREATE SCHEMA extensions;
  CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
  CREATE FUNCTION usuarios.fn_sesion_header_tiene_rol(roles text[])
  RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
`);
for (const nombre of ['inventario.productos', 'inventario.movimientos_inventario',
  'vendedores.vendedores', 'ventas.ventas', 'ventas.items_venta',
  'rutas.rutas', 'rutas.items_ruta', 'rutas.abonos', 'usuarios.usuarios',
  'usuarios.sesiones_app']) {
  await db.exec(tabla(nombre));
}
const authStart = anterior.indexOf('CREATE OR REPLACE FUNCTION usuarios.fn_usuario_sesion(');
await db.exec(anterior.slice(authStart, anterior.indexOf('CREATE OR REPLACE FUNCTION usuarios.fn_session_token_header', authStart)));
await db.exec(migracion);
await db.exec(migracion);
const scalar = async (sql, params = []) => Object.values((await db.query(sql, params)).rows[0])[0];
const seller = await scalar("INSERT INTO vendedores.vendedores(nombre) VALUES ('Yovany') RETURNING id");
const oliver = await scalar("INSERT INTO vendedores.vendedores(nombre) VALUES ('Oliver') RETURNING id");
const correccion = readFileSync('supabase/parche_devoluciones_y_saldo_explicito.sql', 'utf8');
await db.exec(correccion);
await db.exec(correccion);
for (const rol of ['admin', 'planta', 'vendedor']) {
  const usuario = await scalar(`
    INSERT INTO usuarios.usuarios(email_hash, email_enc, nombre, hash_contrasena, rol)
    VALUES ($1, extensions.pgp_sym_encrypt($1, 'agua_milena_db_key_2026'), $1, 'test', $1)
    RETURNING id`, [rol]);
  await db.query(`
    INSERT INTO usuarios.sesiones_app(usuario_id, token_hash)
    VALUES ($1, encode(extensions.digest(convert_to($2, 'UTF8'), 'sha256'), 'hex'))`, [usuario, rol]);
}
// Reproduce the missing extension in a caller's search_path, then verify the fix.
await db.exec(`
  ALTER FUNCTION usuarios.fn_usuario_sesion(text) RESET search_path;
  CREATE FUNCTION public.probar_sesion(token text) RETURNS text
  LANGUAGE sql SET search_path = usuarios, public
  AS $$ SELECT rol FROM usuarios.fn_usuario_sesion(token) $$;
`);
await assert.rejects(db.query("SELECT public.probar_sesion('admin')"), /digest/);
await db.exec(correccion);
assert.equal(await scalar("SELECT public.probar_sesion('admin')"), 'admin');
const producto = await scalar("INSERT INTO inventario.productos(nombre, precio, stock) VALUES ('Agua', 3, 100) RETURNING id");
const venta = async (items, vendedor = seller, rol = 'admin', fecha = '2026-10-03', aplicar = false) =>
  scalar('SELECT ventas.fn_crear_venta_segura($1, $2::jsonb, $3, $4::uuid, $5::date, 0, 0, $6)', [
    rol, JSON.stringify(items), 'Nota inicial', vendedor, fecha, aplicar,
  ]);
const item = (cantidad, devolucion = 0) => ({ producto_id: producto, cantidad, devolucion });
const guardarPrecio = (vendedor, precio) => db.query(`
  INSERT INTO inventario.precios_producto(producto_id, vendedor_id, precio)
  VALUES ($1, $2, $3) ON CONFLICT(producto_id, vendedor_id)
  DO UPDATE SET precio = EXCLUDED.precio`, [producto, vendedor, precio]);
const pago = (ruta, monto, descuento, rol = 'admin') =>
  scalar('SELECT rutas.fn_registrar_pago_con_descuento($1,$2,$3,$4,$5)', [rol, ruta, monto, descuento, 'Prueba descuento']);

const resultados = [];
async function caso(codigo, nombre, verificar) {
  await db.exec('TRUNCATE ventas.ventas, rutas.rutas, inventario.movimientos_inventario RESTART IDENTITY CASCADE');
  await db.query('UPDATE inventario.productos SET stock=100 WHERE id=$1',[producto]);
  try {
    await verificar();
    resultados.push({codigo,nombre,resultado:'aprobado'});
    console.log(`${codigo} aprobado: ${nombre}`);
  } catch(error) {
    resultados.push({codigo,nombre,resultado:'fallido',error:String(error)});
    console.error(`${codigo} fallido: ${error}`);
  } finally { /* El motor completo se destruye al terminar. */ }
}
const stock = async () => Number(await scalar('SELECT stock FROM inventario.productos WHERE id=$1',[producto]));
const snapshot = async () => (await db.query(`SELECT
  (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM ventas.ventas x) ventas,
  (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM ventas.items_venta x) items,
  (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM inventario.productos x) productos,
  (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM inventario.movimientos_inventario x) movimientos,
  (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM rutas.rutas x) rutas,
  (SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM vendedores.vendedores x) vendedores`)).rows;
// Cada llamada es una sentencia en autocommit; se inspecciona el estado SIN rollback del test.
async function rechazarSinCambios(accion, patron) {
  const antes=await snapshot();
  await assert.rejects(accion(),patron);
  assert.deepEqual(await snapshot(),antes);
}
try {
  await caso('SQL_V01','venta válida, total del precio real y descuento de stock',async()=>{
    const id=await venta([item(2)],null);
    assert.equal(Number(await scalar('SELECT total FROM ventas.ventas WHERE id=$1',[id])),6);
    assert.equal(await stock(),98);
    assert.equal(Number(await scalar("SELECT sum(cantidad) FROM inventario.movimientos_inventario WHERE tipo='salida'")),2);
  });
  await caso('SQL_V02','stock insuficiente no deja venta, items, movimientos ni ruta',async()=>{
    await rechazarSinCambios(()=>venta([item(101)]),/stock/);
  });
  await caso('SQL_V03','segundo producto insuficiente revierte primer producto',async()=>{
    const otro=await scalar("INSERT INTO inventario.productos(nombre,precio,stock) VALUES ('Sin stock',2,0) RETURNING id");
    await rechazarSinCambios(()=>venta([item(2),{producto_id:otro,cantidad:1}]),/stock/);
  });
  for(const cantidad of [-1,0]) {
    await caso(`SQL_V04_${cantidad}`,'cantidad inválida sin cambios',async()=>{
      await rechazarSinCambios(()=>venta([item(cantidad)]),/quantity/);
    });
  }
  await caso('SQL_V05','carrito vacío rechazado sin cambios',async()=>{
    await rechazarSinCambios(()=>venta([]),/item|empty|quantity/i);
  });
  await caso('SQL_V06','producto repetido rechazado sin cambios',async()=>{
    await rechazarSinCambios(()=>venta([item(1),item(1)]),/duplicate/);
  });
  for(const rol of ['admin','planta']) {
    await caso(`SQL_P01_${rol}`,'rol operativo puede registrar venta',async()=>{
      await venta([item(1)],null,rol); assert.equal(await stock(),99);
    });
  }
  for(const rol of ['vendedor','sesion-inexistente']) {
    await caso(`SQL_P02_${rol}`,'rol o sesión inválida no escribe venta',async()=>{
      await rechazarSinCambios(()=>venta([item(1)],null,rol),/privileges|invalid session/);
    });
  }
  await caso('SQL_R01','abono parcial cambia cobrado y estado',async()=>{
    const id=await venta([item(10)]);
    const ruta=await scalar('SELECT ruta_id FROM ventas.ventas WHERE id=$1',[id]);
    await pago(ruta,10,0);
    assert.equal(Number(await scalar('SELECT monto_cobrado FROM rutas.rutas WHERE id=$1',[ruta])),10);
    assert.equal(await scalar('SELECT estado FROM rutas.rutas WHERE id=$1',[ruta]),'parcial');
  });
  await caso('SQL_R02','pago completo cambia estado y registra abono',async()=>{
    const id=await venta([item(10)]);
    const ruta=await scalar('SELECT ruta_id FROM ventas.ventas WHERE id=$1',[id]);
    await pago(ruta,30,0);
    assert.equal(await scalar('SELECT estado FROM rutas.rutas WHERE id=$1',[ruta]),'pagado');
    assert.equal(Number(await scalar('SELECT sum(monto) FROM rutas.abonos WHERE ruta_id=$1',[ruta])),30);
  });
  await caso('SQL_R03','vendedor no registra pagos',async()=>{
    const id=await venta([item(10)]);
    const ruta=await scalar('SELECT ruta_id FROM ventas.ventas WHERE id=$1',[id]);
    await assert.rejects(pago(ruta,1,0,'vendedor'),/privileges/);
    assert.equal(Number(await scalar('SELECT count(*) FROM rutas.abonos')),0);
  });
  // Función de inventario extraída sin reescribirla del SQL actual de producción.
  const esquemaActual=readFileSync('supabase/base_datos_completa_agua_milena.sql','utf8');
  const inicio=esquemaActual.indexOf('CREATE OR REPLACE FUNCTION inventario.fn_registrar_movimiento_seguro(');
  const fin=esquemaActual.indexOf('$$;',inicio)+3;
  assert.ok(inicio>=0 && fin>inicio);
  await db.exec(esquemaActual.slice(inicio,fin));
  const movimiento=(tipo,cantidad,rol='admin')=>scalar('SELECT inventario.fn_registrar_movimiento_seguro($1,$2,$3,$4,$5)',[rol,producto,tipo,cantidad,'fixture aislado']);
  for(const [tipo,cantidad,esperado] of [['entrada',5,105],['salida',5,95]]) {
    await caso(`SQL_I01_${tipo}`,'movimiento cambia stock e historial',async()=>{
      await movimiento(tipo,cantidad);assert.equal(await stock(),esperado);
      assert.equal(Number(await scalar('SELECT sum(cantidad) FROM inventario.movimientos_inventario')),5);
    });
  }
  for(const [tipo,cantidad] of [['entrada',0],['entrada',-1],['ajuste',1],['salida',101]]) {
    await caso(`SQL_I02_${tipo}_${cantidad}`,'movimiento inválido sin cambios',async()=>{
      await rechazarSinCambios(()=>movimiento(tipo,cantidad),/quantity|type|stock|invalid/i);
    });
  }
  await caso('SQL_I03','vendedor no registra inventario',async()=>{
    await rechazarSinCambios(()=>movimiento('entrada',1,'vendedor'),/privileges/);
  });
} finally {
  await db.close();
  const {writeFileSync}=await import('node:fs');
  writeFileSync('docs/auditoria_pruebas/sql_casos.json',JSON.stringify(resultados,null,2));
}
if(resultados.some(r=>r.resultado==='fallido')) process.exitCode=1;
