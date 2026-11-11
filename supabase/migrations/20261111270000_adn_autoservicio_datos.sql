-- Autoservicio del propietario de la iglesia: descargar todos sus datos y pedir la baja, sin pasar por la plataforma.
-- Reglas:
--  * Solo el propietario (rol con es_propietario, perfil activo) de esa iglesia. Se comprueba aquí, en la base, no solo en la función de borde.
--  * La baja NO borra nada: reutiliza el borrado suave que ya existe. La iglesia queda suspendida y se purga a los 30 días; hasta entonces
--    su propietario puede cancelar la baja. Una baja que abrió la plataforma no la puede cancelar la iglesia.
--  * Cada descarga y cada baja o cancelación queda en adn_datos_auditoria: quién, cuándo y qué. Sin datos de personas. Sin clave foránea
--    a iglesias a propósito, para que sobreviva a la purga, como adn_ciclo_auditoria. Solo se agrega: nada se edita ni se borra.
--  * Las descargas se limitan a 6 por hora y por iglesia, para que nadie convierta la exportación en un modo de cargar la base.
--  * Solo las ejecuta el servidor (función de borde `datos-iglesia`), que identifica a quien llama con su sesión.
-- Reversión: supabase/reversiones/20261111270000_adn_autoservicio_datos.down.sql
create table public.adn_datos_auditoria (
  id bigint generated always as identity primary key,
  iglesia_ref uuid not null,
  accion text not null check (accion in ('exportacion', 'baja_solicitada', 'baja_cancelada')),
  actor uuid not null,
  detalle jsonb not null default '{}'::jsonb,
  ocurrido_en timestamptz not null default now()
);
create index adn_datos_auditoria_iglesia_idx on public.adn_datos_auditoria (iglesia_ref, accion, ocurrido_en desc);
alter table public.adn_datos_auditoria enable row level security;  -- sin políticas: solo service_role
revoke all on public.adn_datos_auditoria from public, anon, authenticated;
revoke all on sequence public.adn_datos_auditoria_id_seq from public, anon, authenticated;
grant select, insert on public.adn_datos_auditoria to service_role;
grant usage, select on sequence public.adn_datos_auditoria_id_seq to service_role;

create or replace function public.adn_es_propietario(p_iglesia uuid, p_actor uuid)
returns boolean language sql stable set search_path to '' as $$
  select exists (
    select 1 from public.perfiles pf
    join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
    where pf.id = p_actor and pf.iglesia_id = p_iglesia and pf.activo and r.es_propietario
  )
$$;

-- Estado para la pantalla del propietario: la baja si la hay (cuándo se pidió, cuándo se purga, si la pidió la iglesia y se puede cancelar)
-- y cuántas descargas le quedan en esta hora
create or replace function public.adn_autoservicio_estado(p_iglesia uuid, p_actor uuid)
returns jsonb language plpgsql stable set search_path to '' as $$
declare
  v record;
  baja jsonb := null;
  propia boolean;
  usadas integer;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  select nombre, slug, etapa, adn_borrada_en, adn_borrada_por, borrado_programado_en into v from public.iglesias where id = p_iglesia;
  if not found then raise exception 'ADN_NO_PROPIETARIO'; end if;
  if v.adn_borrada_en is not null then
    propia := exists (select 1 from public.adn_datos_auditoria a
      where a.iglesia_ref = p_iglesia and a.accion = 'baja_solicitada' and a.actor = v.adn_borrada_por and a.ocurrido_en = v.adn_borrada_en);
    baja := jsonb_build_object('solicitada_en', v.adn_borrada_en, 'purga_el', v.borrado_programado_en,
      'por_la_iglesia', propia, 'cancelable', propia and v.borrado_programado_en > now());
  end if;
  select count(*) into usadas from public.adn_datos_auditoria a
    where a.iglesia_ref = p_iglesia and a.accion = 'exportacion' and a.ocurrido_en > now() - interval '1 hour';
  return jsonb_build_object('nombre', v.nombre, 'slug', v.slug, 'etapa', v.etapa, 'baja', baja,
    'descargas_restantes', greatest(0, 6 - usadas), 'plazo_dias', 30);
end $$;

-- Anota una descarga completa (se llama una vez, al empezar) y aplica el límite de 6 por hora
create or replace function public.adn_autoservicio_exportar(p_iglesia uuid, p_actor uuid)
returns void language plpgsql set search_path to '' as $$
declare
  usadas integer;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  perform pg_advisory_xact_lock(hashtextextended('adn_descarga_' || p_iglesia::text, 0));
  select count(*) into usadas from public.adn_datos_auditoria a
    where a.iglesia_ref = p_iglesia and a.accion = 'exportacion' and a.ocurrido_en > now() - interval '1 hour';
  if usadas >= 6 then raise exception 'ADN_LIMITE_DESCARGAS'; end if;
  insert into public.adn_datos_auditoria (iglesia_ref, accion, actor, detalle) values (p_iglesia, 'exportacion', p_actor, '{"paginado": true}'::jsonb);
end $$;

-- Pide la baja: borrado suave con el actor y el motivo. Devuelve la fecha de la purga (30 días). No borra nada ahora.
create or replace function public.adn_autoservicio_baja(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns timestamptz language plpgsql set search_path to '' as $$
declare
  purga timestamptz;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  purga := public.adn_borrar_suave(p_iglesia, p_actor, 'autoservicio: ' || left(coalesce(p_motivo, ''), 480));
  -- La misma transacción fija la misma fecha en el borrado y en esta anotación: así se reconoce después que la baja la pidió la iglesia
  insert into public.adn_datos_auditoria (iglesia_ref, accion, actor, detalle) values (p_iglesia, 'baja_solicitada', p_actor, jsonb_build_object('purga_el', purga));
  return purga;
end $$;

-- Cancela una baja que pidió la propia iglesia y que aún está dentro del plazo. Devuelve la etapa a la que vuelve.
create or replace function public.adn_autoservicio_cancelar_baja(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns text language plpgsql set search_path to '' as $$
declare
  v record;
  etapa text;
begin
  if not public.adn_es_propietario(p_iglesia, p_actor) then raise exception 'ADN_NO_PROPIETARIO'; end if;
  select adn_borrada_en, adn_borrada_por into v from public.iglesias where id = p_iglesia for update;
  if v.adn_borrada_en is null then raise exception 'ADN_NO_BORRADA'; end if;
  if not exists (select 1 from public.adn_datos_auditoria a
      where a.iglesia_ref = p_iglesia and a.accion = 'baja_solicitada' and a.actor = v.adn_borrada_por and a.ocurrido_en = v.adn_borrada_en) then
    raise exception 'ADN_BAJA_DE_PLATAFORMA';
  end if;
  etapa := public.adn_recuperar_iglesia(p_iglesia, p_actor, 'autoservicio: ' || left(coalesce(p_motivo, ''), 480));
  insert into public.adn_datos_auditoria (iglesia_ref, accion, actor, detalle) values (p_iglesia, 'baja_cancelada', p_actor, jsonb_build_object('etapa', etapa));
  return etapa;
end $$;

revoke all on function public.adn_es_propietario(uuid, uuid), public.adn_autoservicio_estado(uuid, uuid), public.adn_autoservicio_exportar(uuid, uuid),
  public.adn_autoservicio_baja(uuid, uuid, text), public.adn_autoservicio_cancelar_baja(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.adn_es_propietario(uuid, uuid), public.adn_autoservicio_estado(uuid, uuid), public.adn_autoservicio_exportar(uuid, uuid),
  public.adn_autoservicio_baja(uuid, uuid, text), public.adn_autoservicio_cancelar_baja(uuid, uuid, text) to service_role;
