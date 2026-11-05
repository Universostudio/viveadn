-- La fecha de cierre de una consolidacion la fija la base, no quien la cierra. Antes la pantalla solo guardaba
-- completado = true y dejaba completado_at vacio, con lo que esos casos no contaban como completados dentro de las 72 horas.
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

-- Los casos ya cerrados sin fecha: la mejor aproximacion es su ultima actualizacion
update public.consolidaciones set completado_at = updated_at where completado is true and completado_at is null;
