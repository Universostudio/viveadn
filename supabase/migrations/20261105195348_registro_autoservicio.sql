-- Registro de iglesias por su cuenta (alta autoservicio).
-- En la etapa de pruebas se exige un codigo de acceso a la beta para que no entre cualquiera, y cada
-- dispositivo tiene un limite de intentos. Al lanzar basta con desactivar la exigencia del codigo.
-- Todo es de uso exclusivo del servidor: ninguna de estas tablas ni funciones se abre a anon ni a authenticated.

create table public.plataforma_ajustes (
  clave text primary key check (clave ~ '^[a-z_]{1,60}$'),
  valor jsonb not null,
  updated_at timestamptz not null default now()
);
insert into public.plataforma_ajustes (clave, valor) values
  ('registro_abierto', 'true'::jsonb),
  ('registro_requiere_codigo', 'true'::jsonb);

create table public.registro_codigos (
  id uuid primary key default gen_random_uuid(),
  codigo_hash text not null unique check (codigo_hash ~ '^[0-9a-f]{64}$'),
  etiqueta text not null check (length(btrim(etiqueta)) between 1 and 80),
  usos_max integer not null default 1 check (usos_max between 1 and 1000),
  usos integer not null default 0 check (usos >= 0),
  vence_en timestamptz,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  check (usos <= usos_max)
);

create table public.registro_intentos (
  id bigint generated always as identity primary key,
  ip_hash text not null check (ip_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
create index registro_intentos_ip_idx on public.registro_intentos (ip_hash, created_at desc);

-- Solo el servidor (service_role) toca estas tablas
do $$
declare t text;
begin
  foreach t in array array['plataforma_ajustes', 'registro_codigos', 'registro_intentos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('create policy solo_servicio on public.%I for all to anon, authenticated using (false) with check (false)', t);
  end loop;
end $$;
grant usage, select on sequence public.registro_intentos_id_seq to service_role;

-- Usa un codigo de forma atomica: devuelve su id, o nada si no existe, esta agotado, vencido o desactivado
create or replace function public.consumir_codigo_registro(p_hash text)
 returns uuid
 language sql
 set search_path to ''
as $$
  update public.registro_codigos set usos = usos + 1
   where codigo_hash = p_hash and activo and usos < usos_max and (vence_en is null or vence_en > now())
  returning id;
$$;

-- Devuelve un uso cuando el alta no llego a completarse
create or replace function public.devolver_codigo_registro(p_id uuid)
 returns void
 language sql
 set search_path to ''
as $$
  update public.registro_codigos set usos = greatest(usos - 1, 0) where id = p_id;
$$;

-- Cuenta el intento de un dispositivo y dice si aun esta dentro del limite. El cerrojo evita que dos
-- peticiones simultaneas se cuelen a la vez.
create or replace function public.registrar_intento_registro(p_ip_hash text, p_max integer, p_minutos integer)
 returns boolean
 language plpgsql
 set search_path to ''
as $$
declare n integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('registro:' || p_ip_hash, 0));
  delete from public.registro_intentos where created_at < now() - interval '2 days';
  select count(*) into n from public.registro_intentos
   where ip_hash = p_ip_hash and created_at > now() - make_interval(mins => p_minutos);
  if n >= p_max then
    return false;
  end if;
  insert into public.registro_intentos (ip_hash) values (p_ip_hash);
  return true;
end;
$$;

do $$
declare f text;
begin
  foreach f in array array['consumir_codigo_registro(text)', 'devolver_codigo_registro(uuid)', 'registrar_intento_registro(text, integer, integer)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;
