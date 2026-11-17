-- Vive ADN, traspaso al proyecto real, archivo 11 de 19: tramo 10 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('public.adn_envio_liberar(text,uuid)') is not null then raise notice 'Tramo 10 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('public.adn_exportar_plan(uuid)') is not null) then raise exception 'Falta aplicar antes el tramo 9 de 15: no se sigue.'; end if;
  execute $cuerpo$


create or replace function public.adn_exportar_pagina(p_iglesia uuid, p_tabla text, p_formato text, p_despues jsonb default null, p_limite integer default 1000)
returns jsonb language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  filtro text;
  nombres text[]; omitidas text[]; pk text[]; tipos text[];
  lim integer;
  condicion text := '';
  orden text; claves text;
  res record;
begin
  if p_formato is null or p_formato not in ('json', 'csv') then raise exception 'ADN_FORMATO_INVALIDO'; end if;
  select x.filtro into filtro from public.adn_tablas_exportables() x where x.nombre = p_tabla;
  if filtro is null then raise exception 'ADN_TABLA_NO_EXPORTABLE'; end if;
  if not exists (select 1 from public.iglesias where id = p_iglesia) then raise exception 'La iglesia no existe'; end if;
  lim := least(greatest(coalesce(p_limite, 1000), 1), 5000);

  select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text <> all (public.adn_exportar_secretos())), '{}'),
         coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text = any (public.adn_exportar_secretos())), '{}')
    into nombres, omitidas
    from pg_attribute a
    where a.attrelid = ('public.' || quote_ident(p_tabla))::regclass and a.attnum > 0 and not a.attisdropped;
  select array_agg(a.attname::text order by k.ord), array_agg(format_type(a.atttypid, a.atttypmod) order by k.ord) into pk, tipos
    from pg_index i
    cross join lateral unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
    join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
    where i.indrelid = ('public.' || quote_ident(p_tabla))::regclass and i.indisprimary;
  if pk is null then raise exception 'ADN_SIN_CLAVE'; end if;

  orden := (select string_agg(format('t.%I', c), ', ' order by ord) from unnest(pk) with ordinality u(c, ord));
  claves := (select string_agg(format('t.%I::text', c), ', ' order by ord) from unnest(pk) with ordinality u(c, ord));
  if p_despues is not null then
    if jsonb_typeof(p_despues) <> 'array' or jsonb_array_length(p_despues) <> cardinality(pk)
       or exists (select 1 from jsonb_array_elements(p_despues) e where jsonb_typeof(e) <> 'string') then
      raise exception 'ADN_CURSOR_INVALIDO';
    end if;
    condicion := format(' and (%s) > (%s)', orden,
      (select string_agg(format('%L::%s', p_despues ->> (ord - 1)::integer, tipos[ord]), ', ' order by ord) from generate_series(1, cardinality(pk)) ord));
  end if;

  execute format($q$
    with pag as (
      select public.adn_fila_exportable(to_jsonb(t), $2) as f,
             to_jsonb(array[%s]) as clave,
             row_number() over (order by %s) as rn
      from public.%I t where %s %s
      order by %s
      limit $3 + 1
    )
    select count(*) filter (where rn <= $3) as n,
           bool_or(rn > $3) as hay_mas,
           case when $5 = 'json'
             then '[' || coalesce(string_agg(f::text, ',' order by rn) filter (where rn <= $3), '') || ']' end as json,
           case when $5 = 'csv'
             then coalesce(string_agg(
                    (select string_agg(public.adn_csv_campo(f -> c.n), ',' order by c.ord) from unnest($4::text[]) with ordinality c(n, ord)),
                    E'\r\n' order by rn) filter (where rn <= $3) || E'\r\n', '') end as csv,
           case when $5 = 'json' then coalesce(jsonb_agg(md5(f::text) order by rn) filter (where rn <= $3), '[]'::jsonb) end as hashes,
           (jsonb_agg(clave order by rn) filter (where rn <= $3)) -> -1 as ultima
    from pag
  $q$, claves, orden, p_tabla, filtro, condicion, orden)
    into res using p_iglesia, omitidas, lim, nombres, p_formato;

  return jsonb_strip_nulls(jsonb_build_object(
    'n', res.n, 'json', res.json, 'csv', res.csv, 'hashes', res.hashes,
    'siguiente', case when coalesce(res.hay_mas, false) then res.ultima end));
end $$;

revoke all on function
  public.adn_exportar_secretos(), public.adn_exportar_orden(), public.adn_exportar_plan(uuid), public.adn_exportar_pagina(uuid, text, text, jsonb, integer)
  from public, anon, authenticated;
grant execute on function
  public.adn_exportar_secretos(), public.adn_exportar_orden(), public.adn_exportar_plan(uuid), public.adn_exportar_pagina(uuid, text, text, jsonb, integer)
  to service_role;
-- ===== 20261111270000_adn_autoservicio_datos (origen sha256 099c92b1e67c, compilado sha256 f04b939ca61f) =====
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
-- ===== 20261111280000_adn_envios_topes (origen sha256 5aff7c7b9cb3, compilado sha256 4fb610250466) =====
-- Topes de envío de correo (docs/COSTE-ENVIO.md, aprobados por Gerencia). Un contador por día en la base: antes de enviar, la función
-- de borde reserva un envío; si algún tope está alcanzado, no se envía y se anota. Los topes los pasa quien llama (variables de la
-- función, con valores por defecto del plan gratuito), la base solo cuenta y decide de forma atómica.
--  * adn_envios_dia: una fila por día (UTC), tipo de correo e iglesia (la iglesia vacía usa un identificador de ceros). Solo números.
--  * adn_envio_reservar(tipo, iglesia, tope_iglesia, tope_tipo, tope_global): devuelve 'ok' y suma uno, o el primer tope alcanzado:
--    'tope_global', 'tope_tipo' o 'tope_iglesia'. Se comprueba en ese orden para que, con el plan gratuito, el fallo sea limpio y no a medias.
--  * adn_envio_liberar(tipo, iglesia): devuelve la reserva si el proveedor no aceptó el correo (no gasta cupo).
--  * Solo las ejecuta el servidor.
-- Reversión: supabase/reversiones/20261111280000_adn_envios_topes.down.sql
create table public.adn_envios_dia (
  dia date not null,
  tipo text not null check (tipo in ('purga', 'baja', 'confirmacion')),
  iglesia_ref uuid not null default '00000000-0000-0000-0000-000000000000',
  n integer not null check (n >= 0),
  primary key (dia, tipo, iglesia_ref)
);
alter table public.adn_envios_dia enable row level security;  -- sin políticas: solo service_role
revoke all on public.adn_envios_dia from public, anon, authenticated;
grant select, insert, update on public.adn_envios_dia to service_role;

create or replace function public.adn_envio_reservar(p_tipo text, p_iglesia uuid, p_tope_iglesia integer, p_tope_tipo integer, p_tope_global integer)
returns text language plpgsql set search_path to '' as $$
declare
  hoy date := (now() at time zone 'utc')::date;
  clave uuid := coalesce(p_iglesia, '00000000-0000-0000-0000-000000000000');
  global_n integer;
  tipo_n integer;
  iglesia_n integer;
begin
  if p_tipo is null or p_tipo not in ('purga', 'baja', 'confirmacion') then raise exception 'ADN_TIPO_INVALIDO'; end if;
  if p_tope_global is null or p_tope_global < 0 or p_tope_tipo < 0 or p_tope_iglesia < 0 then raise exception 'ADN_TOPE_INVALIDO'; end if;
  perform pg_advisory_xact_lock(hashtextextended('adn_envios_dia', 0));
  select coalesce(sum(n), 0) into global_n from public.adn_envios_dia where dia = hoy;
  if global_n >= p_tope_global then return 'tope_global'; end if;
  select coalesce(sum(n), 0) into tipo_n from public.adn_envios_dia where dia = hoy and tipo = p_tipo;
  if p_tope_tipo is not null and tipo_n >= p_tope_tipo then return 'tope_tipo'; end if;
  select coalesce(n, 0) into iglesia_n from public.adn_envios_dia where dia = hoy and tipo = p_tipo and iglesia_ref = clave;
  iglesia_n := coalesce(iglesia_n, 0);
  if p_tope_iglesia is not null and p_iglesia is not null and iglesia_n >= p_tope_iglesia then return 'tope_iglesia'; end if;
  insert into public.adn_envios_dia (dia, tipo, iglesia_ref, n) values (hoy, p_tipo, clave, 1)
    on conflict (dia, tipo, iglesia_ref) do update set n = public.adn_envios_dia.n + 1;
  return 'ok';
end $$;

create or replace function public.adn_envio_liberar(p_tipo text, p_iglesia uuid)
returns void language sql set search_path to '' as $$
  update public.adn_envios_dia set n = n - 1
  where dia = (now() at time zone 'utc')::date and tipo = p_tipo
    and iglesia_ref = coalesce(p_iglesia, '00000000-0000-0000-0000-000000000000') and n > 0
$$;

revoke all on function public.adn_envio_reservar(text, uuid, integer, integer, integer), public.adn_envio_liberar(text, uuid) from public, anon, authenticated;
grant execute on function public.adn_envio_reservar(text, uuid, integer, integer, integer), public.adn_envio_liberar(text, uuid) to service_role;
$cuerpo$;
end $tramo$;
select 'ok: tramo 10 de 15 aplicado' as resultado, (to_regprocedure('public.adn_envio_liberar(text,uuid)') is not null) as comprobado;
