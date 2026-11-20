-- Aplicación explícita y atómica del crédito al total de un despacho.
BEGIN;

CREATE TABLE IF NOT EXISTS rutas.aplicaciones_saldo (
  operacion_id uuid PRIMARY KEY,
  ruta_id uuid NOT NULL REFERENCES rutas.rutas(id) ON DELETE RESTRICT,
  usuario_id uuid NOT NULL,
  monto numeric(10,2) NOT NULL CHECK (monto > 0),
  efectivo numeric(10,2) NOT NULL CHECK (efectivo >= 0),
  descuento numeric(10,2) NOT NULL CHECK (descuento >= 0),
  origenes jsonb NOT NULL,
  creado_en timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE rutas.aplicaciones_saldo ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rutas.aplicaciones_saldo FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION rutas.fn_registrar_pago_con_saldo(
  p_session_token text, p_ruta_id uuid, p_operacion_id uuid,
  p_credito numeric, p_monto numeric DEFAULT 0,
  p_descuento numeric DEFAULT 0, p_nota text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, rutas, usuarios, vendedores, public, extensions
AS $$
DECLARE
  ctx record;
  destino record;
  origen record;
  previo record;
  vendedor_id_destino uuid;
  disponible numeric;
  restante numeric;
  consumir numeric;
  total_nuevo numeric;
  cobrado_nuevo numeric;
  origenes jsonb := '[]'::jsonb;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);
  IF ctx.rol IS NULL OR ctx.rol NOT IN ('admin', 'planta') THEN
    RAISE EXCEPTION 'admin or planta privileges required' USING ERRCODE = '42501';
  END IF;
  IF p_operacion_id IS NULL OR p_credito IS NULL OR p_monto IS NULL
     OR p_descuento IS NULL OR round(p_credito, 2) <= 0
     OR p_monto < 0 OR p_descuento < 0
     OR p_credito::text IN ('NaN', 'Infinity', '-Infinity')
     OR p_monto::text IN ('NaN', 'Infinity', '-Infinity')
     OR p_descuento::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'invalid payment or credit' USING ERRCODE = '22023';
  END IF;

  SELECT vendedor_id INTO vendedor_id_destino FROM rutas.rutas WHERE id = p_ruta_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'route not found' USING ERRCODE = 'P0002';
  END IF;
  -- Mismo bloqueo que ventas.fn_crear_venta_segura: serializa venta y despacho.
  PERFORM 1 FROM vendedores.vendedores WHERE id = vendedor_id_destino FOR UPDATE;
  SELECT * INTO previo FROM rutas.aplicaciones_saldo WHERE operacion_id = p_operacion_id;
  IF FOUND THEN
    IF previo.ruta_id <> p_ruta_id OR previo.usuario_id <> ctx.id
       OR previo.monto <> round(p_credito, 2)
       OR previo.efectivo <> round(p_monto, 2)
       OR previo.descuento <> round(p_descuento, 2) THEN
      RAISE EXCEPTION 'operation does not match previous request' USING ERRCODE = '22023';
    END IF;
    RETURN p_ruta_id;
  END IF;

  SELECT * INTO destino FROM rutas.rutas WHERE id = p_ruta_id FOR UPDATE;
  IF destino.estado = 'pagado' THEN
    RAISE EXCEPTION 'route is already paid' USING ERRCODE = '23514';
  END IF;
  IF round(p_descuento, 2) + round(p_credito, 2) >
      GREATEST(destino.monto_total - destino.monto_cobrado, 0) THEN
    RAISE EXCEPTION 'credit or discount exceeds pending balance' USING ERRCODE = '23514';
  END IF;

  PERFORM id FROM rutas.rutas
  WHERE vendedor_id = vendedor_id_destino AND id <> p_ruta_id
    AND monto_cobrado > monto_total
  ORDER BY creado_en, id FOR UPDATE;
  SELECT COALESCE(SUM(GREATEST(monto_cobrado - monto_total, 0)), 0)
  INTO disponible FROM rutas.rutas
  WHERE vendedor_id = vendedor_id_destino AND id <> p_ruta_id;
  IF round(p_credito, 2) > disponible THEN
    RAISE EXCEPTION 'credit balance changed; reload route' USING ERRCODE = '23514';
  END IF;

  restante := round(p_credito, 2);
  FOR origen IN SELECT id, monto_cobrado, monto_total FROM rutas.rutas
    WHERE vendedor_id = vendedor_id_destino AND id <> p_ruta_id
      AND monto_cobrado > monto_total ORDER BY creado_en, id FOR UPDATE
  LOOP
    EXIT WHEN restante <= 0;
    consumir := LEAST(origen.monto_cobrado - origen.monto_total, restante);
    UPDATE rutas.rutas SET monto_cobrado = monto_cobrado - consumir,
      notas = concat_ws(chr(10), NULLIF(notas, ''),
        'Saldo a favor transferido: ' || consumir::text || ' al despacho ' || p_ruta_id::text)
    WHERE id = origen.id;
    origenes := origenes || jsonb_build_array(jsonb_build_object('ruta_id', origen.id, 'monto', consumir));
    restante := restante - consumir;
  END LOOP;

  total_nuevo := destino.monto_total - round(p_descuento, 2) - round(p_credito, 2);
  cobrado_nuevo := destino.monto_cobrado + round(p_monto, 2);
  IF round(p_monto, 2) > 0 THEN
-- Datos INSERT omitidos para portafolio.

  END IF;
  UPDATE rutas.rutas SET monto_total = total_nuevo, monto_cobrado = cobrado_nuevo,
    estado = CASE WHEN cobrado_nuevo >= total_nuevo THEN 'pagado'
                  WHEN cobrado_nuevo > 0 THEN 'parcial' ELSE 'pendiente' END,
    notas = concat_ws(chr(10), NULLIF(notas, ''),
      'Saldo a favor aplicado: ' || round(p_credito, 2)::text,
      CASE WHEN p_descuento > 0 THEN 'Descuento: ' || round(p_descuento, 2)::text END,
      NULLIF(btrim(COALESCE(p_nota, '')), ''))
  WHERE id = p_ruta_id;
-- Datos INSERT omitidos para portafolio.

  RETURN p_ruta_id;
END;
$$;
REVOKE ALL ON FUNCTION rutas.fn_registrar_pago_con_saldo(text, uuid, uuid, numeric, numeric, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rutas.fn_registrar_pago_con_saldo(text, uuid, uuid, numeric, numeric, numeric, text) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
