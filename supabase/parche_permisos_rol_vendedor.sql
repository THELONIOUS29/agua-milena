BEGIN;

CREATE OR REPLACE FUNCTION usuarios.fn_vendedor_sesion_header()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = usuarios, public, extensions
AS $$
DECLARE
  ctx record;
  token text;
BEGIN
  token := usuarios.fn_session_token_header();
  IF token IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO ctx FROM usuarios.fn_contexto_sesion(token);
  IF ctx.rol <> 'vendedor' THEN
    RETURN NULL;
  END IF;

  RETURN ctx.vendedor_id;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$;

DO $$
DECLARE
  fila record;
BEGIN
  FOR fila IN
    SELECT * FROM (
      VALUES
        ('inventario', 'productos'),
        ('inventario', 'movimientos_inventario'),
        ('inventario', 'alertas'),
        ('inventario', 'predicciones_modelo_alertas'),
        ('inventario', 'configuracion_app'),
        ('vendedores', 'vendedores'),
        ('ventas', 'ventas'),
        ('ventas', 'items_venta'),
        ('rutas', 'rutas'),
        ('rutas', 'items_ruta'),
        ('rutas', 'abonos'),
        ('auditoria', 'log_auditoria')
    ) AS t(esquema, tabla)
  LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS app_select ON %I.%I',
      fila.esquema,
      fila.tabla
    );
    EXECUTE format(
      'CREATE POLICY app_select ON %I.%I FOR SELECT TO anon, authenticated USING (usuarios.fn_sesion_header_tiene_rol(ARRAY[''admin'', ''planta'']))',
      fila.esquema,
      fila.tabla
    );
  END LOOP;
END $$;

DROP POLICY app_select ON vendedores.vendedores;
CREATE POLICY app_select ON vendedores.vendedores
FOR SELECT TO anon, authenticated
USING (
  usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
  OR id = usuarios.fn_vendedor_sesion_header()
);

DROP POLICY app_select ON rutas.rutas;
CREATE POLICY app_select ON rutas.rutas
FOR SELECT TO anon, authenticated
USING (
  usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
  OR vendedor_id = usuarios.fn_vendedor_sesion_header()
);

DROP POLICY app_select ON rutas.items_ruta;
CREATE POLICY app_select ON rutas.items_ruta
FOR SELECT TO anon, authenticated
USING (
  usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
  OR EXISTS (
    SELECT 1
    FROM rutas.rutas r
    WHERE r.id = items_ruta.ruta_id
      AND r.vendedor_id = usuarios.fn_vendedor_sesion_header()
  )
);

DROP POLICY app_select ON rutas.abonos;
CREATE POLICY app_select ON rutas.abonos
FOR SELECT TO anon, authenticated
USING (
  usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
  OR EXISTS (
    SELECT 1
    FROM rutas.rutas r
    WHERE r.id = abonos.ruta_id
      AND r.vendedor_id = usuarios.fn_vendedor_sesion_header()
  )
);

DROP POLICY app_select ON ventas.ventas;
CREATE POLICY app_select ON ventas.ventas
FOR SELECT TO anon, authenticated
USING (
  usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
  OR vendedor_id = usuarios.fn_vendedor_sesion_header()
);

GRANT EXECUTE ON FUNCTION usuarios.fn_vendedor_sesion_header()
TO anon, authenticated;

COMMIT;
