-- Agua Milena 1.0.5: ejecutar en SQL Editor sobre la base existente.
-- Conserva productos, vendedores, ventas, rutas y usuarios.
BEGIN;

CREATE TABLE IF NOT EXISTS inventario.precios_producto (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id uuid NOT NULL REFERENCES inventario.productos(id) ON DELETE CASCADE,
  vendedor_id uuid REFERENCES vendedores.vendedores(id) ON DELETE CASCADE,
  precio numeric(10,2) NOT NULL CHECK (precio >= 0),
  creado_en timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (producto_id, vendedor_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_precio_producto_contexto
ON inventario.precios_producto (producto_id, vendedor_id) NULLS NOT DISTINCT;

ALTER TABLE ventas.items_venta ADD COLUMN IF NOT EXISTS devolucion integer NOT NULL DEFAULT 0;
ALTER TABLE ventas.items_venta DROP CONSTRAINT IF EXISTS items_venta_cantidad_check;
ALTER TABLE ventas.items_venta ADD CONSTRAINT items_venta_cantidad_check CHECK (cantidad >= 0);
ALTER TABLE ventas.items_venta DROP CONSTRAINT IF EXISTS items_venta_devolucion_check;
ALTER TABLE ventas.items_venta ADD CONSTRAINT items_venta_devolucion_check CHECK (devolucion >= 0);
ALTER TABLE ventas.items_venta DROP CONSTRAINT IF EXISTS items_venta_operacion_check;
ALTER TABLE ventas.items_venta ADD CONSTRAINT items_venta_operacion_check CHECK (cantidad > 0 OR devolucion > 0);

ALTER TABLE inventario.precios_producto ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON inventario.precios_producto TO anon, authenticated;
DROP POLICY IF EXISTS app_select ON inventario.precios_producto;
DROP POLICY IF EXISTS app_insert ON inventario.precios_producto;
DROP POLICY IF EXISTS app_update ON inventario.precios_producto;
DROP POLICY IF EXISTS app_delete ON inventario.precios_producto;
CREATE POLICY app_select ON inventario.precios_producto FOR SELECT TO anon, authenticated
USING (usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta']));
CREATE POLICY app_insert ON inventario.precios_producto FOR INSERT TO anon, authenticated
WITH CHECK (usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta']));
CREATE POLICY app_update ON inventario.precios_producto FOR UPDATE TO anon, authenticated
USING (usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta']))
WITH CHECK (usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta']));
CREATE POLICY app_delete ON inventario.precios_producto FOR DELETE TO anon, authenticated
USING (usuarios.fn_sesion_header_tiene_rol(ARRAY['admin']));

CREATE OR REPLACE VIEW ventas.v_ventas AS
SELECT
  v.*,
  vd.nombre AS nombre_vendedor,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', iv.id,
          'venta_id', iv.venta_id,
          'producto_id', iv.producto_id,
          'nombre_producto', p.nombre,
          'cantidad', iv.cantidad,
          'devolucion', iv.devolucion,
          'precio_unitario', iv.precio_unitario,
          'subtotal', iv.subtotal
        )
        ORDER BY iv.id
      )
      FROM ventas.items_venta iv
      LEFT JOIN inventario.productos p ON p.id = iv.producto_id
      WHERE iv.venta_id = v.id
    ),
    '[]'::jsonb
  ) AS items_json
FROM ventas.ventas v
LEFT JOIN vendedores.vendedores vd ON vd.id = v.vendedor_id;

CREATE OR REPLACE FUNCTION ventas.fn_crear_venta_segura(
  p_session_token text,
  p_items jsonb,
  p_notas text DEFAULT NULL,
  p_vendedor_id uuid DEFAULT NULL,
  p_fecha date DEFAULT CURRENT_DATE,
  p_bidones_llenos_en_carro integer DEFAULT 0,
  p_bidones_vacios_recibidos integer DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ventas, rutas, inventario, vendedores, usuarios, public, extensions
AS $$
DECLARE
  ctx record;
  item jsonb;
  producto record;
  vendedor record;
  venta_id uuid;
  ruta_id uuid;
  v_producto_id uuid;
  cantidad integer;
  total numeric := 0;
  subtotal numeric;
  bidones_cargados integer := 0;
  credito_aplicado numeric := 0;
  saldo_favor numeric := 0;
  restante_credito numeric := 0;
  ruta_credito record;
  nuevos_llenos integer := 0;
  nuevos_prestados integer := 0;
  fecha_venta date := COALESCE(p_fecha, CURRENT_DATE);
  precio_unitario numeric;
  devolucion integer;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  IF ctx.rol NOT IN ('admin', 'planta') THEN
    RAISE EXCEPTION 'admin or planta privileges required' USING ERRCODE = '42501';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'sale items are required' USING ERRCODE = '22023';
  END IF;

  IF (SELECT COUNT(DISTINCT value->>'producto_id') FROM jsonb_array_elements(p_items))
      <> jsonb_array_length(p_items) THEN
    RAISE EXCEPTION 'duplicate products are not allowed' USING ERRCODE = '22023';
  END IF;

  -- Lock the seller first so simultaneous sales share the same active route.
  IF p_vendedor_id IS NOT NULL THEN
    PERFORM 1 FROM vendedores.vendedores WHERE id = p_vendedor_id FOR UPDATE;
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(p_items) ORDER BY value->>'producto_id'
  LOOP
    v_producto_id := (item->>'producto_id')::uuid;
    cantidad := COALESCE((item->>'cantidad')::integer, 0);
    devolucion := COALESCE((item->>'devolucion')::integer, 0);

    IF cantidad < 0 OR devolucion < 0 OR cantidad + devolucion = 0
        OR (devolucion > 0 AND p_vendedor_id IS NULL) THEN
      RAISE EXCEPTION 'invalid item quantity' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO producto
    FROM inventario.productos
    WHERE id = v_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'product not found' USING ERRCODE = 'P0002';
    END IF;

    IF producto.stock < cantidad - devolucion THEN
      RAISE EXCEPTION 'insufficient stock for %', producto.nombre
        USING ERRCODE = '23514';
    END IF;

    -- Obtener precio dinamico de inventario.precios_producto (vendedor -> distribuidora -> base)
    SELECT COALESCE(
      (SELECT pp.precio FROM inventario.precios_producto pp WHERE pp.producto_id = v_producto_id AND pp.vendedor_id = p_vendedor_id),
      (SELECT pp.precio FROM inventario.precios_producto pp WHERE pp.producto_id = v_producto_id AND pp.vendedor_id IS NULL),
      producto.precio
    ) INTO precio_unitario;

    subtotal := precio_unitario * (cantidad - devolucion);
    total := total + subtotal;

    IF lower(producto.nombre || ' ' || producto.unidad) LIKE '%bid%' THEN
      bidones_cargados := bidones_cargados + cantidad;
    END IF;
  END LOOP;

  total := GREATEST(total, 0);

  IF p_vendedor_id IS NOT NULL THEN
    SELECT * INTO vendedor
    FROM vendedores.vendedores
    WHERE id = p_vendedor_id
    FOR UPDATE;

    IF NOT FOUND OR vendedor.activo IS NOT TRUE THEN
      RAISE EXCEPTION 'seller not found or inactive' USING ERRCODE = 'P0002';
    END IF;

    SELECT COALESCE(SUM(GREATEST(monto_cobrado - monto_total, 0)), 0)
    INTO saldo_favor
    FROM rutas.rutas
    WHERE vendedor_id = p_vendedor_id;

    credito_aplicado := GREATEST(LEAST(saldo_favor, total), 0);

    SELECT id INTO ruta_id
    FROM rutas.rutas
    WHERE vendedor_id = p_vendedor_id
      AND estado IN ('sin_cierre', 'pendiente', 'parcial')
    ORDER BY fecha ASC, creado_en ASC
    LIMIT 1
    FOR UPDATE;

    IF ruta_id IS NULL THEN
-- Datos INSERT omitidos para portafolio.

    END IF;
  END IF;
-- Datos INSERT omitidos para portafolio.


  FOR item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_producto_id := (item->>'producto_id')::uuid;
    cantidad := COALESCE((item->>'cantidad')::integer, 0);
    devolucion := COALESCE((item->>'devolucion')::integer, 0);

    SELECT * INTO producto
    FROM inventario.productos
    WHERE id = v_producto_id;

    SELECT COALESCE(
      (SELECT pp.precio FROM inventario.precios_producto pp WHERE pp.producto_id = v_producto_id AND pp.vendedor_id = p_vendedor_id),
      (SELECT pp.precio FROM inventario.precios_producto pp WHERE pp.producto_id = v_producto_id AND pp.vendedor_id IS NULL),
      producto.precio
    ) INTO precio_unitario;
-- Datos INSERT omitidos para portafolio.


    UPDATE inventario.productos
    SET stock = stock - cantidad + devolucion,
        actualizado_en = now()
    WHERE id = v_producto_id;

    IF cantidad > 0 THEN
-- Datos INSERT omitidos para portafolio.

    END IF;
    IF devolucion > 0 THEN
-- Datos INSERT omitidos para portafolio.

    END IF;
  END LOOP;

  IF p_vendedor_id IS NOT NULL THEN
    nuevos_llenos := GREATEST(COALESCE(p_bidones_llenos_en_carro, 0), 0) + bidones_cargados;
    nuevos_prestados := GREATEST(nuevos_llenos - COALESCE(vendedor.bidones_propios, 0), 0);

    UPDATE vendedores.vendedores
    SET bidones_llenos_actuales = nuevos_llenos,
        bidones_vacios_actuales = 0,
        bidones_prestados = nuevos_prestados
    WHERE id = p_vendedor_id;

    UPDATE rutas.rutas
    SET monto_total = monto_total + GREATEST(total - credito_aplicado, 0),
        bidones_cargados_hoy = bidones_cargados_hoy + bidones_cargados,
        estado = CASE WHEN monto_cobrado > 0 THEN 'parcial' ELSE 'pendiente' END
    WHERE id = ruta_id;

    restante_credito := credito_aplicado;
    FOR ruta_credito IN
      SELECT id, monto_total, monto_cobrado
      FROM rutas.rutas
      WHERE vendedor_id = p_vendedor_id
        AND monto_cobrado > monto_total
      ORDER BY creado_en ASC
      FOR UPDATE
    LOOP
      EXIT WHEN restante_credito <= 0;

      subtotal := LEAST(ruta_credito.monto_cobrado - ruta_credito.monto_total, restante_credito);
      UPDATE rutas.rutas
      SET monto_cobrado = monto_cobrado - subtotal
      WHERE id = ruta_credito.id;

      restante_credito := restante_credito - subtotal;
    END LOOP;
  END IF;

  RETURN venta_id;
END;
$$;

CREATE OR REPLACE FUNCTION rutas.fn_registrar_pago_con_descuento(
  p_session_token text, p_ruta_id uuid, p_monto numeric,
  p_descuento numeric DEFAULT 0, p_nota text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rutas, usuarios, public
AS $$
DECLARE
  ctx record;
  ruta record;
  nuevo_total numeric;
  nuevo_cobrado numeric;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);
  IF ctx.rol NOT IN ('admin', 'planta') THEN
    RAISE EXCEPTION 'admin or planta privileges required' USING ERRCODE = '42501';
  END IF;
  IF p_monto IS NULL OR p_descuento IS NULL OR p_monto < 0 OR p_descuento < 0
      OR round(p_monto + p_descuento, 2) <= 0
      OR p_monto::text IN ('NaN', 'Infinity', '-Infinity')
      OR p_descuento::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'invalid payment or discount' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO ruta FROM rutas.rutas WHERE id = p_ruta_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'route not found' USING ERRCODE = 'P0002';
  END IF;
  IF ruta.estado = 'pagado' THEN
    RAISE EXCEPTION 'route is already paid' USING ERRCODE = '23514';
  END IF;
  IF round(p_descuento, 2) > GREATEST(ruta.monto_total - ruta.monto_cobrado, 0) THEN
    RAISE EXCEPTION 'discount exceeds pending balance' USING ERRCODE = '23514';
  END IF;
  nuevo_total := ruta.monto_total - round(p_descuento, 2);
  nuevo_cobrado := ruta.monto_cobrado + round(p_monto, 2);
  IF round(p_monto, 2) > 0 THEN
-- Datos INSERT omitidos para portafolio.

  END IF;
  UPDATE rutas.rutas
  SET monto_total = nuevo_total,
      monto_cobrado = nuevo_cobrado,
      estado = CASE WHEN nuevo_cobrado >= nuevo_total THEN 'pagado'
                    WHEN nuevo_cobrado > 0 THEN 'parcial' ELSE 'pendiente' END,
      notas = CASE WHEN p_descuento > 0
        THEN concat_ws(chr(10), NULLIF(notas, ''),
          'Descuento: ' || round(p_descuento, 2)::text ||
          COALESCE(' - ' || NULLIF(btrim(p_nota), ''), ''))
        ELSE notas END
  WHERE id = p_ruta_id;
  RETURN p_ruta_id;
END;
$$;
REVOKE ALL ON FUNCTION rutas.fn_registrar_pago_con_descuento(text, uuid, numeric, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rutas.fn_registrar_pago_con_descuento(text, uuid, numeric, numeric, text) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

