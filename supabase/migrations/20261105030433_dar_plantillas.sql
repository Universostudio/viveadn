-- Plantillas de la pagina de dar. Cada iglesia elige un estilo, su apariencia y sus propios fondos
-- (no solo diezmo, ofrenda y donacion), cada uno con el enlace de su sitio de recaudo. La app no
-- procesa pagos: la pagina ayuda a calcular el aporte y lleva a la persona al sitio de la iglesia.

-- 1. Fondos propios: clave libre (minusculas, numeros y guion bajo), nombre, descripcion y orden.
--    Los tres tipos originales siguen valiendo y se traducen en la web si no tienen nombre.
alter table public.enlaces_dar drop constraint if exists enlaces_dar_tipo_check;
alter table public.enlaces_dar add constraint enlaces_dar_tipo_check check (tipo ~ '^[a-z0-9_]{1,40}$');
alter table public.enlaces_dar add column nombre text check (nombre is null or length(btrim(nombre)) between 1 and 80);
alter table public.enlaces_dar add column descripcion text check (descripcion is null or length(descripcion) <= 200);
alter table public.enlaces_dar add column orden integer not null default 0 check (orden between 0 and 1000);

-- Un maximo de 20 fondos por iglesia: la pagina publica los devuelve todos.
-- Un upsert que acaba siendo una actualizacion tambien pasa por este disparador (BEFORE INSERT se ejecuta
-- antes de resolver el conflicto), asi que solo se cuenta cuando el fondo todavia no existe.
create or replace function private.limitar_fondos_dar()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
begin
  if not exists (select 1 from public.enlaces_dar where iglesia_id = new.iglesia_id and tipo = new.tipo)
     and (select count(*) from public.enlaces_dar where iglesia_id = new.iglesia_id) >= 20 then
    raise exception 'Se admiten como maximo 20 fondos por iglesia' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke execute on function private.limitar_fondos_dar() from public, anon, authenticated, service_role;
create trigger enlaces_dar_limite before insert on public.enlaces_dar
  for each row execute function private.limitar_fondos_dar();

-- 2. Apariencia de la pagina publica de cada iglesia
create table public.dar_config (
  iglesia_id uuid primary key default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  plantilla text not null default 'clasica' check (plantilla in ('clasica', 'dia')),
  titulo text check (titulo is null or length(titulo) <= 100),
  subtitulo text check (subtitulo is null or length(subtitulo) <= 200),
  color_primario text not null default '#00523c' check (color_primario ~ '^#[0-9a-fA-F]{6}$'),
  color_acento text not null default '#f5a623' check (color_acento ~ '^#[0-9a-fA-F]{6}$'),
  logo_url text check (logo_url is null or (length(logo_url) <= 500 and logo_url ~ '^https://[^[:space:]]+$')),
  calculadora text not null default 'dia' check (calculadora in ('dia', 'diezmo', 'ninguna')),
  moneda text not null default 'EUR' check (moneda ~ '^[A-Z]{3}$'),
  updated_at timestamptz not null default now()
);

alter table public.dar_config enable row level security;

create policy dar_config_ver on public.dar_config for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()));
create policy dar_config_crear on public.dar_config for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
create policy dar_config_editar on public.dar_config for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy dar_config_borrar on public.dar_config for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));

grant select, insert, update, delete on public.dar_config to authenticated;
grant all on public.dar_config to service_role;
