-- Vive ADN, paquete de aplicación 08 de 09. Aplicar en orden y detenerse en el primer error.
set search_path = public, extensions;

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

-- ===== migrations/20261111330000_adn_seguimiento_metricas.sql (sha256 c5f74066f45c) =====
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

-- ===== migrations/20261111340000_adn_seguimiento_propio.sql (sha256 f00fb86b3cf7) =====
-- Método de seguimiento configurable, FASE 3: la iglesia elige su método y, en Premium, crea y edita el suyo. Diseño: docs/SEGUIMIENTO-CONFIGURABLE.md.
--  * Módulo nuevo seguimiento_propio (una fila en modulos y en plan_modulos, solo Premium para las pruebas de desarrollo; el empaquetado real por plan queda pendiente).
--    No se reutiliza consolidacion_etapas, que es otra idea (etapas hasta el bautismo).
--  * Elegir entre OP72 y Seguimiento simple está en todos los planes; crear y editar un método propio exige el módulo. Quien configura es quien tiene iglesia.configurar.
--  * Escritura por seguridad de filas, sin funciones nuevas para guardar: solo se pueden insertar y editar métodos de la propia iglesia, y solo las columnas de contenido
--    (la iglesia, la clave y la plantilla de origen no se pueden cambiar). Nada se borra: un método se archiva, y uno archivado o activo no se archiva ni se elige de nuevo.
--  * Un proceso nuevo toma el método activo de la iglesia (sin fila de configuración, OP72) mediante un disparador; la columna sigue con OP72 por defecto. Los procesos abiertos conservan el suyo.
--  * Si se editan los plazos de un método, la fecha límite y el color de sus procesos abiertos se recalculan; los completados no cambian.
--  * adn_seguimiento_en_uso() dice cuántos procesos usan un método, para avisar antes de guardar.
-- Reversión: supabase/reversiones/20261111340000_adn_seguimiento_propio.down.sql (deja los métodos propios y los procesos como están: solo quita la posibilidad de editarlos).

insert into public.modulos (clave, nombre, descripcion, tipo, orden) values
  ('seguimiento_propio', 'Método de seguimiento propio', 'La iglesia crea y edita su propio método de seguimiento de nuevas personas: número de contactos, plazo y colores', 'especial', 216)
on conflict (clave) do nothing;
insert into public.plan_modulos (plan, modulo) values ('premium', 'seguimiento_propio') on conflict do nothing;

-- La comprobación de la plantilla de origen debe poder mirar métodos de otras iglesias que quien escribe no ve: con la seguridad de quien llama,
-- el método ajeno no se vería y la copia pasaría. Por eso pasa a security definer (su contenido no cambia).
create or replace function private.adn_comprobar_plantilla() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.plantilla_origen is not null and exists (select 1 from public.adn_seguimiento_metodos o where o.id = new.plantilla_origen and o.iglesia_id is not null and o.iglesia_id is distinct from new.iglesia_id) then
    raise exception 'ADN_PLANTILLA_DE_OTRA_IGLESIA' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_plantilla() from public, anon, authenticated, service_role;
-- Lo mismo con la comprobación del método de un proceso o de la configuración: debe distinguir «no existe» de «es de otra iglesia» sin que la seguridad de filas esconda la fila
create or replace function private.adn_comprobar_metodo() returns trigger language plpgsql security definer set search_path to '' as $$
declare m record;
begin
  select iglesia_id, archivado_en into m from public.adn_seguimiento_metodos where id = new.metodo_id;
  if not found then raise exception 'ADN_METODO_INEXISTENTE' using errcode = 'foreign_key_violation'; end if;
  if m.iglesia_id is not null and m.iglesia_id <> new.iglesia_id then raise exception 'ADN_METODO_DE_OTRA_IGLESIA' using errcode = 'check_violation'; end if;
  if m.archivado_en is not null and (tg_op = 'INSERT' or new.metodo_id is distinct from old.metodo_id) then raise exception 'ADN_METODO_ARCHIVADO' using errcode = 'check_violation'; end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_metodo() from public, anon, authenticated, service_role;

-- Un método se puede elegir si es de plataforma o es de la propia iglesia con el módulo contratado, y no está archivado
create or replace function private.adn_metodo_usable(p_metodo uuid) returns boolean language sql stable security definer set search_path to '' as $$
  select exists (
    select 1 from public.adn_seguimiento_metodos m
     where m.id = p_metodo and m.archivado_en is null
       and (m.iglesia_id is null or (m.iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_modulo('seguimiento_propio'))))
  )
$$;
revoke all on function private.adn_metodo_usable(uuid) from public, anon, authenticated, service_role;
grant execute on function private.adn_metodo_usable(uuid) to authenticated, service_role;

-- Escritura sobre los métodos: solo los de la propia iglesia, con permiso de configuración y con el módulo
revoke all on public.adn_seguimiento_metodos from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_metodos to authenticated;
grant insert (id, iglesia_id, clave, nombre, plantilla_origen, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas, primer_contacto_horas) on public.adn_seguimiento_metodos to authenticated;
grant update (nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas, primer_contacto_horas, archivado_en) on public.adn_seguimiento_metodos to authenticated;
grant all on public.adn_seguimiento_metodos to service_role;
drop policy if exists adn_seguimiento_metodos_crear on public.adn_seguimiento_metodos;
create policy adn_seguimiento_metodos_crear on public.adn_seguimiento_metodos for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and archivado_en is null
              and (select private.tiene_permiso('iglesia.configurar')) and (select private.tiene_modulo('seguimiento_propio')));
drop policy if exists adn_seguimiento_metodos_editar on public.adn_seguimiento_metodos;
create policy adn_seguimiento_metodos_editar on public.adn_seguimiento_metodos for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.tiene_modulo('seguimiento_propio')))
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.tiene_modulo('seguimiento_propio')));

-- Como mucho diez métodos propios sin archivar por iglesia
create or replace function private.adn_limitar_metodos() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.iglesia_id is not null and (select count(*) from public.adn_seguimiento_metodos m where m.iglesia_id = new.iglesia_id and m.archivado_en is null) >= 10 then
    raise exception 'ADN_DEMASIADOS_METODOS' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_limitar_metodos() from public, anon, authenticated, service_role;
drop trigger if exists adn_seguimiento_metodos_limite on public.adn_seguimiento_metodos;
create trigger adn_seguimiento_metodos_limite before insert on public.adn_seguimiento_metodos
  for each row execute function private.adn_limitar_metodos();

-- El método que la iglesia tiene activo no se archiva (primero se elige otro)
create or replace function private.adn_no_archivar_activo() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.archivado_en is not null and old.archivado_en is null and exists (select 1 from public.adn_seguimiento_config c where c.metodo_id = new.id) then
    raise exception 'ADN_METODO_ACTIVO' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_no_archivar_activo() from public, anon, authenticated, service_role;
drop trigger if exists adn_seguimiento_metodos_archivo on public.adn_seguimiento_metodos;
create trigger adn_seguimiento_metodos_archivo before update of archivado_en on public.adn_seguimiento_metodos
  for each row execute function private.adn_no_archivar_activo();

-- Si cambian el plazo o los colores, los procesos abiertos de ese método recalculan su fecha límite y su color. Los completados no cambian.
create or replace function private.adn_metodo_recalcular() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.plazo_horas is distinct from old.plazo_horas or new.umbral_amarillo_horas is distinct from old.umbral_amarillo_horas or new.umbral_naranja_horas is distinct from old.umbral_naranja_horas then
    update public.consolidaciones c set fecha_limite = c.fecha_conversion + make_interval(hours => new.plazo_horas)
     where c.metodo_id = new.id and c.completado is not true;
  end if;
  return null;
end $$;
revoke all on function private.adn_metodo_recalcular() from public, anon, authenticated, service_role;
drop trigger if exists adn_seguimiento_metodos_recalcular on public.adn_seguimiento_metodos;
create trigger adn_seguimiento_metodos_recalcular after update of plazo_horas, umbral_amarillo_horas, umbral_naranja_horas on public.adn_seguimiento_metodos
  for each row execute function private.adn_metodo_recalcular();

-- Elegir el método activo de la iglesia
revoke all on public.adn_seguimiento_config from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_config to authenticated;
grant insert (iglesia_id, metodo_id), update (metodo_id) on public.adn_seguimiento_config to authenticated;
grant all on public.adn_seguimiento_config to service_role;
drop policy if exists adn_seguimiento_config_elegir on public.adn_seguimiento_config;
create policy adn_seguimiento_config_elegir on public.adn_seguimiento_config for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.adn_metodo_usable(metodo_id)));
drop policy if exists adn_seguimiento_config_cambiar on public.adn_seguimiento_config;
create policy adn_seguimiento_config_cambiar on public.adn_seguimiento_config for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')))
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.adn_metodo_usable(metodo_id)));
create or replace function private.adn_config_tocar() returns trigger language plpgsql set search_path to '' as $$
begin new.updated_at := now(); return new; end $$;
revoke all on function private.adn_config_tocar() from public, anon, authenticated, service_role;
drop trigger if exists adn_seguimiento_config_fecha on public.adn_seguimiento_config;
create trigger adn_seguimiento_config_fecha before update on public.adn_seguimiento_config for each row execute function private.adn_config_tocar();

-- Un proceso nuevo toma el método activo de la iglesia. La columna conserva OP72 como valor por defecto (es la red de seguridad de las cargas sin disparadores,
-- como una restauración); este disparador, que se ejecuta antes que el de comprobación por llevar un nombre anterior en orden alfabético, cambia OP72 por el
-- método activo cuando la iglesia eligió otro. Un método distinto de OP72 dado a mano se respeta. Límite conocido: un proceso insertado a mano con OP72
-- explícito en una iglesia que usa otro método pasa al método activo; las restauraciones se hacen sin disparadores (docs/EXPORTACION.md) y no se ven afectadas.
create or replace function private.adn_consolidacion_metodo_activo() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.metodo_id = '5e000000-0000-4000-8000-000000000072'::uuid then new.metodo_id := private.adn_metodo_activo(new.iglesia_id); end if;
  return new;
end $$;
revoke all on function private.adn_consolidacion_metodo_activo() from public, anon, authenticated, service_role;
drop trigger if exists consolidaciones_a_metodo on public.consolidaciones;
create trigger consolidaciones_a_metodo before insert on public.consolidaciones for each row execute function private.adn_consolidacion_metodo_activo();

-- Cuántos procesos de la iglesia usan un método (para avisar antes de guardar un cambio). Solo lo ve quien puede configurar.
-- La parte con privilegios vive en private (la regla del proyecto es que en public no haya funciones con SECURITY DEFINER); la pública solo la llama.
create or replace function private.adn_seguimiento_en_uso(p_metodo uuid) returns jsonb language sql stable security definer set search_path to '' as $$
  select case when (select private.tiene_permiso('iglesia.configurar')) then
    (select jsonb_build_object('abiertos', count(*) filter (where c.completado is not true), 'total', count(*))
       from public.consolidaciones c where c.iglesia_id = (select private.get_iglesia_id()) and c.metodo_id = p_metodo)
  end
$$;
revoke all on function private.adn_seguimiento_en_uso(uuid) from public, anon, authenticated, service_role;
grant execute on function private.adn_seguimiento_en_uso(uuid) to authenticated, service_role;
create or replace function public.adn_seguimiento_en_uso(p_metodo uuid) returns jsonb language sql stable set search_path to '' as $$
  select private.adn_seguimiento_en_uso(p_metodo)
$$;
revoke all on function public.adn_seguimiento_en_uso(uuid) from public, anon, authenticated, service_role;
grant execute on function public.adn_seguimiento_en_uso(uuid) to authenticated, service_role;

-- ===== migrations/20261111350000_adn_soporte.sql (sha256 dddf06b599e8) =====
-- Soporte dentro de la plataforma, sin servicios externos de pago. Tres piezas independientes:
--  (a) Tickets: la iglesia (quien puede configurarla, iglesia.configurar) abre un ticket con asunto, texto y prioridad y sigue su conversación; la plataforma
--      lo ve, responde y cierra desde la función de borde (service_role). Una iglesia solo ve los suyos.
--  (b) Novedades de plataforma: registro de cambios publicado por la plataforma (versión, fecha, texto), que lee cualquier persona con sesión, con una marca
--      de «vistas» por persona para el aviso de «novedades».
--  (c) Avisos masivos dentro de la aplicación: la plataforma redacta un aviso (actualización, mantenimiento o alerta) y elige destinatarios (todas, por plan
--      o por estado). Al crearlo se reparte una entrega a cada iglesia destinataria; cada iglesia lo ve como banner descartable y queda registro de entrega,
--      lectura y descarte. El correo masivo NO se envía: solo se anota si se pidió y que el envío está apagado.
-- Todo con el prefijo adn_. Las tablas con iglesia_id caen con la iglesia al purgarla.
-- Reversión: supabase/reversiones/20261111350000_adn_soporte.down.sql (borra estas tablas y sus datos: es lo único que se pierde).
-- Escrito para poder repetirse sin error y sin reordenar permisos (if not exists, drop ... if exists, create or replace, revoke con todos los roles).

-- ---------------------------------------------------------------- (a) Tickets
create table if not exists public.adn_tickets (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  creado_por uuid not null default auth.uid(),
  asunto text not null check (length(btrim(asunto)) between 3 and 120),
  prioridad text not null default 'normal' check (prioridad in ('baja', 'normal', 'alta', 'urgente')),
  estado text not null default 'abierto' check (estado in ('abierto', 'respondido', 'cerrado')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cerrado_en timestamptz,
  constraint adn_tickets_cierre check ((estado = 'cerrado') = (cerrado_en is not null)),
  constraint adn_tickets_id_iglesia_uq unique (id, iglesia_id)
);
create index if not exists adn_tickets_iglesia_idx on public.adn_tickets (iglesia_id, created_at desc);
create index if not exists adn_tickets_estado_idx on public.adn_tickets (estado, updated_at desc);

create table if not exists public.adn_ticket_mensajes (
  id bigint generated always as identity primary key,
  ticket_id uuid not null,
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  -- Clave compuesta con la iglesia: un mensaje nunca puede apuntar al ticket de otra iglesia
  constraint adn_ticket_mensajes_ticket_fk foreign key (ticket_id, iglesia_id) references public.adn_tickets (id, iglesia_id) on delete cascade,
  autor_tipo text not null default 'iglesia' check (autor_tipo in ('iglesia', 'plataforma')),
  autor uuid default auth.uid(),
  texto text not null check (length(btrim(texto)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists adn_ticket_mensajes_ticket_idx on public.adn_ticket_mensajes (ticket_id, id);
create index if not exists adn_ticket_mensajes_iglesia_idx on public.adn_ticket_mensajes (iglesia_id);

alter table public.adn_tickets enable row level security;
alter table public.adn_ticket_mensajes enable row level security;

-- Cada mensaje hereda la iglesia de su ticket (con privilegios, para que el ticket de otra iglesia no se «vea» a medias y falle por no nulo)
create or replace function private.adn_mensaje_iglesia() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  select t.iglesia_id into new.iglesia_id from public.adn_tickets t where t.id = new.ticket_id;
  if new.iglesia_id is null then raise exception 'ADN_TICKET_INEXISTENTE' using errcode = 'foreign_key_violation'; end if;
  return new;
end $$;
revoke all on function private.adn_mensaje_iglesia() from public, anon, authenticated, service_role;
drop trigger if exists adn_ticket_mensajes_iglesia on public.adn_ticket_mensajes;
create trigger adn_ticket_mensajes_iglesia before insert on public.adn_ticket_mensajes for each row execute function private.adn_mensaje_iglesia();

-- Una conversación cerrada no admite mensajes, y un mensaje cambia el estado: la iglesia reabre (abierto), la plataforma responde (respondido)
create or replace function private.adn_mensaje_estado() returns trigger language plpgsql security definer set search_path to '' as $$
declare v_estado text;
begin
  select estado into v_estado from public.adn_tickets where id = new.ticket_id for update;
  if v_estado = 'cerrado' then raise exception 'ADN_TICKET_CERRADO' using errcode = 'check_violation'; end if;
  if (select count(*) from public.adn_ticket_mensajes m where m.ticket_id = new.ticket_id) > 200 then raise exception 'ADN_TICKET_LLENO' using errcode = 'check_violation'; end if;
  update public.adn_tickets set updated_at = now(),
    estado = case when new.autor_tipo = 'plataforma' then 'respondido' else 'abierto' end
   where id = new.ticket_id;
  return new;
end $$;
revoke all on function private.adn_mensaje_estado() from public, anon, authenticated, service_role;
drop trigger if exists adn_ticket_mensajes_estado on public.adn_ticket_mensajes;
create trigger adn_ticket_mensajes_estado after insert on public.adn_ticket_mensajes for each row execute function private.adn_mensaje_estado();

-- Como mucho diez tickets sin cerrar por iglesia
create or replace function private.adn_tickets_limite() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if (select count(*) from public.adn_tickets t where t.iglesia_id = new.iglesia_id and t.estado <> 'cerrado') >= 10 then
    raise exception 'ADN_DEMASIADOS_TICKETS' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_tickets_limite() from public, anon, authenticated, service_role;
drop trigger if exists adn_tickets_limite on public.adn_tickets;
create trigger adn_tickets_limite before insert on public.adn_tickets for each row execute function private.adn_tickets_limite();

-- La iglesia ve y escribe solo lo suyo y solo con iglesia.configurar. El estado, el cierre y las respuestas de la plataforma los pone el servidor.
revoke all on public.adn_tickets from public, anon, authenticated, service_role;
grant select on public.adn_tickets to authenticated;
grant insert (asunto, prioridad) on public.adn_tickets to authenticated;
grant all on public.adn_tickets to service_role;
revoke all on public.adn_ticket_mensajes from public, anon, authenticated, service_role;
grant select on public.adn_ticket_mensajes to authenticated;
grant insert (ticket_id, texto) on public.adn_ticket_mensajes to authenticated;
grant all on public.adn_ticket_mensajes to service_role;
revoke all on sequence public.adn_ticket_mensajes_id_seq from public, anon, authenticated, service_role;
grant usage, select on sequence public.adn_ticket_mensajes_id_seq to authenticated, service_role;

drop policy if exists adn_tickets_ver on public.adn_tickets;
create policy adn_tickets_ver on public.adn_tickets for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_tickets_crear on public.adn_tickets;
create policy adn_tickets_crear on public.adn_tickets for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and creado_por = (select auth.uid()) and estado = 'abierto' and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_ticket_mensajes_ver on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_ver on public.adn_ticket_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_ticket_mensajes_crear on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_crear on public.adn_ticket_mensajes for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and autor_tipo = 'iglesia' and autor = (select auth.uid()) and (select private.tiene_permiso('iglesia.configurar')));

-- Abrir un ticket con su primer mensaje de una vez. Con los permisos de quien llama (security invoker): si no puede, falla por la seguridad de filas.
create or replace function public.adn_ticket_crear(p_asunto text, p_prioridad text, p_texto text) returns uuid language plpgsql set search_path to '' as $$
declare v_id uuid;
begin
  insert into public.adn_tickets (asunto, prioridad) values (p_asunto, coalesce(p_prioridad, 'normal')) returning id into v_id;
  insert into public.adn_ticket_mensajes (ticket_id, texto) values (v_id, p_texto);
  return v_id;
end $$;
revoke all on function public.adn_ticket_crear(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.adn_ticket_crear(text, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------- (b) Novedades de plataforma
create table if not exists public.adn_novedades (
  id uuid primary key default gen_random_uuid(),
  version text not null check (length(btrim(version)) between 1 and 30),
  titulo text not null check (length(btrim(titulo)) between 3 and 120),
  texto text not null check (length(btrim(texto)) between 1 and 4000),
  publicada_en timestamptz not null default now(),
  publicada_por uuid,
  retirada_en timestamptz
);
create index if not exists adn_novedades_fecha_idx on public.adn_novedades (publicada_en desc);
alter table public.adn_novedades enable row level security;
revoke all on public.adn_novedades from public, anon, authenticated, service_role;
grant select on public.adn_novedades to authenticated;
grant all on public.adn_novedades to service_role;
drop policy if exists adn_novedades_ver on public.adn_novedades;
create policy adn_novedades_ver on public.adn_novedades for select to authenticated using (retirada_en is null);

-- Qué novedades ya vio cada persona: una fila por persona
create table if not exists public.adn_novedades_vistas (
  usuario uuid primary key default auth.uid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  vista_en timestamptz not null default now()
);
create index if not exists adn_novedades_vistas_iglesia_idx on public.adn_novedades_vistas (iglesia_id);
alter table public.adn_novedades_vistas enable row level security;
revoke all on public.adn_novedades_vistas from public, anon, authenticated, service_role;
grant select on public.adn_novedades_vistas to authenticated;
grant insert (vista_en) on public.adn_novedades_vistas to authenticated;
grant update (vista_en) on public.adn_novedades_vistas to authenticated;
grant all on public.adn_novedades_vistas to service_role;
drop policy if exists adn_novedades_vistas_ver on public.adn_novedades_vistas;
create policy adn_novedades_vistas_ver on public.adn_novedades_vistas for select to authenticated
  using (usuario = (select auth.uid()) and iglesia_id = (select private.get_iglesia_id()));
drop policy if exists adn_novedades_vistas_crear on public.adn_novedades_vistas;
create policy adn_novedades_vistas_crear on public.adn_novedades_vistas for insert to authenticated
  with check (usuario = (select auth.uid()) and iglesia_id = (select private.get_iglesia_id()));
drop policy if exists adn_novedades_vistas_cambiar on public.adn_novedades_vistas;
create policy adn_novedades_vistas_cambiar on public.adn_novedades_vistas for update to authenticated
  using (usuario = (select auth.uid()) and iglesia_id = (select private.get_iglesia_id()))
  with check (usuario = (select auth.uid()) and iglesia_id = (select private.get_iglesia_id()));

-- Marca las novedades como vistas ahora (con los permisos de quien llama)
create or replace function public.adn_novedades_marcar_vistas() returns void language sql set search_path to '' as $$
  insert into public.adn_novedades_vistas (vista_en) values (now())
  on conflict (usuario) do update set vista_en = excluded.vista_en
$$;
revoke all on function public.adn_novedades_marcar_vistas() from public, anon, authenticated, service_role;
grant execute on function public.adn_novedades_marcar_vistas() to authenticated, service_role;

-- ---------------------------------------------------------------- (c) Avisos masivos dentro de la aplicación
-- destino: {"todas": true} (las iglesias operativas) o {"planes": [...], "estados": [...]} (ambos opcionales; juntos, se piden los dos)
create or replace function private.adn_destino_valido(d jsonb) returns boolean language sql immutable set search_path to '' as $$
  select jsonb_typeof(d) = 'object'
     and not exists (select 1 from jsonb_object_keys(d) k where k not in ('todas', 'planes', 'estados'))
     and (not d ? 'todas' or jsonb_typeof(d -> 'todas') = 'boolean')
     and (not d ? 'planes' or (jsonb_typeof(d -> 'planes') = 'array' and jsonb_array_length(d -> 'planes') between 1 and 20 and not exists (select 1 from jsonb_array_elements(d -> 'planes') e where jsonb_typeof(e) <> 'string')))
     and (not d ? 'estados' or (jsonb_typeof(d -> 'estados') = 'array' and jsonb_array_length(d -> 'estados') between 1 and 5 and not exists (select 1 from jsonb_array_elements(d -> 'estados') e where jsonb_typeof(e) <> 'string' or (e #>> '{}') not in ('onboarding', 'prueba', 'activa', 'receso', 'suspendida'))))
     and (d ? 'todas' or d ? 'planes' or d ? 'estados')
$$;
revoke all on function private.adn_destino_valido(jsonb) from public, anon, authenticated, service_role;
grant execute on function private.adn_destino_valido(jsonb) to service_role;

create table if not exists public.adn_avisos (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('actualizacion', 'mantenimiento', 'alerta')),
  titulo text not null check (length(btrim(titulo)) between 3 and 120),
  texto text not null check (length(btrim(texto)) between 1 and 2000),
  destino jsonb not null default '{"todas": true}'::jsonb,
  incluir_demo boolean not null default false,
  desde timestamptz not null default now(),
  hasta timestamptz,
  creado_por uuid,
  created_at timestamptz not null default now(),
  retirado_en timestamptz,
  por_correo boolean not null default false,
  correo_estado text not null default 'no_pedido' check (correo_estado in ('no_pedido', 'apagado', 'pendiente')),
  constraint adn_avisos_destino check (private.adn_destino_valido(destino)),
  constraint adn_avisos_vigencia check (hasta is null or hasta > desde),
  constraint adn_avisos_correo check ((por_correo = false and correo_estado = 'no_pedido') or (por_correo and correo_estado <> 'no_pedido'))
);
create table if not exists public.adn_avisos_entregas (
  aviso_id uuid not null references public.adn_avisos(id) on delete cascade,
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  entregado_en timestamptz not null default now(),
  leido_en timestamptz,
  descartado_en timestamptz,
  primary key (aviso_id, iglesia_id)
);
create index if not exists adn_avisos_entregas_iglesia_idx on public.adn_avisos_entregas (iglesia_id);
alter table public.adn_avisos enable row level security;
alter table public.adn_avisos_entregas enable row level security;
revoke all on public.adn_avisos from public, anon, authenticated, service_role;
grant select on public.adn_avisos to authenticated;
grant all on public.adn_avisos to service_role;
revoke all on public.adn_avisos_entregas from public, anon, authenticated, service_role;
grant select on public.adn_avisos_entregas to authenticated;
grant update (leido_en, descartado_en) on public.adn_avisos_entregas to authenticated;
grant all on public.adn_avisos_entregas to service_role;

-- Cada iglesia lee y marca solo sus entregas; solo ve los avisos que le llegaron, vigentes y no retirados
drop policy if exists adn_avisos_entregas_ver on public.adn_avisos_entregas;
create policy adn_avisos_entregas_ver on public.adn_avisos_entregas for select to authenticated using (iglesia_id = (select private.get_iglesia_id()));
drop policy if exists adn_avisos_entregas_marcar on public.adn_avisos_entregas;
create policy adn_avisos_entregas_marcar on public.adn_avisos_entregas for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id())) with check (iglesia_id = (select private.get_iglesia_id()));
drop policy if exists adn_avisos_ver on public.adn_avisos;
create policy adn_avisos_ver on public.adn_avisos for select to authenticated
  using (retirado_en is null and desde <= now() and (hasta is null or hasta > now())
         and exists (select 1 from public.adn_avisos_entregas e where e.aviso_id = adn_avisos.id and e.iglesia_id = (select private.get_iglesia_id())));

-- Reparte un aviso a las iglesias destinatarias. Solo el servidor. Devuelve cuántas. Las demostraciones solo entran si el aviso lo pide;
-- las que están en baja (borrado suave) nunca. «todas» son las iglesias operativas (en alta, prueba y activa).
create or replace function public.adn_aviso_entregar(p_aviso uuid) returns integer language plpgsql set search_path to '' as $$
declare a record; n integer;
begin
  select * into a from public.adn_avisos where id = p_aviso;
  if not found then raise exception 'ADN_AVISO_INEXISTENTE'; end if;
  insert into public.adn_avisos_entregas (aviso_id, iglesia_id)
  select a.id, i.id from public.iglesias i
   where i.adn_borrada_en is null
     and (a.incluir_demo or not i.es_demo)
     and case
           when coalesce((a.destino ->> 'todas')::boolean, false) then i.etapa in ('onboarding', 'prueba', 'activa')
           else (not a.destino ? 'planes' or i.plan in (select jsonb_array_elements_text(a.destino -> 'planes')))
            and (case when a.destino ? 'estados' then i.etapa in (select jsonb_array_elements_text(a.destino -> 'estados')) else i.etapa in ('onboarding', 'prueba', 'activa') end)
         end
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.adn_aviso_entregar(uuid) from public, anon, authenticated, service_role;
grant execute on function public.adn_aviso_entregar(uuid) to service_role;

-- ---------------------------------------------------------------- Exportación
-- Las entregas de avisos son un registro operativo de la plataforma sobre avisos que son globales (no llevan iglesia_id y no se exportan): sin el aviso no se
-- pueden cargar, así que quedan fuera de la exportación de la iglesia, igual que los enlaces de baja y las confirmaciones. Los tickets, sus mensajes y la marca de
-- novedades vistas sí salen. Es la misma función de siempre con una exclusión más.
create or replace function public.adn_tablas_exportables()
returns table (nombre text, filtro text) language sql stable set search_path to '' as $$
  select 'iglesias'::text, 'id = $1'::text
  union all
  select c.relname::text, 'iglesia_id = $1'
  from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
    -- La auditoria de la plataforma son acciones internas y puede llevar notas de administracion: no sale en la exportacion de la iglesia
    and c.relname not in ('plataforma_auditoria', 'adn_bajas_enlaces', 'adn_confirmaciones', 'adn_avisos_entregas')
    -- (adn_bajas_enlaces y adn_confirmaciones: secretos efimeros de un solo uso, sin valor fuera de la base; adn_avisos_entregas: ver arriba)
    and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
  union all
  select 'rol_permisos', 'rol_id in (select id from public.roles where iglesia_id = $1)'
$$;

-- ===== migrations/20261111360000_adn_precios_plan.sql (sha256 06083fc9aa73) =====
-- Precios por plan (modo de prueba). Solo añade tres columnas opcionales a planes: precio mensual y anual en céntimos y la moneda.
-- Quedan VACÍAS: los valores los fija quien opera la plataforma cuando estén validados (hoy son una propuesta pendiente), y mientras estén vacías el panel
-- lo dice en vez de inventar un precio. No cobra nada ni conecta ninguna pasarela. Reversión: reversiones/20261111360000_adn_precios_plan.down.sql.
alter table public.planes add column if not exists precio_mensual_centimos integer;
alter table public.planes add column if not exists precio_anual_centimos integer;
alter table public.planes add column if not exists moneda text;
alter table public.planes drop constraint if exists adn_planes_precio_coherente;
alter table public.planes add constraint adn_planes_precio_coherente check (
  (precio_mensual_centimos is null or precio_mensual_centimos between 0 and 10000000)
  and (precio_anual_centimos is null or precio_anual_centimos between 0 and 100000000)
  and (moneda is null or moneda ~ '^[A-Z]{3}$')
  and ((precio_mensual_centimos is null and precio_anual_centimos is null) or moneda is not null));

-- ===== migrations/20261111370000_adn_prueba_vencida_lectura.sql (sha256 b86ac835b780) =====
-- Prueba vencida: el núcleo sigue disponible en SOLO LECTURA. Antes, una prueba vencida cortaba todos los módulos y la iglesia no podía ni ver sus datos.
-- Regla: con la prueba vencida (etapa 'prueba' y prueba_hasta pasada), tiene_permiso concede únicamente los permisos de LECTURA (ver, ver_asignados, ver_casa,
-- ver_propia y exportar) de los módulos del NÚCLEO que el plan incluye. Nada de escribir, nada de los módulos incluidos ni de pago. tiene_modulo no cambia.
-- Quien es propietario conserva además la descarga de su copia (función datos-iglesia). Reversión: reversiones/20261111370000_adn_prueba_vencida_lectura.down.sql.
create or replace function private.adn_nucleo_en_lectura(p_modulo text, p_permiso text)
returns boolean language sql stable security definer set search_path to '' as $$
  select p_permiso ~ '\.(ver|ver_asignados|ver_casa|ver_propia|exportar)$'
    and exists (
      select 1 from public.iglesias i join public.modulos m on m.clave = p_modulo and m.tipo = 'nucleo'
      where i.id = (select private.get_iglesia_id()) and i.activa
        and i.etapa = 'prueba' and i.prueba_hasta is not null and i.prueba_hasta <= now()
        and exists (select 1 from public.plan_modulos pm where pm.plan = i.plan and pm.modulo = p_modulo)
    )
$$;
revoke all on function private.adn_nucleo_en_lectura(text, text) from public, anon, authenticated, service_role;
grant execute on function private.adn_nucleo_en_lectura(text, text) to authenticated, service_role;

create or replace function private.tiene_permiso(p_permiso text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.permisos pe
    where pe.clave = p_permiso and (private.tiene_modulo(pe.modulo) or private.adn_nucleo_en_lectura(pe.modulo, pe.clave))
  ) and exists (
    select 1
    from public.perfiles pf
    join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
    where pf.id = (select auth.uid())
      and pf.activo
      and (r.es_propietario
           or exists (select 1 from public.rol_permisos rp where rp.rol_id = r.id and rp.permiso = p_permiso))
  )
$function$;

-- ===== migrations/20261111380000_adn_purga_tarea_estado.sql (sha256 73fd429e1604) =====
-- Estado de la tarea programada de purga, para mostrarlo en «Sistema». Lee pg_cron si existe y, si no, dice «no disponible» (la base local no tiene la extensión).
-- Solo devuelve el nombre de la tarea, su horario, si está activa y cómo terminó su última pasada: nunca la orden completa, que lleva cabeceras con secretos.
-- Función de definidor en `private` y envoltorio de invocador en `public`, ejecutable solo por el servidor. Reversión: reversiones/20261111380000_adn_purga_tarea_estado.down.sql.
create or replace function private.adn_purga_tarea_estado() returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare r jsonb;
begin
  if to_regclass('cron.job') is null or to_regclass('cron.job_run_details') is null then
    return jsonb_build_object('disponible', false, 'tareas', '[]'::jsonb);
  end if;
  execute $q$
    select jsonb_build_object('disponible', true, 'tareas', coalesce(jsonb_agg(jsonb_build_object(
      'nombre', j.jobname, 'programacion', j.schedule, 'activa', j.active,
      'ultima_pasada', u.start_time, 'ultimo_resultado', u.status) order by j.jobname), '[]'::jsonb))
    from cron.job j
    left join lateral (select d.start_time, d.status from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1) u on true
    where j.jobname like 'adn-%'
  $q$ into r;
  return r;
end $$;
revoke all on function private.adn_purga_tarea_estado() from public, anon, authenticated, service_role;
grant execute on function private.adn_purga_tarea_estado() to service_role;

create or replace function public.adn_purga_tarea_estado() returns jsonb language sql stable set search_path to '' as $$
  select private.adn_purga_tarea_estado()
$$;
revoke all on function public.adn_purga_tarea_estado() from public, anon, authenticated, service_role;
grant execute on function public.adn_purga_tarea_estado() to service_role;

-- ===== migrations/20261111390000_adn_soporte_prueba_vencida.sql (sha256 2e391cdde5de) =====
-- Soporte con la prueba vencida: una iglesia en solo lectura (prueba vencida) debe poder pedir ayuda y leer las respuestas, justo cuando más lo necesita.
-- Antes, los tickets exigían tiene_permiso('iglesia.configurar') y con la prueba vencida ese permiso se cierra. Ahora basta ese permiso O ser propietario activo de una
-- iglesia que sigue activa (en receso o suspendida no hay acceso). Solo cambian las cuatro políticas de tickets y mensajes. Reversión: reversiones/20261111390000_adn_soporte_prueba_vencida.down.sql.
create or replace function private.adn_puede_pedir_ayuda() returns boolean language sql stable security definer set search_path to '' as $$
  select private.tiene_permiso('iglesia.configurar')
    or exists (
      select 1 from public.perfiles pf
      join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
      join public.iglesias i on i.id = pf.iglesia_id
      where pf.id = (select auth.uid()) and pf.activo and r.es_propietario and i.activa and i.adn_borrada_en is null
    )
$$;
revoke all on function private.adn_puede_pedir_ayuda() from public, anon, authenticated, service_role;
grant execute on function private.adn_puede_pedir_ayuda() to authenticated, service_role;

drop policy if exists adn_tickets_ver on public.adn_tickets;
create policy adn_tickets_ver on public.adn_tickets for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_tickets_crear on public.adn_tickets;
create policy adn_tickets_crear on public.adn_tickets for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and creado_por = (select auth.uid()) and estado = 'abierto' and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_ticket_mensajes_ver on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_ver on public.adn_ticket_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_ticket_mensajes_crear on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_crear on public.adn_ticket_mensajes for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and autor_tipo = 'iglesia' and autor = (select auth.uid()) and (select private.adn_puede_pedir_ayuda()));
