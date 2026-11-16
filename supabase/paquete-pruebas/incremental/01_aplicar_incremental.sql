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

-- ===== migrations/20261111320000_adn_seguimiento_metodos.sql (sha256 65cd58e56080) =====
-- Método de seguimiento configurable, FASE 1: esquema sin cambio visible. Diseño: docs/SEGUIMIENTO-CONFIGURABLE.md.
-- OP72 deja de estar escrito a mano y pasa a ser una plantilla de plataforma con los valores de siempre (3 pasos, 72 horas, colores a 24, 48 y 72).
--  * adn_seguimiento_metodos: plantillas de plataforma (iglesia_id nulo, uuid fijo) y métodos propios de cada iglesia (fase 3).
--  * adn_seguimiento_config: el método activo de cada iglesia; sin fila, OP72.
--  * consolidaciones.metodo_id con OP72 por defecto: todo lo existente pasa a OP72 sin cambiar ningún dato propio ni su color.
--  * El disparador de consolidaciones toma el plazo y los colores del método. Con OP72 da exactamente lo mismo que antes.
--  * adn_seguimiento_alerta() y la vista adn_seguimiento_estado, para que la fase 2 deje de usar 48 y 72 escritos a mano.
-- Una consolidación solo puede apuntar a un método de plataforma o de su propia iglesia (lo comprueba un disparador, porque las plantillas no
-- tienen iglesia y no pueden formar una clave foránea compuesta). Los procesos abiertos conservan su método aunque la iglesia cambie el activo.
-- Reversión: supabase/reversiones/20261111320000_adn_seguimiento_metodos.down.sql

-- Todo está escrito para poder repetirse sin error y sin reordenar los permisos (cada revoke incluye a todos los roles que luego reciben grant) (el incremental del paquete se puede volver a ejecutar): if not exists, on conflict y drop ... if exists
create table if not exists public.adn_seguimiento_metodos (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid references public.iglesias(id) on delete cascade,
  clave text not null check (clave ~ '^[a-z0-9_]{2,30}$'),
  nombre text not null check (length(btrim(nombre)) between 1 and 80),
  plantilla_origen uuid references public.adn_seguimiento_metodos(id) on delete set null,
  pasos smallint not null check (pasos between 1 and 3),
  plazo_horas integer not null check (plazo_horas between 1 and 720),
  -- Desde cuántas horas empieza cada color: verde hasta el amarillo, amarillo hasta el naranja, naranja hasta el plazo, rojo después
  umbral_amarillo_horas integer not null check (umbral_amarillo_horas >= 1),
  umbral_naranja_horas integer not null,
  primer_contacto_horas integer check (primer_contacto_horas is null or primer_contacto_horas >= 1),
  archivado_en timestamptz,
  created_at timestamptz not null default now(),
  constraint adn_seguimiento_metodos_umbrales check (umbral_amarillo_horas < umbral_naranja_horas and umbral_naranja_horas <= plazo_horas),
  constraint adn_seguimiento_metodos_primer check (primer_contacto_horas is null or primer_contacto_horas <= plazo_horas)
);
-- Una clave por iglesia (y una por plantilla de plataforma)
create unique index if not exists adn_seguimiento_metodos_clave_idx on public.adn_seguimiento_metodos (coalesce(iglesia_id, '00000000-0000-0000-0000-000000000000'::uuid), clave);
create index if not exists adn_seguimiento_metodos_iglesia_idx on public.adn_seguimiento_metodos (iglesia_id) where iglesia_id is not null;

alter table public.adn_seguimiento_metodos enable row level security;
-- Cada iglesia lee las plantillas de plataforma y sus propios métodos. Escribir lo hará la fase 3 con su propia política: por ahora solo el servidor.
drop policy if exists adn_seguimiento_metodos_ver on public.adn_seguimiento_metodos;
create policy adn_seguimiento_metodos_ver on public.adn_seguimiento_metodos for select to authenticated
  using (iglesia_id is null or iglesia_id = (select private.get_iglesia_id()));
revoke all on public.adn_seguimiento_metodos from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_metodos to authenticated;
grant all on public.adn_seguimiento_metodos to service_role;

-- Plantilla OP72: los valores de siempre. Seguimiento simple: valores PROPUESTOS, por validar.
insert into public.adn_seguimiento_metodos (id, iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas, primer_contacto_horas) values
  ('5e000000-0000-4000-8000-000000000072', null, 'op72', 'OP72', 3, 72, 24, 48, 24),
  ('5e000000-0000-4000-8000-000000000001', null, 'simple', 'Seguimiento simple', 1, 168, 72, 120, 72)
on conflict (id) do nothing;

create table if not exists public.adn_seguimiento_config (
  iglesia_id uuid primary key references public.iglesias(id) on delete cascade,
  metodo_id uuid not null references public.adn_seguimiento_metodos(id),
  updated_at timestamptz not null default now()
);
alter table public.adn_seguimiento_config enable row level security;
drop policy if exists adn_seguimiento_config_ver on public.adn_seguimiento_config;
create policy adn_seguimiento_config_ver on public.adn_seguimiento_config for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()));
revoke all on public.adn_seguimiento_config from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_config to authenticated;
grant all on public.adn_seguimiento_config to service_role;

-- Un método solo se usa en su iglesia (o es de plataforma), y uno archivado no se elige para algo nuevo
create or replace function private.adn_comprobar_metodo() returns trigger language plpgsql set search_path to '' as $$
declare m record;
begin
  select iglesia_id, archivado_en into m from public.adn_seguimiento_metodos where id = new.metodo_id;
  if not found then raise exception 'ADN_METODO_INEXISTENTE' using errcode = 'foreign_key_violation'; end if;
  if m.iglesia_id is not null and m.iglesia_id <> new.iglesia_id then raise exception 'ADN_METODO_DE_OTRA_IGLESIA' using errcode = 'check_violation'; end if;
  if m.archivado_en is not null and (tg_op = 'INSERT' or new.metodo_id is distinct from old.metodo_id) then raise exception 'ADN_METODO_ARCHIVADO' using errcode = 'check_violation'; end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_metodo() from public, anon, authenticated, service_role;
drop trigger if exists adn_seguimiento_config_metodo on public.adn_seguimiento_config;
create trigger adn_seguimiento_config_metodo before insert or update of metodo_id on public.adn_seguimiento_config
  for each row execute function private.adn_comprobar_metodo();

-- Un método propio solo puede copiar una plantilla de plataforma o un método de su propia iglesia
create or replace function private.adn_comprobar_plantilla() returns trigger language plpgsql set search_path to '' as $$
begin
  if new.plantilla_origen is not null and exists (select 1 from public.adn_seguimiento_metodos o where o.id = new.plantilla_origen and o.iglesia_id is not null and o.iglesia_id is distinct from new.iglesia_id) then
    raise exception 'ADN_PLANTILLA_DE_OTRA_IGLESIA' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_plantilla() from public, anon, authenticated, service_role;
drop trigger if exists adn_seguimiento_metodos_plantilla on public.adn_seguimiento_metodos;
create trigger adn_seguimiento_metodos_plantilla before insert or update of plantilla_origen on public.adn_seguimiento_metodos
  for each row execute function private.adn_comprobar_plantilla();

-- Todo proceso existente pasa a OP72 (la columna nace con ese valor por defecto: ninguna fila cambia de fecha, de color ni de resultado)
alter table public.consolidaciones add column if not exists metodo_id uuid not null default '5e000000-0000-4000-8000-000000000072'::uuid references public.adn_seguimiento_metodos(id);
drop trigger if exists consolidaciones_metodo on public.consolidaciones;
create trigger consolidaciones_metodo before insert or update of metodo_id on public.consolidaciones
  for each row execute function private.adn_comprobar_metodo();

-- El método activo de una iglesia: el que eligió o, si no eligió, OP72
create or replace function private.adn_metodo_activo(p_iglesia uuid) returns uuid language sql stable set search_path to '' as $$
  select coalesce((select c.metodo_id from public.adn_seguimiento_config c where c.iglesia_id = p_iglesia), '5e000000-0000-4000-8000-000000000072'::uuid)
$$;
revoke all on function private.adn_metodo_activo(uuid) from public, anon, authenticated, service_role;
grant execute on function private.adn_metodo_activo(uuid) to service_role;

-- La regla del color, con los números del método. Verde hasta el umbral amarillo, amarillo hasta el naranja, naranja hasta el plazo, rojo después; verde si está completado.
-- Con OP72 (24, 48, 72) da lo mismo que el código que había escrito a mano.
create or replace function private.adn_alerta_con_umbrales(p_conversion timestamptz, p_completado boolean, p_amarillo integer, p_naranja integer, p_plazo integer, p_ahora timestamptz default now())
returns text language sql immutable set search_path to '' as $$
  select case
    when coalesce(p_completado, false) then 'verde'
    when extract(epoch from (p_ahora - p_conversion)) / 3600 <= p_amarillo then 'verde'
    when extract(epoch from (p_ahora - p_conversion)) / 3600 <= p_naranja then 'amarillo'
    when extract(epoch from (p_ahora - p_conversion)) / 3600 <= p_plazo then 'naranja'
    else 'rojo' end
$$;
revoke all on function private.adn_alerta_con_umbrales(timestamptz, boolean, integer, integer, integer, timestamptz) from public, anon, authenticated, service_role;
grant execute on function private.adn_alerta_con_umbrales(timestamptz, boolean, integer, integer, integer, timestamptz) to authenticated, service_role;

-- Versión pública para consultas: lee el método (con la seguridad de quien llama, así solo ve plantillas y los métodos de su iglesia).
-- Un método que no se puede leer se trata como OP72, que es el valor de siempre.
create or replace function public.adn_seguimiento_alerta(p_conversion timestamptz, p_completado boolean, p_metodo uuid default '5e000000-0000-4000-8000-000000000072', p_ahora timestamptz default now())
returns text language sql stable set search_path to '' as $$
  select private.adn_alerta_con_umbrales(p_conversion, p_completado,
           coalesce(m.umbral_amarillo_horas, 24), coalesce(m.umbral_naranja_horas, 48), coalesce(m.plazo_horas, 72), p_ahora)
    from (select 1) x left join public.adn_seguimiento_metodos m on m.id = p_metodo
$$;
revoke all on function public.adn_seguimiento_alerta(timestamptz, boolean, uuid, timestamptz) from public, anon, authenticated, service_role;
grant execute on function public.adn_seguimiento_alerta(timestamptz, boolean, uuid, timestamptz) to authenticated, service_role;

-- El disparador toma el plazo y los colores del método del proceso. Todo lo demás (cierre, fecha de cierre, updated_at) queda igual.
create or replace function public.gestionar_consolidacion()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
DECLARE
  v_plazo integer := 72; v_amarillo integer := 24; v_naranja integer := 48;
BEGIN
  SELECT m.plazo_horas, m.umbral_amarillo_horas, m.umbral_naranja_horas INTO v_plazo, v_amarillo, v_naranja
    FROM public.adn_seguimiento_metodos m WHERE m.id = NEW.metodo_id;
  IF NOT FOUND THEN v_plazo := 72; v_amarillo := 24; v_naranja := 48; END IF;

  -- Calcular fecha limite automaticamente al insertar, con el plazo del metodo
  IF TG_OP = 'INSERT' THEN
    NEW.fecha_limite := NEW.fecha_conversion + make_interval(hours => v_plazo);
  END IF;

  -- La fecha de cierre se fija al completar y se limpia si se reabre
  IF NEW.completado IS TRUE THEN
    IF NEW.completado_at IS NULL THEN NEW.completado_at := NOW(); END IF;
  ELSE
    NEW.completado_at := NULL;
  END IF;

  -- Actualizar estado de alerta si no esta completado
  IF NEW.completado = false THEN
    NEW.estado_alerta := private.adn_alerta_con_umbrales(NEW.fecha_conversion, false, v_amarillo, v_naranja, v_plazo, NOW());
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$function$;

-- Estado de cada proceso con el color calculado ahora y el método que usa (para los recuentos de la fase 2)
create or replace view public.adn_seguimiento_estado with (security_invoker = true) as
  select c.id, c.iglesia_id, c.miembro_id, c.casa_oracion_id, c.consolidador_id, c.metodo_id, c.fecha_conversion, c.fecha_limite, c.completado,
         public.adn_seguimiento_alerta(c.fecha_conversion, c.completado, c.metodo_id) as estado
    from public.consolidaciones c;
revoke all on public.adn_seguimiento_estado from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_estado to authenticated;
grant all on public.adn_seguimiento_estado to service_role;
