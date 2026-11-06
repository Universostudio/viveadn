-- El cerrojo del recalculo con FOR UPDATE provocaba un bloqueo mutuo (deadlock) entre dos avances simultaneos:
-- al insertar el avance, la clave foranea toma FOR KEY SHARE sobre la inscripcion, y despues las dos transacciones
-- pedian FOR UPDATE, que choca con el KEY SHARE de la otra. FOR NO KEY UPDATE se serializa con otro recalculo (choca
-- consigo mismo) pero es compatible con el KEY SHARE de la clave foranea, y basta porque nunca se cambia la clave.
create or replace function private.recalcular_inscripcion(p_inscripcion uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v record; n_total integer; n_hechas integer;
begin
  select i.iglesia_id, i.programa_id, i.estado into v from public.inscripciones_formacion i where i.id = p_inscripcion for no key update;
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
