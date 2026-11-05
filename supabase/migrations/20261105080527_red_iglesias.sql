-- Red de iglesias: una iglesia madre puede tener sedes. Cada sede sigue siendo una iglesia con sus propios
-- datos y usuarios. La madre solo ve un resumen agregado, y solo si la plataforma lo permite para esa sede.
-- Niveles de acceso hoy: 'ninguno' (la madre no ve nada de la sede) y 'resumen' (cifras agregadas).
-- Los niveles se pueden ampliar con otra migracion sin tocar las iglesias ya configuradas.

alter table public.iglesias add column iglesia_madre_id uuid references public.iglesias(id) on delete set null;
alter table public.iglesias add column red_acceso text not null default 'resumen' check (red_acceso in ('ninguno', 'resumen'));
alter table public.iglesias add constraint iglesias_madre_distinta check (iglesia_madre_id is null or iglesia_madre_id <> id);
create index iglesias_madre_idx on public.iglesias (iglesia_madre_id) where iglesia_madre_id is not null;

-- La iglesia puede leer a quien es su madre y su nivel; solo la plataforma (service_role) los cambia.
-- Quien tiene sesion (authenticated) no puede cambiarlos: lo impide el disparador private.guardar_iglesia de abajo.
grant select (iglesia_madre_id, red_acceso) on public.iglesias to authenticated;

-- Un solo nivel: una madre no es sede de otra y una sede no tiene sedes. Se bloquea la fila de la madre
-- para que dos cambios a la vez no puedan formar una cadena.
create or replace function private.limitar_red_iglesias()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
begin
  if new.iglesia_madre_id is null then
    return new;
  end if;
  perform 1 from public.iglesias where id = new.iglesia_madre_id for update;
  if exists (select 1 from public.iglesias where id = new.iglesia_madre_id and iglesia_madre_id is not null) then
    raise exception 'Una iglesia que ya es sede no puede ser iglesia madre' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.iglesias where iglesia_madre_id = new.id) then
    raise exception 'Una iglesia que tiene sedes no puede ser sede de otra' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke execute on function private.limitar_red_iglesias() from public, anon, authenticated, service_role;
create trigger iglesias_red before insert or update of iglesia_madre_id on public.iglesias
  for each row execute function private.limitar_red_iglesias();

-- Defensa en profundidad: quien no es la plataforma no cambia la red ni el acceso
create or replace function private.guardar_iglesia()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.plan is distinct from old.plan or new.activa is distinct from old.activa
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo
     or new.iglesia_madre_id is distinct from old.iglesia_madre_id or new.red_acceso is distinct from old.red_acceso then
    raise exception 'El plan, el estado, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$function$;
revoke execute on function private.guardar_iglesia() from public, anon, authenticated, service_role;
