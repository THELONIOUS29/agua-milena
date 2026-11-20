-- Ejecutar sobre la base existente despues de parche_plan_v1_0_5.sql.
-- Conserva ventas, abonos y saldos historicos. No corrige importes ya registrados.
BEGIN;

ALTER FUNCTION usuarios.fn_usuario_sesion(text)
SET search_path = usuarios, public, extensions;

ALTER TABLE vendedores.vendedores
ADD COLUMN IF NOT EXISTS permite_devoluciones boolean NOT NULL DEFAULT false;

-- El permiso queda asociado al registro del vendedor.
UPDATE vendedores.vendedores
SET permite_devoluciones = lower(btrim(nombre)) ~ '(^|[[:space:]])yovany([[:space:]]|$)';

DROP FUNCTION IF EXISTS ventas.fn_crear_venta_segura(text, jsonb, text, uuid, date, integer, integer);

CREATE OR REPLACE FUNCTION ventas.fn_crear_venta_segura(
  p_session_token text,
  p_items jsonb,
  p_notas text DEFAULT NULL,
  p_vendedor_id uuid DEFAULT NULL,
  p_fecha date DEFAULT CURRENT_DATE,
  p_bidones_llenos_en_carro integer DEFAULT 0,
  p_bidones_vacios_recibidos integer DEFAULT 0,
  p_aplicar_saldo_favor boolean DEFAULT false
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

    IF COALESCE(p_aplicar_saldo_favor, false) THEN
      credito_aplicado := GREATEST(LEAST(saldo_favor, total), 0);
    END IF;

    IF vendedor.permite_devoluciones IS NOT TRUE AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_items) i
      WHERE COALESCE((i->>'devolucion')::integer, 0) > 0
    ) THEN
      RAISE EXCEPTION 'returns are not enabled for this seller' USING ERRCODE = '23514';
    END IF;

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
SET search_path = rutas, usuarios, public, extensions
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

REVOKE ALL ON FUNCTION ventas.fn_crear_venta_segura(text, jsonb, text, uuid, date, integer, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ventas.fn_crear_venta_segura(text, jsonb, text, uuid, date, integer, integer, boolean) TO anon, authenticated;

-- Confirma quien tiene devoluciones habilitadas.
SELECT id, nombre, permite_devoluciones FROM vendedores.vendedores ORDER BY nombre;
NOTIFY pgrst, 'reload schema';
COMMIT;
