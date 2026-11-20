-- SOLO ejecutar en Supabase local desechable. No es una migración de producción.
-- Requiere esquema completo y parches de la aplicación ya aplicados.
BEGIN;
-- Datos INSERT omitidos para portafolio.

DO $$
DECLARE rol_prueba text; usuario_prueba uuid;
BEGIN
  FOREACH rol_prueba IN ARRAY ARRAY['admin','vendedor'] LOOP
-- Datos INSERT omitidos para portafolio.

-- Datos INSERT omitidos para portafolio.

  END LOOP;
END $$;
COMMIT;
