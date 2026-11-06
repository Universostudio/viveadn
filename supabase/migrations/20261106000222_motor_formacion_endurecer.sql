-- Endurece el motor de formacion tras la revision:
--  1. Dos avances simultaneos que completan un programa dejaban la inscripcion en curso: cada transaccion veia solo el suyo.
--     El recalculo bloquea ahora la fila de la inscripcion, de modo que el segundo espera al primero y ve su avance.
--  2. Una inscripcion completada podia traspasarse a otro miembro cambiando miembro_id, con su avance y su fecha.
--     Quien inscribe, programa y miembro no se pueden cambiar: se borra la inscripcion y se crea otra.
--  3. Mover una leccion a otro programa no recalculaba ninguno de los dos. La leccion ya no cambia de programa.

create or replace function private.recalcular_inscripcion(p_inscripcion uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v record; n_total integer; n_hechas integer;
begin
  -- El cerrojo serializa los recalculos de una misma inscripcion; despues de esperarlo, los conteos ven lo ya confirmado
  select i.iglesia_id, i.programa_id, i.estado into v from public.inscripciones_formacion i where i.id = p_inscripcion for update;
  if not found then return; end if;
  select count(*) into n_total from public.programa_lecciones l where l.iglesia_id = v.iglesia_id and l.programa_id = v.programa_id;
  select count(*) into n_hechas from public.avance_formacion a where a.inscripcion_id = p_inscripcion;
  if n_total > 0 and n_hechas >= n_total then
    update public.inscripciones_formacion set estado = 'completado', completado_en = coalesce(completado_en, now())
      where id = p_inscripcion and estado <> 'completado';
  elsif v.estado = 'completado' then
    update public.inscripciones_formacion set estado = 'en_curso', completado_en = null where id = p_inscripcion;
  end if;
end $$;
revoke all on function private.recalcular_inscripcion(uuid) from public, anon, authenticated, service_role;

create or replace function private.guardar_inscripcion()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null or pg_trigger_depth() > 1 then return new; end if;
  if tg_op = 'INSERT' then
    new.estado := 'en_curso';
    new.completado_en := null;
  else
    if new.iglesia_id is distinct from old.iglesia_id or new.programa_id is distinct from old.programa_id or new.miembro_id is distinct from old.miembro_id then
      raise exception 'Una inscripcion no cambia de programa ni de miembro: se borra y se crea otra';
    end if;
    if new.completado_en is distinct from old.completado_en or (new.estado = 'completado') is distinct from (old.estado = 'completado') then
      raise exception 'La finalizacion de un programa se calcula con sus lecciones';
    end if;
  end if;
  return new;
end $$;
revoke all on function private.guardar_inscripcion() from public, anon, authenticated, service_role;

create or replace function private.guardar_leccion()
returns trigger language plpgsql set search_path to '' as $$
begin
  if new.iglesia_id is distinct from old.iglesia_id or new.programa_id is distinct from old.programa_id then
    raise exception 'Una leccion no cambia de programa: se borra y se crea en el otro';
  end if;
  return new;
end $$;
revoke all on function private.guardar_leccion() from public, anon, authenticated, service_role;
create trigger programa_lecciones_guardar before update on public.programa_lecciones
  for each row execute function private.guardar_leccion();
