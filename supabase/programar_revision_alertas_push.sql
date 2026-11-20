-- Programa revisiones automaticas de alertas operativas desde Supabase.
-- Con esta configuracion se revisa a las 07:00, 10:00, 13:00, 16:00 y
-- 19:00 de Ecuador (12:00, 15:00, 18:00, 21:00 y 00:00 UTC).
-- Antes de ejecutar:
-- 1. Despliega la funcion: supabase functions deploy enviar-notificaciones
-- 2. Configura NOTIFICACIONES_SECRET en la Edge Function.
-- 3. Cambia CAMBIA_ESTE_SECRETO por el mismo valor de NOTIFICACIONES_SECRET.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

SELECT cron.unschedule('agua_milena_alertas_admin_horario_laboral')
WHERE EXISTS (
  SELECT 1
  FROM cron.job
  WHERE jobname = 'agua_milena_alertas_admin_horario_laboral'
);

SELECT cron.unschedule('agua_milena_alertas_admin_cada_hora')
WHERE EXISTS (
  SELECT 1
  FROM cron.job
  WHERE jobname = 'agua_milena_alertas_admin_cada_hora'
);

SELECT cron.unschedule('agua_milena_alertas_planta_horario_laboral')
WHERE EXISTS (
  SELECT 1
  FROM cron.job
  WHERE jobname = 'agua_milena_alertas_planta_horario_laboral'
);

SELECT cron.unschedule('agua_milena_alertas_planta_cada_hora')
WHERE EXISTS (
  SELECT 1
  FROM cron.job
  WHERE jobname = 'agua_milena_alertas_planta_cada_hora'
);

SELECT cron.schedule(
  'agua_milena_alertas_admin_horario_laboral',
  '0 0,12,15,18,21 * * *',
  $$
  SELECT net.http_post(
    url := 'https://PROYECTO.supabase.co/functions/v1/enviar-notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notificaciones-secret', 'CAMBIA_ESTE_SECRETO'
    ),
    body := jsonb_build_object(
      'revision', 'operativa',
      'rol', 'admin'
    ),
    timeout_milliseconds := 30000
  );
  $$
);

SELECT cron.schedule(
  'agua_milena_alertas_planta_horario_laboral',
  '0 0,12,15,18,21 * * *',
  $$
  SELECT net.http_post(
    url := 'https://PROYECTO.supabase.co/functions/v1/enviar-notificaciones',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notificaciones-secret', 'CAMBIA_ESTE_SECRETO'
    ),
    body := jsonb_build_object(
      'revision', 'operativa',
      'rol', 'planta'
    ),
    timeout_milliseconds := 30000
  );
  $$
);
