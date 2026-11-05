-- Ciclo de vida de la iglesia: onboarding, prueba, activa, receso y suspendida.
-- `activa` sigue siendo la unica puerta que leen las politicas y las funciones de borde;
-- `etapa` la gobierna y la mantiene sincronizada un disparador, de modo que nada existente cambia.
--   onboarding, prueba, activa  -> activa = true
--   receso, suspendida          -> activa = false (los datos se conservan intactos)
-- Una prueba vencida corta los modulos de pago (tiene_modulo), sin tocar `activa`.

alter table public.iglesias
  add column etapa text not null default 'activa'
    constraint iglesias_etapa_check check (etapa in ('onboarding', 'prueba', 'activa', 'receso', 'suspendida')),
  add column etapa_desde timestamptz not null default now(),
  add column prueba_hasta timestamptz;

update public.iglesias set etapa = case when activa then 'activa' else 'suspendida' end;

create or replace function private.sincronizar_etapa()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if tg_op = 'INSERT' then
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
  elsif new.etapa is distinct from old.etapa then
    -- La etapa manda
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
    new.etapa_desde := now();
  elsif new.activa is distinct from old.activa then
    -- Compatibilidad con quien aun cambia solo `activa`
    new.etapa := case when new.activa then 'activa' else 'suspendida' end;
    new.etapa_desde := now();
  end if;
  if new.etapa = 'prueba' and new.prueba_hasta is null then
    new.prueba_hasta := now() + interval '30 days';
  elsif new.etapa <> 'prueba' then
    new.prueba_hasta := null;
  end if;
  return new;
end $$;
revoke all on function private.sincronizar_etapa() from public, anon, authenticated, service_role;

create trigger iglesias_sincronizar_etapa
  before insert or update on public.iglesias
  for each row execute function private.sincronizar_etapa();

-- Una prueba vencida deja de dar modulos
create or replace function private.tiene_modulo(p_modulo text)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (
    select 1 from public.iglesias i
    where i.id = (select private.get_iglesia_id()) and i.activa
      and (i.etapa <> 'prueba' or i.prueba_hasta is null or i.prueba_hasta > now())
      and (
        exists (select 1 from public.plan_modulos pm where pm.plan = i.plan and pm.modulo = p_modulo)
        or exists (
          select 1 from public.iglesia_modulos im
          where im.iglesia_id = i.id and im.modulo = p_modulo and im.activo
            and im.desde <= now() and (im.hasta is null or im.hasta > now())
        )
      )
  )
$$;
