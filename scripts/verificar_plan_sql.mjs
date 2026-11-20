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
try {
  assert.equal(await scalar('SELECT permite_devoluciones FROM vendedores.vendedores WHERE id=$1', [seller]), true);
  assert.equal(await scalar('SELECT permite_devoluciones FROM vendedores.vendedores WHERE id=$1', [oliver]), false);
  await assert.rejects(venta([item(1, 1)], oliver), /returns are not enabled/);
  const base = await venta([item(2)], null);
  assert.equal(Number(await scalar('SELECT total FROM ventas.ventas WHERE id=$1', [base])), 6);
  await guardarPrecio(null, 2);
  await guardarPrecio(null, 2.5);
  assert.equal(Number(await scalar('SELECT count(*) FROM inventario.precios_producto WHERE vendedor_id IS NULL')), 1);
  const fallback = await venta([item(2)]);
  assert.equal(Number(await scalar('SELECT total FROM ventas.ventas WHERE id=$1', [fallback])), 5);
  await guardarPrecio(seller, 1);
  const nueva = await venta([item(10, 2)], seller, 'admin', '2026-10-04');
  assert.equal(Number(await scalar('SELECT total FROM ventas.ventas WHERE id=$1', [nueva])), 8);
  assert.equal(Number(await scalar('SELECT stock FROM inventario.productos WHERE id=$1', [producto])), 88);
  assert.equal(Number(await scalar("SELECT cantidad FROM inventario.movimientos_inventario WHERE tipo='entrada'")), 2);
  assert.equal((await scalar('SELECT items_json FROM ventas.v_ventas WHERE id=$1', [nueva]))[0].devolucion, 2);
  const ruta = await scalar('SELECT ruta_id FROM ventas.ventas WHERE id=$1', [nueva]);
  assert.equal(await scalar('SELECT ruta_id FROM ventas.ventas WHERE id=$1', [fallback]), ruta);
  assert.equal(Number(await scalar('SELECT count(*) FROM rutas.rutas')), 1);
  await venta([item(0, 3)]);
  assert.equal(Number(await scalar('SELECT stock FROM inventario.productos WHERE id=$1', [producto])), 91);
  await assert.rejects(venta([item(1)], seller, 'vendedor'), /privileges/);
  await assert.rejects(venta([item(1, 1)], null), /quantity/);
  await assert.rejects(venta([item(1), item(1)]), /duplicate/);
  await assert.rejects(venta([item(999)]), /stock/);
  assert.equal(Number(await scalar('SELECT count(*) FROM ventas.ventas')), 4);
  await db.query("UPDATE ventas.ventas SET notas='Nota corregida' WHERE id=$1", [nueva]);
  assert.equal(await scalar('SELECT notas FROM ventas.v_ventas WHERE id=$1', [nueva]), 'Nota corregida');
  await assert.rejects(pago(ruta, 1, 0, 'vendedor'), /privileges/);
  await assert.rejects(pago(ruta, 0, 14), /exceeds/);
  await assert.rejects(pago(ruta, -1, 1), /invalid/);
  await pago(ruta, 8, 5);
  const cerrada = (await db.query('SELECT * FROM rutas.rutas WHERE id=$1', [ruta])).rows[0];
  assert.equal(Number(cerrada.monto_total), 8);
  assert.equal(Number(cerrada.monto_cobrado), 8);
  assert.equal(cerrada.estado, 'pagado');
  assert.ok(cerrada.notas.includes('Descuento: 5.00'));
  assert.equal(Number(await scalar('SELECT sum(monto) FROM rutas.abonos')), 8);
  await assert.rejects(pago(ruta, 1, 0), /already paid/);
  const otra = await venta([item(5)]);
  const ruta2 = await scalar('SELECT ruta_id FROM ventas.ventas WHERE id=$1', [otra]);
  assert.notEqual(ruta2, ruta);
  await pago(ruta2, 0, 5);
  assert.equal(Number(await scalar('SELECT monto_total FROM rutas.rutas WHERE id=$1', [ruta2])), 0);
  assert.equal(await scalar('SELECT estado FROM rutas.rutas WHERE id=$1', [ruta2]), 'pagado');
  assert.equal(Number(await scalar('SELECT count(*) FROM rutas.abonos WHERE ruta_id=$1', [ruta2])), 0);
  const productoOliver = await scalar("INSERT INTO inventario.productos(nombre, precio, stock) VALUES ('Bidon Oliver', 0.53, 1000) RETURNING id");
  const saldoPrevio = await scalar("INSERT INTO rutas.rutas(vendedor_id, monto_total, monto_cobrado, estado) VALUES ($1, 10, 24.83, 'pagado') RETURNING id", [oliver]);
  const sinCredito = await venta([{producto_id: productoOliver, cantidad: 195}], oliver);
  const ventaNormal = (await db.query('SELECT total, credito_aplicado FROM ventas.ventas WHERE id=$1', [sinCredito])).rows[0];
  assert.equal(Number(ventaNormal.total), 103.35);
  assert.equal(Number(ventaNormal.credito_aplicado), 0);
  assert.equal(Number(await scalar('SELECT monto_cobrado FROM rutas.rutas WHERE id=$1', [saldoPrevio])), 24.83);
  const conCredito = await venta([{producto_id: productoOliver, cantidad: 195}], oliver, 'admin', '2026-10-04', true);
  assert.equal(Number(await scalar('SELECT credito_aplicado FROM ventas.ventas WHERE id=$1', [conCredito])), 14.83);
  assert.equal(Number(await scalar('SELECT monto_cobrado FROM rutas.rutas WHERE id=$1', [saldoPrevio])), 10);
  await assert.rejects(pago(ruta2, 1, 0, 'sesion-inexistente'), /invalid session/);
  const saldoDespacho = readFileSync('supabase/parche_saldo_favor_despacho.sql', 'utf8');
  await db.exec(saldoDespacho);
  await db.exec(saldoDespacho);
  const vendedorCredito = await scalar("INSERT INTO vendedores.vendedores(nombre) VALUES ('Credito despacho') RETURNING id");
  const crearRuta = (total, cobrado, vendedor = vendedorCredito) => scalar(
    "INSERT INTO rutas.rutas(vendedor_id,monto_total,monto_cobrado,estado) VALUES ($1,$2::numeric,$3::numeric,CASE WHEN $3::numeric >= $2::numeric THEN 'pagado' ELSE 'pendiente' END) RETURNING id",
    [vendedor, total, cobrado]);
  const origen = await crearRuta(10, 30);
  const destino = await crearRuta(100, 0);
  const aplicar = (ruta, credito, efectivo = 0, descuento = 0, operacion = randomUUID(), rol = 'admin') => scalar(
    'SELECT rutas.fn_registrar_pago_con_saldo($1,$2,$3,$4,$5,$6,$7)',
    [rol, ruta, operacion, credito, efectivo, descuento, 'Prueba credito despacho']);
  const op = randomUUID();
  await aplicar(destino, 20, 10, 5, op);
  assert.equal(Number(await scalar('SELECT monto_total FROM rutas.rutas WHERE id=$1', [destino])), 75);
  assert.equal(Number(await scalar('SELECT monto_cobrado FROM rutas.rutas WHERE id=$1', [destino])), 10);
  assert.equal(Number(await scalar('SELECT monto_cobrado FROM rutas.rutas WHERE id=$1', [origen])), 10);
  await aplicar(destino, 20, 10, 5, op); // Reintento: no segundo descuento ni segundo abono.
  assert.equal(Number(await scalar('SELECT count(*) FROM rutas.abonos WHERE ruta_id=$1', [destino])), 1);
  await assert.rejects(aplicar(destino, 1, 0, 0, op), /does not match/);
  await assert.rejects(aplicar(destino, 1), /credit balance changed/);
  assert.equal(Number(await scalar('SELECT monto_total FROM rutas.rutas WHERE id=$1', [destino])), 75);
  await assert.rejects(aplicar(destino, 1, 0, 0, randomUUID(), 'vendedor'), /privileges/);
  for (const invalid of [-1, 0, 'NaN', 'Infinity']) {
    await assert.rejects(aplicar(destino, invalid), /invalid payment or credit/);
  }
  const saldoExtra = await crearRuta(0, 80);
  const opCompleta = randomUUID();
  await aplicar(destino, 65, 0, 0, opCompleta, 'planta');
  assert.equal(await scalar('SELECT estado FROM rutas.rutas WHERE id=$1', [destino]), 'pagado');
  assert.equal(Number(await scalar('SELECT monto_cobrado FROM rutas.rutas WHERE id=$1', [saldoExtra])), 15);
  await aplicar(destino, 65, 0, 0, opCompleta, 'planta');
  const sinCreditoOtro = await crearRuta(50, 0, seller);
  await assert.rejects(aplicar(sinCreditoOtro, 1), /credit balance changed/);
  // La venta posterior solo puede consumir los 15 que quedaron, no los 65 ya aplicados.
  const posterior = await venta([item(10)], vendedorCredito, 'admin', '2026-10-19', true);
  assert.equal(Number(await scalar('SELECT credito_aplicado FROM ventas.ventas WHERE id=$1', [posterior])), 15);
  assert.equal(Number(await scalar('SELECT monto_cobrado FROM rutas.rutas WHERE id=$1', [saldoExtra])), 0);
  assert.equal(Number(await scalar('SELECT count(*) FROM rutas.aplicaciones_saldo')), 2);
  assert.equal(Number(await scalar('SELECT sum(monto) FROM rutas.aplicaciones_saldo')), 85);
  console.log('SQL OK: ventas y despachos, saldo parcial/total, remanente, reintentos, rollback, sesiones y permisos.');
} finally {
  await db.close();
}
