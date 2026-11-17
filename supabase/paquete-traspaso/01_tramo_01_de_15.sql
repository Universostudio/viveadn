-- Vive ADN, traspaso al proyecto real, archivo 2 de 19: tramo 1 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('public.adn_tablas_exportables()') is not null then raise notice 'Tramo 1 de 15 ya aplicado: no se repite'; return; end if;
  execute $cuerpo$

-- ===== 20261111120000_adn_ciclo_vida (origen sha256 f51290e88822, compilado sha256 ba82a37d77dc) =====
-- Ciclo de vida de la iglesia, segunda parte: borrado suave con plazo de gracia fijo de 30 dias,
-- recuperacion, purga de lo vencido y registro de auditoria que sobrevive a la purga.
-- Se apoya en lo que ya existe (etapa, borrado_programado_en, borrar_iglesia) y no lo renombra.
-- Reversion: supabase/reversiones/20261111120000_adn_ciclo_vida.down.sql (probada por tests/adn_reversion.sh).
--
-- Un borrado suave deja la iglesia en `suspendida` (la base ya le corta el acceso a sus datos de negocio),
-- fija `borrado_programado_en` a 30 dias y guarda en `adn_estado_previo` la etapa y la prueba que tenia, para
-- poder devolverla tal cual. Pasado el plazo ya no se puede recuperar y la purga la borra por completo.

-- 1. Marcas del borrado suave en la iglesia
alter table public.iglesias
  add column adn_borrada_en timestamptz,
  add column adn_borrada_por uuid,
  add column adn_estado_previo jsonb,
  add constraint adn_iglesias_borrada_check
    check (adn_borrada_en is null or (etapa in ('receso', 'suspendida') and borrado_programado_en is not null));

-- Si la iglesia sale de receso o suspension por cualquier via, las marcas se limpian solas. El nombre empieza por zz
-- para que corra despues de iglesias_sincronizar_etapa, que es quien puede cambiar la etapa.
create or replace function private.adn_coherencia_borrado()
returns trigger language plpgsql set search_path to '' as $$
begin
  if new.etapa not in ('receso', 'suspendida') then
    new.adn_borrada_en := null;
    new.adn_borrada_por := null;
    new.adn_estado_previo := null;
  end if;
  return new;
end $$;
revoke all on function private.adn_coherencia_borrado() from public, anon, authenticated, service_role;

create trigger iglesias_zz_adn_coherencia
  before insert or update on public.iglesias
  for each row execute function private.adn_coherencia_borrado();

-- Las marcas solo las cambia la plataforma, igual que la etapa y el borrado programado
create or replace function private.guardar_iglesia()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.plan is distinct from old.plan or new.activa is distinct from old.activa
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo
     or new.iglesia_madre_id is distinct from old.iglesia_madre_id or new.red_acceso is distinct from old.red_acceso
     or new.etapa is distinct from old.etapa or new.etapa_desde is distinct from old.etapa_desde
     or new.prueba_hasta is distinct from old.prueba_hasta
     or new.borrado_programado_en is distinct from old.borrado_programado_en
     or new.adn_borrada_en is distinct from old.adn_borrada_en
     or new.adn_borrada_por is distinct from old.adn_borrada_por
     or new.adn_estado_previo is distinct from old.adn_estado_previo then
    raise exception 'El plan, el estado, la etapa, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$$;

-- 2. Auditoria del ciclo de vida. Sin clave foranea a iglesias a proposito: debe sobrevivir a la purga.
--    No guarda datos de personas: solo la referencia de la iglesia, quien actuo, la fecha y conteos.
--    El motivo es texto libre de quien opera la plataforma: se anula al purgar por si contuviera algo personal.
create table public.adn_ciclo_auditoria (
  id bigint generated always as identity primary key,
  iglesia_ref uuid not null,
  accion text not null check (accion in ('borrado_suave', 'recuperacion', 'purga', 'purga_externa')),
  actor uuid,
  motivo text check (motivo is null or length(motivo) <= 500),
  detalle jsonb not null default '{}'::jsonb,
  ocurrido_en timestamptz not null default now()
);
create index adn_ciclo_auditoria_iglesia_idx on public.adn_ciclo_auditoria (iglesia_ref, ocurrido_en desc);

alter table public.adn_ciclo_auditoria enable row level security;  -- sin politicas: solo service_role
revoke all on public.adn_ciclo_auditoria from public, anon, authenticated;
revoke all on sequence public.adn_ciclo_auditoria_id_seq from public, anon, authenticated;
-- Solo se agrega y solo se puede anular el motivo: nada se edita ni se borra
grant select, insert on public.adn_ciclo_auditoria to service_role;
grant update (motivo) on public.adn_ciclo_auditoria to service_role;
grant usage, select on sequence public.adn_ciclo_auditoria_id_seq to service_role;

-- 3. Funciones. Las ejecuta solo service_role, desde la funcion de borde `plataforma`, que valida a quien llama.
create or replace function public.adn_auditar_ciclo(p_iglesia uuid, p_accion text, p_actor uuid, p_motivo text default null, p_detalle jsonb default '{}'::jsonb)
returns void language sql set search_path to '' as $$
  insert into public.adn_ciclo_auditoria (iglesia_ref, accion, actor, motivo, detalle)
  values (p_iglesia, p_accion, p_actor, p_motivo, coalesce(p_detalle, '{}'::jsonb))
$$;

-- Borrado suave: suspende la iglesia y fija el plazo de gracia de 30 dias. Devuelve la fecha de la purga.
create or replace function public.adn_borrar_suave(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns timestamptz language plpgsql set search_path to '' as $$
declare
  v record;
  limite timestamptz := now() + interval '30 days';
begin
  select etapa, prueba_hasta, adn_borrada_en into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.adn_borrada_en is not null then raise exception 'ADN_YA_BORRADA'; end if;
  update public.iglesias set
    adn_borrada_en = now(), adn_borrada_por = p_actor,
    adn_estado_previo = jsonb_build_object('etapa', v.etapa, 'prueba_hasta', v.prueba_hasta),
    etapa = 'suspendida', borrado_programado_en = limite
  where id = p_iglesia;
  perform public.adn_auditar_ciclo(p_iglesia, 'borrado_suave', p_actor, p_motivo,
    jsonb_build_object('plazo_dias', 30, 'etapa_previa', v.etapa, 'purga_el', limite));
  return limite;
end $$;

-- Recuperacion: solo dentro del plazo. Devuelve la iglesia a la etapa que tenia, con su prueba, y cancela la purga.
create or replace function public.adn_recuperar_iglesia(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns text language plpgsql set search_path to '' as $$
declare
  v record;
  destino text;
  prueba timestamptz;
begin
  select adn_borrada_en, borrado_programado_en, adn_estado_previo into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.adn_borrada_en is null then raise exception 'ADN_NO_BORRADA'; end if;
  if v.borrado_programado_en <= now() then raise exception 'ADN_PLAZO_VENCIDO'; end if;
  destino := coalesce(v.adn_estado_previo ->> 'etapa', 'activa');
  prueba := nullif(v.adn_estado_previo ->> 'prueba_hasta', '')::timestamptz;
  update public.iglesias set
    etapa = destino,
    prueba_hasta = case when destino = 'prueba' then prueba else null end,
    borrado_programado_en = null, adn_borrada_en = null, adn_borrada_por = null, adn_estado_previo = null
  where id = p_iglesia;
  perform public.adn_auditar_ciclo(p_iglesia, 'recuperacion', p_actor, p_motivo, jsonb_build_object('etapa_restaurada', destino));
  return destino;
end $$;

-- Iglesias en borrado suave cuyo plazo ya vencio, las mas antiguas primero
create or replace function public.adn_iglesias_vencidas()
returns setof uuid language sql stable set search_path to '' as $$
  select id from public.iglesias
  where adn_borrada_en is not null and borrado_programado_en <= now()
  order by borrado_programado_en
$$;

-- Purga de una iglesia vencida: borra sus filas (en cascada) y devuelve los usuarios de acceso que la funcion de
-- borde debe retirar de Auth. Deja en la auditoria solo conteos, sin datos de personas, y anula los motivos.
create or replace function public.adn_purgar_iglesia(p_iglesia uuid, p_actor uuid)
returns uuid[] language plpgsql set search_path to '' as $$
declare
  v record;
  miembros bigint;
  usuarios uuid[];
begin
  select adn_borrada_en, borrado_programado_en into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.adn_borrada_en is null then raise exception 'ADN_NO_BORRADA'; end if;
  if v.borrado_programado_en > now() then raise exception 'BORRADO_NO_VENCIDO' using errcode = 'check_violation'; end if;
  select count(*) into miembros from public.miembros where iglesia_id = p_iglesia;
  usuarios := public.borrar_iglesia(p_iglesia);
  update public.adn_ciclo_auditoria set motivo = null where iglesia_ref = p_iglesia;
  perform public.adn_auditar_ciclo(p_iglesia, 'purga', p_actor, null,
    jsonb_build_object('miembros_borrados', miembros, 'usuarios_a_retirar', coalesce(array_length(usuarios, 1), 0)));
  return usuarios;
end $$;

revoke all on function
  public.adn_auditar_ciclo(uuid, text, uuid, text, jsonb), public.adn_borrar_suave(uuid, uuid, text),
  public.adn_recuperar_iglesia(uuid, uuid, text), public.adn_iglesias_vencidas(), public.adn_purgar_iglesia(uuid, uuid)
  from public, anon, authenticated;
grant execute on function
  public.adn_auditar_ciclo(uuid, text, uuid, text, jsonb), public.adn_borrar_suave(uuid, uuid, text),
  public.adn_recuperar_iglesia(uuid, uuid, text), public.adn_iglesias_vencidas(), public.adn_purgar_iglesia(uuid, uuid)
  to service_role;
-- ===== 20261111130000_adn_exportacion (origen sha256 b75eb4ca2ece, compilado sha256 ff60c8dfc1e9) =====
-- Exportacion completa de una iglesia en formato universal: JSON y un CSV por tabla, con manifiesto de cifras.
-- Reversion: supabase/reversiones/20261111130000_adn_exportacion.down.sql. No modifica exportar_iglesia.
--
-- adn_exportar_paquete devuelve, para una iglesia:
--   formato, exportado_en, iglesia, tablas   -> igual que exportar_iglesia (superconjunto, mismas claves)
--   manifiesto                               -> por tabla: filas, columnas con tipo, columnas omitidas, orden de carga,
--                                               huella (md5 del contenido) y md5 del CSV
--   csv                                      -> un CSV por tabla (RFC 4180, UTF-8, CRLF; NULL = campo vacio sin comillas,
--                                               cadena vacia = "")
-- El CSV se genera aqui, no en el navegador, para conservar exactamente la escala de los numericos y los tipos.
-- Nunca salen los secretos (token, token_hash, ip_hash) ni las marcas internas de borrado suave (adn_*).
-- adn_verificar_carga recalcula esas cifras en la base donde se cargo la exportacion y las compara con el manifiesto.

-- Un campo CSV a partir de un valor JSON
create or replace function public.adn_csv_campo(p_valor jsonb)
returns text language sql immutable set search_path to '' as $$
  select case
    when p_valor is null or jsonb_typeof(p_valor) = 'null' then ''
    else (
      select case when t = '' or t ~ '["\r\n,]' or t ~ '^\s|\s$' then '"' || replace(t, '"', '""') || '"' else t end
      from (select case jsonb_typeof(p_valor) when 'string' then p_valor #>> '{}' else p_valor::text end as t) x
    )
  end
$$;

-- La fila tal como sale en la exportacion: sin las columnas omitidas y sin secretos anidados en `detalle`.
-- La usan la exportacion y la verificacion, para que las huellas se calculen igual.
create or replace function public.adn_fila_exportable(p_fila jsonb, p_omitidas text[])
returns jsonb language sql immutable set search_path to '' as $$
  select case
    when jsonb_typeof(p_fila -> 'detalle') = 'object'
      then jsonb_set(p_fila - p_omitidas, '{detalle}', (p_fila -> 'detalle') - array['token', 'token_hash', 'ip_hash'])
    else p_fila - p_omitidas
  end
$$;

-- Tablas que entran en la exportacion y como se filtran por iglesia ($1 es el id de la iglesia):
-- la propia iglesia, toda tabla con iglesia_id y rol_permisos (que cuelga de roles)
create or replace function public.adn_tablas_exportables()
returns table (nombre text, filtro text) language sql stable set search_path to '' as $$
  select 'iglesias'::text, 'id = $1'::text
  union all
  select c.relname::text, 'iglesia_id = $1'
  from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
    -- La auditoria de la plataforma son acciones internas y puede llevar notas de administracion: no sale en la exportacion de la iglesia
    and c.relname not in ('plataforma_auditoria', 'adn_bajas_enlaces', 'adn_confirmaciones')
    -- (adn_bajas_enlaces y adn_confirmaciones: secretos efimeros de un solo uso, sin valor fuera de la base)
    and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
  union all
  select 'rol_permisos', 'rol_id in (select id from public.roles where iglesia_id = $1)'
$$;
$cuerpo$;
end $tramo$;
select 'ok: tramo 1 de 15 aplicado' as resultado, (to_regprocedure('public.adn_tablas_exportables()') is not null) as comprobado;
