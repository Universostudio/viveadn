-- Exportacion y borrado completo de una iglesia (RGPD: portabilidad y supresion).
-- Las dos funciones solo las ejecuta service_role: las llama la funcion de borde `plataforma`,
-- que valida a quien pide la operacion.

-- 1. Borrado programado: solo desde receso o suspendida, y solo lo fija la plataforma.
alter table public.iglesias
  add column borrado_programado_en timestamptz,
  add constraint iglesias_borrado_check check (borrado_programado_en is null or etapa in ('receso', 'suspendida'));

-- Si la iglesia sale de receso o suspension, el borrado programado se cancela solo
create or replace function private.sincronizar_etapa()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if tg_op = 'INSERT' then
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
  elsif new.etapa is distinct from old.etapa then
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
    new.etapa_desde := now();
  elsif new.activa is distinct from old.activa then
    new.etapa := case when new.activa then 'activa' else 'suspendida' end;
    new.etapa_desde := now();
  end if;
  if new.etapa = 'prueba' and new.prueba_hasta is null then
    new.prueba_hasta := now() + interval '30 days';
  elsif new.etapa <> 'prueba' then
    new.prueba_hasta := null;
  end if;
  -- Al cambiar de etapa fuera de receso o suspension se cancela; programarlo estando fuera lo rechaza la restriccion
  if new.etapa not in ('receso', 'suspendida') and (tg_op = 'INSERT' or new.etapa is distinct from old.etapa) then
    new.borrado_programado_en := null;
  end if;
  return new;
end $$;

create or replace function private.guardar_iglesia()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.plan is distinct from old.plan or new.activa is distinct from old.activa
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo
     or new.iglesia_madre_id is distinct from old.iglesia_madre_id or new.red_acceso is distinct from old.red_acceso
     or new.etapa is distinct from old.etapa or new.etapa_desde is distinct from old.etapa_desde
     or new.prueba_hasta is distinct from old.prueba_hasta
     or new.borrado_programado_en is distinct from old.borrado_programado_en then
    raise exception 'El plan, el estado, la etapa, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$$;

-- 2. Exportacion: recorre todas las tablas con iglesia_id, de modo que una tabla nueva
--    entra sola. Se excluyen los secretos (tokens de QR e invitacion, huella de IP).
create or replace function public.exportar_iglesia(p_iglesia uuid)
returns jsonb language plpgsql set search_path to '' as $$
declare
  r record;
  filas jsonb;
  tablas jsonb := '{}'::jsonb;
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
      and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
    order by c.relname
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) - %L::text[]), ''[]''::jsonb) from public.%I t where t.iglesia_id = $1',
                   array['token', 'token_hash', 'ip_hash'], r.relname)
      into filas using p_iglesia;
    tablas := tablas || jsonb_build_object(r.relname, filas);
  end loop;
  -- La unica tabla de iglesia sin iglesia_id propio
  select coalesce(jsonb_agg(to_jsonb(rp)), '[]'::jsonb) into filas
    from public.rol_permisos rp join public.roles ro on ro.id = rp.rol_id where ro.iglesia_id = p_iglesia;
  tablas := tablas || jsonb_build_object('rol_permisos', filas);
  return jsonb_build_object(
    'formato', 'viveadn-exportacion-1',
    'exportado_en', now(),
    'iglesia', (select to_jsonb(i) from public.iglesias i where i.id = p_iglesia),
    'tablas', tablas
  );
end $$;

-- 3. Borrado: solo si el plazo programado ya vencio. Devuelve los usuarios de acceso que la
--    funcion de borde debe borrar de Auth (los administradores de plataforma se respetan).
--    La auditoria conserva la accion y la fecha, pero pierde el detalle y el enlace a la iglesia.
create or replace function public.borrar_iglesia(p_iglesia uuid)
returns uuid[] language plpgsql set search_path to '' as $$
declare
  v record;
  usuarios uuid[];
begin
  select etapa, borrado_programado_en into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.borrado_programado_en is null or v.borrado_programado_en > now() then
    raise exception 'BORRADO_NO_VENCIDO' using errcode = 'check_violation';
  end if;
  select coalesce(array_agg(p.id), '{}') into usuarios
    from public.perfiles p
    where p.iglesia_id = p_iglesia and not exists (select 1 from public.plataforma_admins a where a.user_id = p.id);
  update public.plataforma_auditoria set detalle = '{}'::jsonb where iglesia_id = p_iglesia;
  delete from public.iglesias where id = p_iglesia;
  return usuarios;
end $$;

revoke all on function public.exportar_iglesia(uuid), public.borrar_iglesia(uuid) from public, anon, authenticated;
grant execute on function public.exportar_iglesia(uuid), public.borrar_iglesia(uuid) to service_role;
