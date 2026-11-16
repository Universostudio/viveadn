-- Vive ADN, incremental tras 20261111300000. Aplicar una vez, solo sobre un proyecto que ya tiene el paquete completo hasta esa migración. Detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261111310000_adn_asistencias_unico.sql (sha256 7a2b3835401e) =====
-- Asistencia de casa de oración: una sola fila por casa, persona y fecha.
-- Hasta ahora nada lo impedía: la pantalla evita duplicar leyendo antes de guardar, pero dos personas que guardaran a la vez
-- la lista de la misma casa y fecha podían crear dos filas, y los informes contarían dos asistencias.
--  1. Limpieza de lo que ya exista: si hay filas repetidas para la misma casa, persona y fecha, se CONSERVA LA MÁS RECIENTE
--     (por fecha de creación y, en empate, por identificador) y las demás se copian a adn_asistencias_duplicadas antes de
--     borrarse. Si no hay repetidas, no se toca ninguna fila.
--  2. Índice único por casa, persona y fecha.
-- La reversión devuelve las filas archivadas: supabase/reversiones/20261111310000_adn_asistencias_unico.down.sql

-- «if not exists» en lo que crea: el incremental se puede repetir sin error ni cambios
create table if not exists public.adn_asistencias_duplicadas (
  id uuid primary key,
  iglesia_id uuid not null,
  casa_oracion_id uuid not null,
  miembro_id uuid not null,
  fecha date not null,
  presente boolean,
  notas text,
  created_at timestamptz,
  archivada_en timestamptz not null default now()
);
create index if not exists adn_asistencias_duplicadas_iglesia_idx on public.adn_asistencias_duplicadas (iglesia_id);
-- Solo para quien opera la base: ninguna persona con sesión la lee ni la escribe
alter table public.adn_asistencias_duplicadas enable row level security;
revoke all on public.adn_asistencias_duplicadas from public, anon, authenticated;
grant all on public.adn_asistencias_duplicadas to service_role;

do $$
declare n integer;
begin
  with ordenadas as (
    select id, row_number() over (partition by casa_oracion_id, miembro_id, fecha order by created_at desc nulls last, id desc) as orden
      from public.asistencias
  ), sobran as (
    select id from ordenadas where orden > 1
  ), archivadas as (
    insert into public.adn_asistencias_duplicadas (id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente, notas, created_at)
      select a.id, a.iglesia_id, a.casa_oracion_id, a.miembro_id, a.fecha, a.presente, a.notas, a.created_at
        from public.asistencias a join sobran s on s.id = a.id
      returning id
  ), borradas as (
    delete from public.asistencias where id in (select id from archivadas) returning id
  )
  select count(*) into n from borradas;
  raise notice 'Asistencias duplicadas archivadas y borradas: %', n;
end $$;

create unique index if not exists adn_asistencias_unica_idx on public.asistencias (casa_oracion_id, miembro_id, fecha);
