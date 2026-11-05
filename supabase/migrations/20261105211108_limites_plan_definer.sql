-- Correccion de los limites del plan, dos hallazgos reales de la revision:
--  1. Los disparadores corrian con los permisos de quien da de alta, asi que contaban solo las filas que su seguridad
--     por filas le deja ver. Un colaborador ve cero miembros ajenos: el tope no le afectaba. Ahora son SECURITY DEFINER
--     (en private, con search_path fijo) y cuentan todas las filas de la iglesia.
--  2. Reactivar o dar de alta un perfil ignoraba las plazas reservadas por invitaciones pendientes, y podia dejar sin
--     sitio a quien aceptaba una invitacion vigente. Ahora los usuarios cuentan perfiles activos mas invitaciones vigentes.
--     Quien acepta una invitacion no se cuenta dos veces: reclamar_invitacion la marca como usada antes de crear el perfil.

create or replace function private.limitar_plan_miembros()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_max integer; v_n integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_miembros into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.miembros where iglesia_id = new.iglesia_id and activo;
  if v_n >= v_max then
    raise exception 'PLAN_LIMITE: miembros' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

create or replace function private.limitar_plan_usuarios()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_max integer; v_n integer; v_i integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  select count(*) into v_i from public.invitaciones
   where iglesia_id = new.iglesia_id and usada_en is null and revocada_en is null and caduca_en > now();
  if v_n + v_i >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

create or replace function private.limitar_plan_invitaciones()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_max integer; v_n integer; v_i integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  select count(*) into v_i from public.invitaciones
   where iglesia_id = new.iglesia_id and usada_en is null and revocada_en is null and caduca_en > now();
  if v_n + v_i >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

revoke execute on function private.limitar_plan_miembros() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_usuarios() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_invitaciones() from public, anon, authenticated, service_role;
