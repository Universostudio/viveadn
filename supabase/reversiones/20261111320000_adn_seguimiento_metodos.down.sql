-- Reversión de 20261111320000_adn_seguimiento_metodos.sql (fase 1 del método de seguimiento configurable). No es una migración: se ejecuta a mano,
-- solo si Gerencia lo ordena, y tests/adn_reversion.sh y tests/adn_seguimiento_metodos.sh demuestran que deja el esquema idéntico al anterior.
-- Devuelve el disparador de consolidaciones a su versión anterior (72 horas y colores a 24, 48 y 72 escritos en la función), quita la columna
-- metodo_id y borra los métodos y la configuración. No toca ningún dato de consolidaciones: todos los procesos siguen con sus fechas y su color.
\set ON_ERROR_STOP on
begin;
create or replace function public.gestionar_consolidacion()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
DECLARE
  horas_transcurridas DECIMAL;
BEGIN
  -- Calcular fecha limite automaticamente al insertar
  IF TG_OP = 'INSERT' THEN
    NEW.fecha_limite := NEW.fecha_conversion + INTERVAL '72 hours';
  END IF;

  -- La fecha de cierre se fija al completar y se limpia si se reabre
  IF NEW.completado IS TRUE THEN
    IF NEW.completado_at IS NULL THEN NEW.completado_at := NOW(); END IF;
  ELSE
    NEW.completado_at := NULL;
  END IF;

  -- Actualizar estado de alerta si no esta completado
  IF NEW.completado = false THEN
    horas_transcurridas := EXTRACT(EPOCH FROM (NOW() - NEW.fecha_conversion)) / 3600;
    IF horas_transcurridas <= 24 THEN
      NEW.estado_alerta := 'verde';
    ELSIF horas_transcurridas <= 48 THEN
      NEW.estado_alerta := 'amarillo';
    ELSIF horas_transcurridas <= 72 THEN
      NEW.estado_alerta := 'naranja';
    ELSE
      NEW.estado_alerta := 'rojo';
    END IF;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$function$;

drop view public.adn_seguimiento_estado;
drop trigger consolidaciones_metodo on public.consolidaciones;
alter table public.consolidaciones drop column metodo_id;
drop function public.adn_seguimiento_alerta(timestamptz, boolean, uuid, timestamptz);
drop function private.adn_alerta_con_umbrales(timestamptz, boolean, integer, integer, integer, timestamptz);
drop function private.adn_metodo_activo(uuid);
drop table public.adn_seguimiento_config;
drop table public.adn_seguimiento_metodos;
drop function private.adn_comprobar_metodo();
drop function private.adn_comprobar_plantilla();
commit;
