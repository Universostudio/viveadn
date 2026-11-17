-- Vive ADN, traspaso al proyecto real, archivo 13 de 19: tramo 12 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('public.adn_seguimiento_alerta(timestamptz,bool,uuid,timestamptz)') is not null then raise notice 'Tramo 12 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regclass('public.adn_asistencias_duplicadas') is not null) then raise exception 'Falta aplicar antes el tramo 11 de 15: no se sigue.'; end if;
  execute $cuerpo$

-- ===== 20261111320000_adn_seguimiento_metodos (origen sha256 65cd58e56080, compilado sha256 968af270b0af) =====
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

-- Todo está escrito para poder repetirse sin error y sin reordenar los permisos (cada revoke incluye a todos los roles que luego reciben grant) (el incremental del paquete se puede volver a ejecutar): if not exists, on conflict y quitar ... if exists
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
create trigger adn_seguimiento_metodos_plantilla before insert or update of plantilla_origen on public.adn_seguimiento_metodos
  for each row execute function private.adn_comprobar_plantilla();

-- Todo proceso existente pasa a OP72 (la columna nace con ese valor por defecto: ninguna fila cambia de fecha, de color ni de resultado)
alter table public.consolidaciones add column if not exists metodo_id uuid not null default '5e000000-0000-4000-8000-000000000072'::uuid references public.adn_seguimiento_metodos(id);
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
-- ===== 20261111330000_adn_seguimiento_metricas (origen sha256 c5f74066f45c, compilado sha256 c5f74066f45c) =====
-- Método de seguimiento configurable, FASE 2: las métricas avanzadas de OP72 usan el plazo y el objetivo de primer contacto del método de cada proceso.
-- Con todos los procesos en OP72 (72 y 24 horas) el resultado es EXACTAMENTE el de antes. Las claves del resultado no cambian
-- (primer_contacto_24h y completados_72h pasan a significar «en el objetivo» y «dentro del plazo» de cada método).
-- Reversión: supabase/reversiones/20261111330000_adn_seguimiento_metricas.down.sql

create or replace function public.metricas_op72(p_desde timestamptz default (now() - interval '30 days'))
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare r jsonb;
begin
  if not (select private.tiene_modulo('op72_avanzado')) then
    raise exception 'MODULO_NO_CONTRATADO' using errcode = '42501';
  end if;
  if not (select private.tiene_permiso('consolidacion.ver')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  with c as (
    select co.consolidador_id, co.casa_oracion_id, co.completado, co.completado_at, co.fecha_conversion, co.primer_contacto_fecha,
           coalesce(m.plazo_horas, 72) as plazo,
           coalesce(m.primer_contacto_horas, 24) as objetivo_primer,
           (co.completado is not true and now() - co.fecha_conversion > make_interval(hours => coalesce(m.plazo_horas, 72))) as vencido,
           extract(epoch from (co.primer_contacto_fecha - co.fecha_conversion)) / 3600 as h_primer
      from public.consolidaciones co
      left join public.adn_seguimiento_metodos m on m.id = co.metodo_id
     where co.fecha_conversion >= p_desde
  )
  select jsonb_build_object(
    'desde', p_desde,
    'total', count(*),
    'completados', count(*) filter (where completado),
    'abiertos', count(*) filter (where completado is not true),
    'vencidos', count(*) filter (where vencido),
    'con_primer_contacto', count(*) filter (where primer_contacto_fecha is not null),
    'primer_contacto_24h', count(*) filter (where h_primer <= objetivo_primer),
    'horas_primer_contacto', round((avg(h_primer) filter (where h_primer >= 0))::numeric, 1),
    'completados_72h', count(*) filter (where completado and completado_at <= fecha_conversion + make_interval(hours => plazo)),
    'por_consolidador', coalesce((
      select jsonb_agg(t order by t.total desc, t.nombre)
        from (select x.consolidador_id, coalesce(btrim(p.nombre || ' ' || p.apellido), '') as nombre, count(*) as total,
                     count(*) filter (where x.h_primer <= x.objetivo_primer) as contacto_24h, count(*) filter (where x.vencido) as vencidos
                from c x left join public.perfiles p on p.id = x.consolidador_id
               group by x.consolidador_id, p.nombre, p.apellido
               order by count(*) desc limit 10) t), '[]'::jsonb),
    'por_casa', coalesce((
      select jsonb_agg(t order by t.total desc, t.nombre)
        from (select x.casa_oracion_id, coalesce(ca.nombre, '') as nombre, count(*) as total, count(*) filter (where x.vencido) as vencidos
                from c x left join public.casas_oracion ca on ca.id = x.casa_oracion_id
               group by x.casa_oracion_id, ca.nombre
               order by count(*) desc limit 10) t), '[]'::jsonb)
  ) into r from c;
  return r;
end;
$$;
-- Los permisos de la función no cambian: create or replace los conserva

$cuerpo$;
end $tramo$;
select 'ok: tramo 12 de 15 aplicado' as resultado, (to_regprocedure('public.adn_seguimiento_alerta(timestamptz,bool,uuid,timestamptz)') is not null) as comprobado;
