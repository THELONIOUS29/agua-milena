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
  producto_id uuid;
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
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  IF ctx.rol NOT IN ('admin', 'planta') THEN
    RAISE EXCEPTION 'admin or planta privileges required' USING ERRCODE = '42501';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'sale items are required' USING ERRCODE = '22023';
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    producto_id := (item->>'producto_id')::uuid;
    cantidad := COALESCE((item->>'cantidad')::integer, 0);

    IF cantidad <= 0 THEN
      RAISE EXCEPTION 'invalid item quantity' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO producto
    FROM inventario.productos
    WHERE id = producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'product not found' USING ERRCODE = 'P0002';
    END IF;

    IF producto.stock < cantidad THEN
      RAISE EXCEPTION 'insufficient stock for %', producto.nombre
        USING ERRCODE = '23514';
    END IF;

    subtotal := producto.precio * cantidad;
    total := total + subtotal;

    IF lower(producto.nombre || ' ' || producto.unidad) LIKE '%bid%' THEN
      bidones_cargados := bidones_cargados + cantidad;
    END IF;
  END LOOP;

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
    producto_id := (item->>'producto_id')::uuid;
    cantidad := COALESCE((item->>'cantidad')::integer, 0);

    SELECT * INTO producto
    FROM inventario.productos
    WHERE id = producto_id;
-- Datos INSERT omitidos para portafolio.


    UPDATE inventario.productos
    SET stock = stock - cantidad,
        actualizado_en = now()
    WHERE id = producto_id;
-- Datos INSERT omitidos para portafolio.

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

GRANT EXECUTE ON FUNCTION ventas.fn_crear_venta_segura(text, jsonb, text, uuid, date, integer, integer) TO anon, authenticated;
