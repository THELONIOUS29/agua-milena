-- ============================================================================
-- AGUA MILENA APP - BASE DE DATOS COMPLETA
-- Ejecutar una sola vez en Supabase SQL Editor para una base nueva.
--
-- IMPORTANTE:
-- - Este archivo borra y recrea los esquemas propios de la app.
-- - Mantiene Storage, pero recrea buckets y policies necesarios.
-- - La app usa autenticación propia por RPC. Por eso las tablas operativas
--   quedan accesibles para la anon key; las tablas de usuarios quedan cerradas.
-- ============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

DO $$
BEGIN
  IF current_setting('agua_milena.permitir_reset_total', true) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION
      'Este script borra inventario, ventas, rutas, vendedores, auditoria y usuarios. Para una base nueva, ejecuta antes: SET agua_milena.permitir_reset_total = ''true'';';
  END IF;
END $$;

DROP SCHEMA IF EXISTS inventario CASCADE;
DROP SCHEMA IF EXISTS ventas CASCADE;
DROP SCHEMA IF EXISTS vendedores CASCADE;
DROP SCHEMA IF EXISTS rutas CASCADE;
DROP SCHEMA IF EXISTS auditoria CASCADE;
DROP SCHEMA IF EXISTS usuarios CASCADE;

CREATE SCHEMA inventario;
CREATE SCHEMA ventas;
CREATE SCHEMA vendedores;
CREATE SCHEMA rutas;
CREATE SCHEMA auditoria;
CREATE SCHEMA usuarios;

DO $$
DECLARE
  esquema text;
BEGIN
  FOREACH esquema IN ARRAY ARRAY['inventario', 'ventas', 'vendedores', 'rutas', 'auditoria', 'usuarios']
  LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role', esquema);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO service_role', esquema);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT USAGE, SELECT ON SEQUENCES TO service_role', esquema);
  END LOOP;
END $$;

-- ============================================================================
-- INVENTARIO
-- ============================================================================

CREATE TABLE inventario.productos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre text NOT NULL,
  descripcion text,
  unidad text NOT NULL DEFAULT 'unidad',
  precio numeric(10,2) NOT NULL DEFAULT 0 CHECK (precio >= 0),
  stock integer NOT NULL DEFAULT 0 CHECK (stock >= 0),
  stock_minimo integer NOT NULL DEFAULT 5 CHECK (stock_minimo >= 0),
  stock_bajo_calculado integer,
  url_imagen text,
  catalogo text NOT NULL DEFAULT 'distribuidora'
    CHECK (catalogo IN ('distribuidora', 'vendedor')),
  creado_en timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  UNIQUE (nombre, catalogo)
);

CREATE INDEX idx_productos_catalogo ON inventario.productos(catalogo);
CREATE INDEX idx_productos_nombre ON inventario.productos(nombre);

CREATE OR REPLACE FUNCTION inventario.fn_calcular_stock_bajo(
  p_stock integer,
  p_stock_minimo integer
)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT GREATEST(
    COALESCE(p_stock_minimo, 0),
    COALESCE(p_stock_minimo, 0)
      + GREATEST(1, CEIL(GREATEST(COALESCE(p_stock, 0), 0) * 0.10)::integer)
  );
$$;

CREATE OR REPLACE FUNCTION inventario.fn_actualizar_stock_bajo_calculado()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.stock_bajo_calculado := inventario.fn_calcular_stock_bajo(
      NEW.stock,
      NEW.stock_minimo
    );
    RETURN NEW;
  END IF;

  IF NEW.stock_minimo IS DISTINCT FROM OLD.stock_minimo
     OR NEW.stock > OLD.stock
     OR NEW.stock_bajo_calculado IS NULL THEN
    NEW.stock_bajo_calculado := inventario.fn_calcular_stock_bajo(
      NEW.stock,
      NEW.stock_minimo
    );
  ELSE
    NEW.stock_bajo_calculado := OLD.stock_bajo_calculado;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actualizar_stock_bajo_calculado
BEFORE INSERT OR UPDATE OF stock, stock_minimo, stock_bajo_calculado
ON inventario.productos
FOR EACH ROW
EXECUTE FUNCTION inventario.fn_actualizar_stock_bajo_calculado();

CREATE TABLE inventario.movimientos_inventario (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id uuid NOT NULL REFERENCES inventario.productos(id) ON DELETE CASCADE,
  tipo text NOT NULL CHECK (tipo IN ('entrada', 'salida')),
  cantidad integer NOT NULL CHECK (cantidad > 0),
  motivo text,
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_movimientos_producto ON inventario.movimientos_inventario(producto_id);
CREATE INDEX idx_movimientos_creado ON inventario.movimientos_inventario(creado_en DESC);
CREATE INDEX idx_movimientos_producto_creado ON inventario.movimientos_inventario(producto_id, creado_en DESC);

CREATE TABLE inventario.alertas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id uuid REFERENCES inventario.productos(id) ON DELETE CASCADE,
  tipo text NOT NULL,
  mensaje text NOT NULL,
  leida boolean NOT NULL DEFAULT false,
  activada_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_alertas_producto ON inventario.alertas(producto_id);
CREATE INDEX idx_alertas_leida ON inventario.alertas(leida);

CREATE TABLE inventario.predicciones_modelo_alertas (
  clave text PRIMARY KEY,
  tipo text NOT NULL CHECK (
    tipo IN (
      'diaria',
      'semanal',
      'mensual',
      'temporada_mes',
      'temporada_semana',
      'temporada_dia'
    )
  ),
  fecha_objetivo date NOT NULL,
  periodo_inicio date,
  periodo_fin date,
  titulo text NOT NULL,
  cuerpo text NOT NULL,
  demanda_bidones integer,
  demanda_fundas integer,
  carga_bidones integer,
  carga_fundas integer,
  riesgo_stock_bajo numeric,
  venta_alta_inesperada numeric,
  dia_pico date,
  temporada_nombre text,
  dias_restantes integer,
  modelo_nombre text,
  origen text NOT NULL DEFAULT 'tflite',
  creado_en timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_predicciones_modelo_tipo_fecha
ON inventario.predicciones_modelo_alertas(tipo, fecha_objetivo);

CREATE INDEX idx_predicciones_modelo_actualizado
ON inventario.predicciones_modelo_alertas(actualizado_en DESC);

CREATE UNIQUE INDEX uq_predicciones_modelo_periodo_principal
ON inventario.predicciones_modelo_alertas(origen, tipo, fecha_objetivo)
WHERE tipo IN ('diaria', 'semanal', 'mensual');

CREATE TABLE inventario.configuracion_app (
  clave text PRIMARY KEY,
  valor_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  actualizado_en timestamptz NOT NULL DEFAULT now()
);
-- Datos INSERT omitidos para portafolio.


-- ============================================================================
-- VENDEDORES
-- ============================================================================

CREATE TABLE vendedores.vendedores (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre text NOT NULL UNIQUE,
  telefono text,
  activo boolean NOT NULL DEFAULT true,
  bidones_propios integer NOT NULL DEFAULT 0 CHECK (bidones_propios >= 0),
  bidones_prestados integer NOT NULL DEFAULT 0 CHECK (bidones_prestados >= 0),
  bidones_llenos_actuales integer NOT NULL DEFAULT 0 CHECK (bidones_llenos_actuales >= 0),
  bidones_vacios_actuales integer NOT NULL DEFAULT 0 CHECK (bidones_vacios_actuales >= 0),
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_vendedores_activo ON vendedores.vendedores(activo);
ALTER TABLE vendedores.vendedores ADD COLUMN permite_devoluciones boolean NOT NULL DEFAULT false;
CREATE INDEX idx_vendedores_nombre ON vendedores.vendedores(nombre);

CREATE TABLE inventario.precios_producto (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  producto_id uuid NOT NULL REFERENCES inventario.productos(id) ON DELETE CASCADE,
  vendedor_id uuid REFERENCES vendedores.vendedores(id) ON DELETE CASCADE,
  precio numeric(10,2) NOT NULL CHECK (precio >= 0),
  creado_en timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT (producto_id, vendedor_id)
);

-- ============================================================================
-- USUARIOS Y SESIONES
-- ============================================================================

CREATE TABLE usuarios.usuarios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email_hash text NOT NULL UNIQUE,
  email_enc bytea NOT NULL,
  nombre text NOT NULL,
  hash_contrasena text NOT NULL,
  rol text NOT NULL DEFAULT 'planta' CHECK (rol IN ('admin', 'planta', 'vendedor')),
  activo boolean NOT NULL DEFAULT true,
  debe_cambiar_contrasena boolean NOT NULL DEFAULT true,
  vendedor_id uuid REFERENCES vendedores.vendedores(id) ON DELETE SET NULL,
  telefono_enc bytea,
  url_avatar text,
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_usuarios_rol ON usuarios.usuarios(rol);
CREATE INDEX idx_usuarios_activo ON usuarios.usuarios(activo);
CREATE INDEX idx_usuarios_vendedor ON usuarios.usuarios(vendedor_id);

CREATE TABLE usuarios.sesiones_app (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id uuid NOT NULL REFERENCES usuarios.usuarios(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expira_en timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  revocada_en timestamptz,
  creado_en timestamptz NOT NULL DEFAULT now(),
  ultimo_acceso timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sesiones_usuario ON usuarios.sesiones_app(usuario_id);
CREATE INDEX idx_sesiones_expira ON usuarios.sesiones_app(expira_en);

CREATE TABLE usuarios.tokens_dispositivo (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id uuid NOT NULL REFERENCES usuarios.usuarios(id) ON DELETE CASCADE,
  token_firebase text NOT NULL UNIQUE,
  plataforma text NOT NULL DEFAULT 'android',
  nombre_dispositivo text,
  activo boolean NOT NULL DEFAULT true,
  creado_en timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  ultimo_uso_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tokens_dispositivo_usuario ON usuarios.tokens_dispositivo(usuario_id);
CREATE INDEX idx_tokens_dispositivo_activo ON usuarios.tokens_dispositivo(activo);

-- ============================================================================
-- VENTAS
-- ============================================================================

CREATE TABLE ventas.ventas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fecha date NOT NULL DEFAULT CURRENT_DATE,
  total numeric(10,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  notas text,
  vendedor_id uuid REFERENCES vendedores.vendedores(id) ON DELETE SET NULL,
  ruta_id uuid,
  credito_aplicado numeric(10,2) NOT NULL DEFAULT 0 CHECK (credito_aplicado >= 0),
  bidones_llenos_en_carro integer NOT NULL DEFAULT 0 CHECK (bidones_llenos_en_carro >= 0),
  bidones_vacios_recibidos integer NOT NULL DEFAULT 0 CHECK (bidones_vacios_recibidos >= 0),
  bidones_prestados_empresa integer NOT NULL DEFAULT 0 CHECK (bidones_prestados_empresa >= 0),
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_ventas_fecha ON ventas.ventas(fecha DESC);
CREATE INDEX idx_ventas_vendedor ON ventas.ventas(vendedor_id);
CREATE INDEX idx_ventas_ruta ON ventas.ventas(ruta_id);
CREATE INDEX idx_ventas_creado ON ventas.ventas(creado_en DESC);
CREATE INDEX idx_ventas_fecha_creado ON ventas.ventas(fecha DESC, creado_en DESC);
CREATE INDEX idx_ventas_vendedor_fecha_creado ON ventas.ventas(vendedor_id, fecha DESC, creado_en DESC);

CREATE TABLE ventas.items_venta (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  venta_id uuid NOT NULL REFERENCES ventas.ventas(id) ON DELETE CASCADE,
  producto_id uuid NOT NULL REFERENCES inventario.productos(id) ON DELETE RESTRICT,
  cantidad integer NOT NULL CHECK (cantidad >= 0),
  precio_unitario numeric(10,2) NOT NULL CHECK (precio_unitario >= 0),
  subtotal numeric(10,2) NOT NULL CHECK (subtotal >= 0),
  devolucion integer NOT NULL DEFAULT 0 CHECK (devolucion >= 0),
  CHECK (cantidad > 0 OR devolucion > 0)
);

CREATE INDEX idx_items_venta_venta ON ventas.items_venta(venta_id);
CREATE INDEX idx_items_venta_producto ON ventas.items_venta(producto_id);

-- ============================================================================
-- RUTAS Y COBROS
-- ============================================================================

CREATE TABLE rutas.rutas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vendedor_id uuid NOT NULL REFERENCES vendedores.vendedores(id) ON DELETE RESTRICT,
  fecha date NOT NULL DEFAULT CURRENT_DATE,
  monto_total numeric(10,2) NOT NULL DEFAULT 0 CHECK (monto_total >= 0),
  monto_cobrado numeric(10,2) NOT NULL DEFAULT 0 CHECK (monto_cobrado >= 0),
  estado text NOT NULL DEFAULT 'sin_cierre'
    CHECK (estado IN ('sin_cierre', 'pendiente', 'parcial', 'pagado')),
  notas text,
  bidones_llenos_iniciales integer NOT NULL DEFAULT 0 CHECK (bidones_llenos_iniciales >= 0),
  bidones_vacios_iniciales integer NOT NULL DEFAULT 0 CHECK (bidones_vacios_iniciales >= 0),
  bidones_cargados_hoy integer NOT NULL DEFAULT 0 CHECK (bidones_cargados_hoy >= 0),
  bidones_retorno_llenos integer CHECK (bidones_retorno_llenos IS NULL OR bidones_retorno_llenos >= 0),
  bidones_retorno_vacios integer CHECK (bidones_retorno_vacios IS NULL OR bidones_retorno_vacios >= 0),
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_rutas_vendedor ON rutas.rutas(vendedor_id);
CREATE INDEX idx_rutas_fecha ON rutas.rutas(fecha DESC);
CREATE INDEX idx_rutas_estado ON rutas.rutas(estado);
CREATE INDEX idx_rutas_creado ON rutas.rutas(creado_en DESC);
CREATE UNIQUE INDEX idx_rutas_unica_abierta_vendedor_fecha
ON rutas.rutas(vendedor_id, fecha)
WHERE estado IN ('sin_cierre', 'pendiente', 'parcial');

CREATE TABLE rutas.items_ruta (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ruta_id uuid NOT NULL REFERENCES rutas.rutas(id) ON DELETE CASCADE,
  producto_id uuid NOT NULL REFERENCES inventario.productos(id) ON DELETE RESTRICT,
  nombre_producto text NOT NULL,
  unidad text NOT NULL DEFAULT 'unidad',
  precio_unitario numeric(10,2) NOT NULL CHECK (precio_unitario >= 0),
  cantidad_salida integer NOT NULL CHECK (cantidad_salida > 0),
  cantidad_sin_vender integer CHECK (cantidad_sin_vender IS NULL OR cantidad_sin_vender >= 0),
  cantidad_retorno_vacio integer CHECK (cantidad_retorno_vacio IS NULL OR cantidad_retorno_vacio >= 0)
);

CREATE INDEX idx_items_ruta_ruta ON rutas.items_ruta(ruta_id);
CREATE INDEX idx_items_ruta_producto ON rutas.items_ruta(producto_id);

CREATE TABLE rutas.abonos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ruta_id uuid NOT NULL REFERENCES rutas.rutas(id) ON DELETE CASCADE,
  monto numeric(10,2) NOT NULL CHECK (monto > 0),
  fecha timestamptz NOT NULL DEFAULT now(),
  nota text
);

CREATE INDEX idx_abonos_ruta ON rutas.abonos(ruta_id);
CREATE INDEX idx_abonos_fecha ON rutas.abonos(fecha DESC);

ALTER TABLE ventas.ventas
  ADD CONSTRAINT ventas_ruta_id_fkey
  FOREIGN KEY (ruta_id) REFERENCES rutas.rutas(id) ON DELETE SET NULL;

-- ============================================================================
-- AUDITORIA
-- ============================================================================

CREATE TABLE auditoria.log_auditoria (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id text,
  usuario_email text,
  accion text NOT NULL CHECK (accion IN ('INSERT', 'UPDATE', 'DELETE')),
  esquema text NOT NULL,
  tabla text NOT NULL,
  registro_id text,
  datos_antes jsonb,
  datos_despues jsonb,
  ip_address text,
  dispositivo text,
  version_app text,
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_log_auditoria_tabla ON auditoria.log_auditoria(tabla);
CREATE INDEX idx_log_auditoria_creado ON auditoria.log_auditoria(creado_en DESC);
CREATE INDEX idx_log_auditoria_usuario ON auditoria.log_auditoria(usuario_id);

CREATE TABLE auditoria.log_error (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id text,
  nivel text NOT NULL DEFAULT 'error' CHECK (nivel IN ('warning', 'error', 'fatal')),
  mensaje text NOT NULL,
  stack_trace text,
  pantalla text,
  endpoint text,
  dispositivo text,
  version_os text,
  version_app text,
  metadata jsonb,
  creado_en timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_log_error_nivel ON auditoria.log_error(nivel);
CREATE INDEX idx_log_error_creado ON auditoria.log_error(creado_en DESC);

-- ============================================================================
-- CONFIGURACION REMOTA DE VERSIONES
-- ============================================================================

CREATE TABLE inventario.versiones_aplicacion (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plataforma text NOT NULL CHECK (plataforma IN ('android', 'ios', 'web')),
  version_actual text NOT NULL DEFAULT '1.0.2',
  numero_compilacion_actual integer NOT NULL DEFAULT 2004,
  version_minima text NOT NULL DEFAULT '1.0.2',
  numero_compilacion_minima integer NOT NULL DEFAULT 2004,
  url_actualizacion text NOT NULL,
  mensaje_actualizacion text NOT NULL DEFAULT 'Hay una nueva version de Agua Milena disponible.',
  actualizacion_obligatoria boolean NOT NULL DEFAULT false,
  modo_mantenimiento boolean NOT NULL DEFAULT false,
  mensaje_mantenimiento text NOT NULL DEFAULT 'La aplicacion esta en mantenimiento. Volveremos pronto.',
  activa boolean NOT NULL DEFAULT true,
  creado_en timestamptz NOT NULL DEFAULT now(),
  actualizado_en timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plataforma)
);
-- Datos INSERT omitidos para portafolio.


-- ============================================================================
-- VISTAS PARA LA APP MOVIL
-- ============================================================================

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

CREATE OR REPLACE FUNCTION ventas.fn_resumen_ventas(
  p_fecha_inicio date,
  p_fecha_fin date,
  p_vendedor_id uuid DEFAULT NULL,
  p_solo_distribuidora boolean DEFAULT false
)
RETURNS TABLE(cantidad bigint, total numeric)
LANGUAGE sql
STABLE
AS $$
  SELECT
    COUNT(*)::bigint AS cantidad,
    COALESCE(SUM(v.total), 0)::numeric AS total
  FROM ventas.ventas v
  WHERE v.fecha >= p_fecha_inicio
    AND v.fecha <= p_fecha_fin
    AND (
      (p_solo_distribuidora AND v.vendedor_id IS NULL)
      OR (
        NOT p_solo_distribuidora
        AND (p_vendedor_id IS NULL OR v.vendedor_id = p_vendedor_id)
      )
    );
$$;

CREATE OR REPLACE FUNCTION inventario.fn_registrar_movimiento_seguro(
  p_session_token text,
  p_producto_id uuid,
  p_tipo text,
  p_cantidad integer,
  p_motivo text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = inventario, usuarios, public, extensions
AS $$
DECLARE
  ctx record;
  producto record;
  nuevo_stock integer;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  IF ctx.rol NOT IN ('admin', 'planta') THEN
    RAISE EXCEPTION 'admin or planta privileges required' USING ERRCODE = '42501';
  END IF;

  IF p_tipo NOT IN ('entrada', 'salida') THEN
    RAISE EXCEPTION 'invalid movement type' USING ERRCODE = '22023';
  END IF;

  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RAISE EXCEPTION 'invalid quantity' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO producto
  FROM inventario.productos
  WHERE id = p_producto_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'product not found' USING ERRCODE = 'P0002';
  END IF;

  nuevo_stock := CASE
    WHEN p_tipo = 'entrada' THEN producto.stock + p_cantidad
    ELSE producto.stock - p_cantidad
  END;

  IF nuevo_stock < 0 THEN
    RAISE EXCEPTION 'insufficient stock for %', producto.nombre
      USING ERRCODE = '23514';
  END IF;

  UPDATE inventario.productos
  SET stock = nuevo_stock,
      actualizado_en = now()
  WHERE id = p_producto_id;
-- Datos INSERT omitidos para portafolio.


  RETURN jsonb_build_object('id', p_producto_id, 'stock', nuevo_stock);
END;
$$;

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

CREATE OR REPLACE VIEW rutas.v_rutas AS
SELECT
  r.*,
  vd.nombre AS nombre_vendedor,
  vd.bidones_propios AS vendedor_bidones_propios,
  vd.bidones_prestados AS vendedor_bidones_prestados,
  vd.bidones_llenos_actuales AS vendedor_bidones_llenos_actuales,
  vd.bidones_vacios_actuales AS vendedor_bidones_vacios_actuales,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', ir.id,
          'ruta_id', ir.ruta_id,
          'producto_id', ir.producto_id,
          'nombre_producto', ir.nombre_producto,
          'unidad', ir.unidad,
          'precio_unitario', ir.precio_unitario,
          'cantidad_salida', ir.cantidad_salida,
          'cantidad_sin_vender', ir.cantidad_sin_vender,
          'cantidad_retorno_vacio', ir.cantidad_retorno_vacio
        )
        ORDER BY ir.id
      )
      FROM rutas.items_ruta ir
      WHERE ir.ruta_id = r.id
    ),
    '[]'::jsonb
  ) AS items_json,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', vv.id,
          'fecha', vv.fecha,
          'total', vv.total,
          'notas', vv.notas,
          'vendedor_id', vv.vendedor_id,
          'ruta_id', vv.ruta_id,
          'credito_aplicado', vv.credito_aplicado,
          'bidones_llenos_en_carro', vv.bidones_llenos_en_carro,
          'bidones_vacios_recibidos', vv.bidones_vacios_recibidos,
          'bidones_prestados_empresa', vv.bidones_prestados_empresa,
          'creado_en', vv.creado_en,
          'nombre_vendedor', vd.nombre
        )
        ORDER BY vv.creado_en DESC
      )
      FROM ventas.ventas vv
      WHERE vv.ruta_id = r.id
    ),
    '[]'::jsonb
  ) AS ventas_json,
  COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', a.id,
          'ruta_id', a.ruta_id,
          'monto', a.monto,
          'fecha', a.fecha,
          'nota', a.nota
        )
        ORDER BY a.fecha DESC
      )
      FROM rutas.abonos a
      WHERE a.ruta_id = r.id
    ),
    '[]'::jsonb
  ) AS abonos_json
FROM rutas.rutas r
LEFT JOIN vendedores.vendedores vd ON vd.id = r.vendedor_id;

ALTER VIEW ventas.v_ventas SET (security_invoker = true);
ALTER VIEW rutas.v_rutas SET (security_invoker = true);

-- ============================================================================
-- FUNCIONES DE SOPORTE, AUTENTICACION Y AUDITORIA
-- ============================================================================

CREATE OR REPLACE FUNCTION inventario.fn_actualizar_actualizado_en()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.actualizado_en := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_productos_actualizado_en
BEFORE UPDATE ON inventario.productos
FOR EACH ROW EXECUTE FUNCTION inventario.fn_actualizar_actualizado_en();

CREATE TRIGGER trg_configuracion_actualizado_en
BEFORE UPDATE ON inventario.configuracion_app
FOR EACH ROW EXECUTE FUNCTION inventario.fn_actualizar_actualizado_en();

CREATE TRIGGER trg_versiones_aplicacion_actualizado_en
BEFORE UPDATE ON inventario.versiones_aplicacion
FOR EACH ROW EXECUTE FUNCTION inventario.fn_actualizar_actualizado_en();

CREATE OR REPLACE FUNCTION auditoria.fn_trigger_auditoria()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
-- Datos INSERT omitidos para portafolio.

    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
-- Datos INSERT omitidos para portafolio.

    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
-- Datos INSERT omitidos para portafolio.

    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_audit_productos AFTER INSERT OR UPDATE OR DELETE ON inventario.productos FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_movimientos AFTER INSERT OR UPDATE OR DELETE ON inventario.movimientos_inventario FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_alertas AFTER INSERT OR UPDATE OR DELETE ON inventario.alertas FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_vendedores AFTER INSERT OR UPDATE OR DELETE ON vendedores.vendedores FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_ventas AFTER INSERT OR UPDATE OR DELETE ON ventas.ventas FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_items_venta AFTER INSERT OR UPDATE OR DELETE ON ventas.items_venta FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_rutas AFTER INSERT OR UPDATE OR DELETE ON rutas.rutas FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_items_ruta AFTER INSERT OR UPDATE OR DELETE ON rutas.items_ruta FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();
CREATE TRIGGER trg_audit_abonos AFTER INSERT OR UPDATE OR DELETE ON rutas.abonos FOR EACH ROW EXECUTE FUNCTION auditoria.fn_trigger_auditoria();

CREATE OR REPLACE FUNCTION usuarios.fn_base64url_encode(p_data bytea)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT translate(trim(trailing '=' FROM encode(p_data, 'base64')), '+/', '-_');
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_base64url_decode(p_text text)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT decode(rpad(translate(p_text, '-_', '+/'), ((length(p_text) + 3) / 4) * 4, '='), 'base64');
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_bytea_xor(p_left bytea, p_right bytea)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  resultado bytea := p_left;
  indice integer;
BEGIN
  IF length(p_left) <> length(p_right) THEN
    RAISE EXCEPTION 'bytea length mismatch';
  END IF;

  FOR indice IN 0..length(p_left) - 1 LOOP
    resultado := set_byte(resultado, indice, get_byte(p_left, indice) # get_byte(p_right, indice));
  END LOOP;

  RETURN resultado;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_pbkdf2_sha256(p_password text, p_salt bytea, p_iterations integer)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  llave bytea := convert_to(p_password, 'UTF8');
  u bytea;
  resultado bytea;
  indice integer;
BEGIN
  IF p_iterations < 1 THEN
    RAISE EXCEPTION 'invalid iteration count';
  END IF;

  u := hmac(p_salt || decode('00000001', 'hex'), llave, 'sha256');
  resultado := u;

  FOR indice IN 2..p_iterations LOOP
    u := hmac(u, llave, 'sha256');
    resultado := usuarios.fn_bytea_xor(resultado, u);
  END LOOP;

  RETURN resultado;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_hash_password(p_plain_password text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  salt bytea := gen_random_bytes(16);
  iterations integer := 210000;
  derived bytea;
BEGIN
  derived := usuarios.fn_pbkdf2_sha256(p_plain_password, salt, iterations);
  RETURN format(
    'pbkdf2_sha256$%s$%s$%s',
    iterations,
    usuarios.fn_base64url_encode(salt),
    usuarios.fn_base64url_encode(derived)
  );
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_verify_password(p_plain_password text, p_stored_hash text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  parts text[];
  iterations integer;
  salt bytea;
  expected bytea;
  derived bytea;
BEGIN
  IF p_stored_hash LIKE 'pbkdf2_sha256$%' THEN
    parts := string_to_array(p_stored_hash, '$');
    IF array_length(parts, 1) <> 4 THEN
      RETURN false;
    END IF;

    iterations := parts[2]::integer;
    salt := usuarios.fn_base64url_decode(parts[3]);
    expected := usuarios.fn_base64url_decode(parts[4]);
    derived := usuarios.fn_pbkdf2_sha256(p_plain_password, salt, iterations);
    RETURN derived = expected;
  END IF;

  RETURN encode(sha256(convert_to(p_plain_password || 'AguaMilenaSecureS4lt_2026!', 'UTF8')), 'hex') = p_stored_hash;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_usuario_sesion(p_session_token text)
RETURNS TABLE (
  id uuid,
  email text,
  nombre text,
  rol text,
  vendedor_id uuid,
  debe_cambiar_contrasena boolean,
  telefono text,
  url_avatar text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = usuarios, public, extensions
AS $$
DECLARE
  v_token_hash text;
BEGIN
  IF p_session_token IS NULL OR btrim(p_session_token) = '' THEN
    RAISE EXCEPTION 'missing session token' USING ERRCODE = '28000';
  END IF;

  v_token_hash := encode(digest(convert_to(p_session_token, 'UTF8'), 'sha256'), 'hex');

  UPDATE usuarios.sesiones_app s
  SET ultimo_acceso = now()
  WHERE s.token_hash = v_token_hash
    AND s.revocada_en IS NULL
    AND s.expira_en > now();

  RETURN QUERY
  SELECT
    u.id,
    pgp_sym_decrypt(u.email_enc, 'agua_milena_db_key_2026') AS email,
    u.nombre,
    u.rol,
    u.vendedor_id,
    u.debe_cambiar_contrasena,
    CASE
      WHEN u.telefono_enc IS NOT NULL THEN pgp_sym_decrypt(u.telefono_enc, 'agua_milena_db_key_2026')
      ELSE NULL
    END AS telefono,
    u.url_avatar
  FROM usuarios.sesiones_app s
  JOIN usuarios.usuarios u ON u.id = s.usuario_id
  WHERE s.token_hash = v_token_hash
    AND s.revocada_en IS NULL
    AND s.expira_en > now()
    AND u.activo = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid session' USING ERRCODE = '28000';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_session_token_header()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = usuarios, public, extensions
AS $$
DECLARE
  headers jsonb;
BEGIN
  headers := NULLIF(current_setting('request.headers', true), '')::jsonb;
  RETURN NULLIF(headers->>'x-agua-milena-session', '');
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_contexto_sesion(p_session_token text)
RETURNS TABLE (
  id uuid,
  rol text,
  vendedor_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = usuarios, public, extensions
AS $$
DECLARE
  v_token_hash text;
BEGIN
  IF p_session_token IS NULL OR btrim(p_session_token) = '' THEN
    RAISE EXCEPTION 'missing session token' USING ERRCODE = '28000';
  END IF;

  v_token_hash := encode(digest(convert_to(p_session_token, 'UTF8'), 'sha256'), 'hex');

  RETURN QUERY
  SELECT u.id, u.rol, u.vendedor_id
  FROM usuarios.sesiones_app s
  JOIN usuarios.usuarios u ON u.id = s.usuario_id
  WHERE s.token_hash = v_token_hash
    AND s.revocada_en IS NULL
    AND s.expira_en > now()
    AND u.activo = true
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invalid session' USING ERRCODE = '28000';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_rol_sesion_header()
RETURNS text
LANGUAGE plpgsql
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
  RETURN ctx.rol;
EXCEPTION
  WHEN others THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_sesion_header_valida()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = usuarios, public, extensions
AS $$
  SELECT usuarios.fn_rol_sesion_header() IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_sesion_header_tiene_rol(p_roles text[])
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = usuarios, public, extensions
AS $$
  SELECT COALESCE(usuarios.fn_rol_sesion_header() = ANY(p_roles), false);
$$;

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

CREATE OR REPLACE FUNCTION usuarios.fn_login(p_email text, p_password text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  usuario record;
  session_token text;
  session_hash text;
  target_hash text;
BEGIN
  target_hash := encode(digest(lower(trim(p_email)), 'sha256'), 'hex');

  SELECT id, email_enc, nombre, rol, vendedor_id, debe_cambiar_contrasena,
         hash_contrasena, telefono_enc, url_avatar
  INTO usuario
  FROM usuarios.usuarios
  WHERE email_hash = target_hash
    AND activo = true
  LIMIT 1;

  IF NOT FOUND OR NOT usuarios.fn_verify_password(p_password, usuario.hash_contrasena) THEN
    RAISE EXCEPTION 'invalid credentials' USING ERRCODE = '28000';
  END IF;

  IF usuario.hash_contrasena NOT LIKE 'pbkdf2_sha256$%' THEN
    UPDATE usuarios.usuarios
    SET hash_contrasena = usuarios.fn_hash_password(p_password)
    WHERE id = usuario.id;
  END IF;

  session_token := encode(gen_random_bytes(32), 'hex');
  session_hash := encode(digest(convert_to(session_token, 'UTF8'), 'sha256'), 'hex');
-- Datos INSERT omitidos para portafolio.


  RETURN jsonb_build_object(
    'session_token', session_token,
    'user', jsonb_build_object(
      'id', usuario.id,
      'email', pgp_sym_decrypt(usuario.email_enc, 'agua_milena_db_key_2026'),
      'name', usuario.nombre,
      'role', usuario.rol,
      'seller_id', usuario.vendedor_id,
      'must_change_password', usuario.debe_cambiar_contrasena,
      'phone', CASE
        WHEN usuario.telefono_enc IS NOT NULL THEN pgp_sym_decrypt(usuario.telefono_enc, 'agua_milena_db_key_2026')
        ELSE NULL
      END,
      'avatar_url', usuario.url_avatar
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_validate_session(p_session_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  ctx record;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  RETURN jsonb_build_object(
    'id', ctx.id,
    'email', ctx.email,
    'name', ctx.nombre,
    'role', ctx.rol,
    'seller_id', ctx.vendedor_id,
    'must_change_password', ctx.debe_cambiar_contrasena,
    'phone', ctx.telefono,
    'avatar_url', ctx.url_avatar
  );
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_logout(p_session_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token_hash text;
BEGIN
  IF p_session_token IS NULL OR btrim(p_session_token) = '' THEN
    RETURN;
  END IF;

  v_token_hash := encode(digest(convert_to(p_session_token, 'UTF8'), 'sha256'), 'hex');

  UPDATE usuarios.sesiones_app
  SET revocada_en = now()
  WHERE sesiones_app.token_hash = v_token_hash
    AND revocada_en IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_list_users(p_session_token text)
RETURNS TABLE (
  id uuid,
  email text,
  name text,
  role text,
  active boolean,
  seller_id uuid,
  created_at timestamptz,
  phone text,
  avatar_url text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  ctx record;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  IF ctx.rol <> 'admin' THEN
    RAISE EXCEPTION 'admin privileges required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    u.id,
    pgp_sym_decrypt(u.email_enc, 'agua_milena_db_key_2026') AS email,
    u.nombre AS name,
    u.rol AS role,
    u.activo AS active,
    u.vendedor_id AS seller_id,
    u.creado_en AS created_at,
    CASE
      WHEN u.telefono_enc IS NOT NULL THEN pgp_sym_decrypt(u.telefono_enc, 'agua_milena_db_key_2026')
      ELSE NULL
    END AS phone,
    u.url_avatar AS avatar_url
  FROM usuarios.usuarios u
  ORDER BY u.nombre ASC;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_upsert_user(
  p_session_token text,
  p_target_user_id uuid DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_name text DEFAULT NULL,
  p_password_hash text DEFAULT NULL,
  p_role text DEFAULT NULL,
  p_active boolean DEFAULT NULL,
  p_seller_id uuid DEFAULT NULL,
  p_must_change_password boolean DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  ctx record;
  usuario record;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  IF p_target_user_id IS NOT NULL AND ctx.id = p_target_user_id THEN
    NULL;
  ELSIF ctx.rol <> 'admin' THEN
    RAISE EXCEPTION 'admin privileges required' USING ERRCODE = '42501';
  END IF;

  IF p_target_user_id IS NULL THEN
    IF p_email IS NULL OR p_name IS NULL OR p_role IS NULL OR p_password_hash IS NULL THEN
      RAISE EXCEPTION 'missing required fields for create';
    END IF;
-- Datos INSERT omitidos para portafolio.


    RETURN jsonb_build_object(
      'id', usuario.id,
      'email', lower(trim(p_email)),
      'name', usuario.nombre,
      'role', usuario.rol,
      'active', usuario.activo,
      'seller_id', usuario.vendedor_id,
      'must_change_password', usuario.debe_cambiar_contrasena,
      'phone', p_phone,
      'avatar_url', usuario.url_avatar
    );
  END IF;

  UPDATE usuarios.usuarios
  SET
    email_hash = CASE WHEN p_email IS NOT NULL THEN encode(digest(lower(trim(p_email)), 'sha256'), 'hex') ELSE email_hash END,
    email_enc = CASE WHEN p_email IS NOT NULL THEN pgp_sym_encrypt(lower(trim(p_email)), 'agua_milena_db_key_2026') ELSE email_enc END,
    nombre = COALESCE(trim(p_name), nombre),
    hash_contrasena = COALESCE(p_password_hash, hash_contrasena),
    rol = CASE WHEN ctx.rol = 'admin' THEN COALESCE(p_role, rol) ELSE rol END,
    activo = CASE WHEN ctx.rol = 'admin' THEN COALESCE(p_active, activo) ELSE activo END,
    vendedor_id = CASE
      WHEN ctx.rol = 'admin' AND COALESCE(p_role, rol) <> 'vendedor' THEN NULL
      WHEN ctx.rol = 'admin' THEN COALESCE(p_seller_id, vendedor_id)
      ELSE vendedor_id
    END,
    debe_cambiar_contrasena = COALESCE(p_must_change_password, debe_cambiar_contrasena),
    telefono_enc = CASE
      WHEN p_phone = '' THEN NULL
      WHEN p_phone IS NOT NULL THEN pgp_sym_encrypt(p_phone, 'agua_milena_db_key_2026')
      ELSE telefono_enc
    END,
    url_avatar = COALESCE(p_avatar_url, url_avatar)
  WHERE id = p_target_user_id
  RETURNING id, nombre, rol, activo, vendedor_id, debe_cambiar_contrasena, email_enc, telefono_enc, url_avatar
  INTO usuario;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found';
  END IF;

  RETURN jsonb_build_object(
    'id', usuario.id,
    'email', pgp_sym_decrypt(usuario.email_enc, 'agua_milena_db_key_2026'),
    'name', usuario.nombre,
    'role', usuario.rol,
    'active', usuario.activo,
    'seller_id', usuario.vendedor_id,
    'must_change_password', usuario.debe_cambiar_contrasena,
    'phone', CASE
      WHEN usuario.telefono_enc IS NOT NULL THEN pgp_sym_decrypt(usuario.telefono_enc, 'agua_milena_db_key_2026')
      ELSE NULL
    END,
    'avatar_url', usuario.url_avatar
  );
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_delete_user(p_session_token text, p_target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  ctx record;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  IF ctx.rol <> 'admin' THEN
    RAISE EXCEPTION 'admin privileges required' USING ERRCODE = '42501';
  END IF;

  IF ctx.id = p_target_user_id THEN
    RAISE EXCEPTION 'cannot delete your own account';
  END IF;

  DELETE FROM usuarios.usuarios WHERE id = p_target_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_change_my_password_hash(p_session_token text, p_password_hash text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  ctx record;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  UPDATE usuarios.usuarios
  SET hash_contrasena = p_password_hash,
      debe_cambiar_contrasena = false
  WHERE id = ctx.id;
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_registrar_token_dispositivo(
  p_session_token text,
  p_token_firebase text,
  p_plataforma text DEFAULT 'android',
  p_nombre_dispositivo text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = usuarios, extensions, public, pg_temp
AS $$
DECLARE
  ctx record;
  token_guardado record;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  IF p_token_firebase IS NULL OR btrim(p_token_firebase) = '' THEN
    RAISE EXCEPTION 'missing firebase token' USING ERRCODE = '22023';
  END IF;
-- Datos INSERT omitidos para portafolio.


  RETURN jsonb_build_object(
    'id', token_guardado.id,
    'usuario_id', token_guardado.usuario_id,
    'activo', token_guardado.activo,
    'actualizado_en', token_guardado.actualizado_en
  );
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_desactivar_token_dispositivo(
  p_session_token text,
  p_token_firebase text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = usuarios, extensions, public, pg_temp
AS $$
DECLARE
  ctx record;
BEGIN
  SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);

  UPDATE usuarios.tokens_dispositivo t
  SET activo = false,
      actualizado_en = now()
  WHERE t.usuario_id = ctx.id
    AND t.token_firebase = btrim(p_token_firebase);
END;
$$;

CREATE OR REPLACE FUNCTION usuarios.fn_tokens_notificacion(
  p_rol text DEFAULT NULL,
  p_usuario_id uuid DEFAULT NULL
)
RETURNS TABLE (
  token_firebase text,
  usuario_id uuid,
  rol text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = usuarios, extensions, public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT t.token_firebase, t.usuario_id, u.rol
  FROM usuarios.tokens_dispositivo t
  JOIN usuarios.usuarios u ON u.id = t.usuario_id
  WHERE t.activo = true
    AND u.activo = true
    AND (p_rol IS NULL OR u.rol = p_rol)
    AND (p_usuario_id IS NULL OR t.usuario_id = p_usuario_id);
END;
$$;

CREATE OR REPLACE FUNCTION auditoria.fn_log_error_secure(
  p_session_token text DEFAULT NULL,
  p_nivel text DEFAULT 'error',
  p_mensaje text DEFAULT NULL,
  p_stack_trace text DEFAULT NULL,
  p_pantalla text DEFAULT NULL,
  p_endpoint text DEFAULT NULL,
  p_dispositivo text DEFAULT NULL,
  p_os_version text DEFAULT NULL,
  p_app_version text DEFAULT NULL,
  p_metadata jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  ctx record;
  user_id text;
BEGIN
  IF p_session_token IS NOT NULL AND btrim(p_session_token) <> '' THEN
    BEGIN
      SELECT * INTO ctx FROM usuarios.fn_usuario_sesion(p_session_token);
      user_id := ctx.id::text;
    EXCEPTION WHEN OTHERS THEN
      user_id := NULL;
    END;
  END IF;
-- Datos INSERT omitidos para portafolio.

END;
$$;

-- ============================================================================
-- DATOS INICIALES
-- ============================================================================
-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.


-- ============================================================================
-- PERMISOS, RLS Y STORAGE
-- ============================================================================

DO $$
DECLARE
  esquema text;
BEGIN
  FOREACH esquema IN ARRAY ARRAY['inventario', 'ventas', 'vendedores', 'rutas', 'auditoria', 'usuarios']
  LOOP
    EXECUTE format('GRANT USAGE ON SCHEMA %I TO anon, authenticated, service_role', esquema);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA %I TO service_role', esquema);
    EXECUTE format('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA %I TO service_role', esquema);
  END LOOP;
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA usuarios FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA usuarios FROM anon, authenticated;
GRANT USAGE ON SCHEMA usuarios TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON inventario.productos TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON inventario.precios_producto TO anon, authenticated;
GRANT SELECT, INSERT ON inventario.movimientos_inventario TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON inventario.alertas TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON inventario.predicciones_modelo_alertas TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON inventario.configuracion_app TO anon, authenticated;
GRANT SELECT ON inventario.versiones_aplicacion TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON vendedores.vendedores TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON ventas.ventas TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ventas.items_venta TO anon, authenticated;
GRANT SELECT ON ventas.v_ventas TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON rutas.rutas TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON rutas.items_ruta TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON rutas.abonos TO anon, authenticated;
GRANT SELECT ON rutas.v_rutas TO anon, authenticated;

GRANT SELECT, UPDATE ON auditoria.log_auditoria TO anon, authenticated;

ALTER TABLE usuarios.usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios.sesiones_app ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios.tokens_dispositivo ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditoria.log_error ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  fila record;
BEGIN
  FOR fila IN
    SELECT * FROM (
      VALUES
        ('inventario', 'productos'),
        ('inventario', 'precios_producto'),
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
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', fila.esquema, fila.tabla);
    EXECUTE format('DROP POLICY IF EXISTS app_select ON %I.%I', fila.esquema, fila.tabla);
    EXECUTE format('DROP POLICY IF EXISTS app_insert ON %I.%I', fila.esquema, fila.tabla);
    EXECUTE format('DROP POLICY IF EXISTS app_update ON %I.%I', fila.esquema, fila.tabla);
    EXECUTE format('DROP POLICY IF EXISTS app_delete ON %I.%I', fila.esquema, fila.tabla);
    EXECUTE format('CREATE POLICY app_select ON %I.%I FOR SELECT TO anon, authenticated USING (usuarios.fn_sesion_header_tiene_rol(ARRAY[''admin'', ''planta'']))', fila.esquema, fila.tabla);
    EXECUTE format('CREATE POLICY app_insert ON %I.%I FOR INSERT TO anon, authenticated WITH CHECK (usuarios.fn_sesion_header_tiene_rol(ARRAY[''admin'', ''planta'']))', fila.esquema, fila.tabla);
    EXECUTE format('CREATE POLICY app_update ON %I.%I FOR UPDATE TO anon, authenticated USING (usuarios.fn_sesion_header_tiene_rol(ARRAY[''admin'', ''planta''])) WITH CHECK (usuarios.fn_sesion_header_tiene_rol(ARRAY[''admin'', ''planta'']))', fila.esquema, fila.tabla);
    EXECUTE format('CREATE POLICY app_delete ON %I.%I FOR DELETE TO anon, authenticated USING (usuarios.fn_sesion_header_tiene_rol(ARRAY[''admin'']))', fila.esquema, fila.tabla);
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

GRANT EXECUTE ON FUNCTION usuarios.fn_login(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_session_token_header() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_contexto_sesion(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_rol_sesion_header() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_sesion_header_valida() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_sesion_header_tiene_rol(text[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_vendedor_sesion_header() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_usuario_sesion(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_validate_session(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_logout(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_list_users(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_upsert_user(text, uuid, text, text, text, text, boolean, uuid, boolean, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_delete_user(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_change_my_password_hash(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_registrar_token_dispositivo(text, text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_desactivar_token_dispositivo(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION usuarios.fn_tokens_notificacion(text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION inventario.fn_registrar_movimiento_seguro(text, uuid, text, integer, text) TO anon, authenticated;
REVOKE ALL ON FUNCTION ventas.fn_crear_venta_segura(text, jsonb, text, uuid, date, integer, integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ventas.fn_crear_venta_segura(text, jsonb, text, uuid, date, integer, integer, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auditoria.fn_log_error_secure(text, text, text, text, text, text, text, text, text, jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION ventas.fn_resumen_ventas(date, date, uuid, boolean) TO anon, authenticated;

ALTER TABLE inventario.versiones_aplicacion ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "versiones_aplicacion_lectura_publica"
ON inventario.versiones_aplicacion;

CREATE POLICY "versiones_aplicacion_lectura_publica"
ON inventario.versiones_aplicacion
FOR SELECT
USING (true);
-- Datos INSERT omitidos para portafolio.


DROP POLICY IF EXISTS lectura_publica_avatars ON storage.objects;
CREATE POLICY lectura_publica_avatars
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS subida_publica_avatars ON storage.objects;
CREATE POLICY subida_publica_avatars
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'avatars'
  AND usuarios.fn_sesion_header_valida()
  AND position('..' in name) = 0
  AND lower(name) ~ '\.(jpg|jpeg|png|webp)$'
);

DROP POLICY IF EXISTS actualizacion_publica_avatars ON storage.objects;
CREATE POLICY actualizacion_publica_avatars
ON storage.objects FOR UPDATE
USING (bucket_id = 'avatars' AND usuarios.fn_sesion_header_valida())
WITH CHECK (
  bucket_id = 'avatars'
  AND usuarios.fn_sesion_header_valida()
  AND position('..' in name) = 0
  AND lower(name) ~ '\.(jpg|jpeg|png|webp)$'
);

DROP POLICY IF EXISTS eliminacion_publica_avatars ON storage.objects;
CREATE POLICY eliminacion_publica_avatars
ON storage.objects FOR DELETE
USING (bucket_id = 'avatars' AND usuarios.fn_sesion_header_valida());

DROP POLICY IF EXISTS lectura_publica_productos ON storage.objects;
CREATE POLICY lectura_publica_productos
ON storage.objects FOR SELECT
USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS subida_publica_productos ON storage.objects;
CREATE POLICY subida_publica_productos
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'product-images'
  AND usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
  AND position('..' in name) = 0
  AND lower(name) ~ '\.(jpg|jpeg|png|webp)$'
);

DROP POLICY IF EXISTS actualizacion_publica_productos ON storage.objects;
CREATE POLICY actualizacion_publica_productos
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'product-images'
  AND usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
)
WITH CHECK (
  bucket_id = 'product-images'
  AND usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
  AND position('..' in name) = 0
  AND lower(name) ~ '\.(jpg|jpeg|png|webp)$'
);

DROP POLICY IF EXISTS eliminacion_publica_productos ON storage.objects;
CREATE POLICY eliminacion_publica_productos
ON storage.objects FOR DELETE
USING (
  bucket_id = 'product-images'
  AND usuarios.fn_sesion_header_tiene_rol(ARRAY['admin', 'planta'])
);

COMMIT;

DO $$
BEGIN
  EXECUTE 'ALTER ROLE authenticator SET pgrst.db_schemas TO ''public, storage, graphql_public, inventario, ventas, vendedores, rutas, auditoria, usuarios''';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'Configura los esquemas expuestos desde Supabase Dashboard > API si este proyecto no permite ALTER ROLE.';
END $$;

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';

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
