-- Vive ADN, traspaso al proyecto real, archivo 10 de 19: tramo 9 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('public.adn_exportar_plan(uuid)') is not null then raise notice 'Tramo 9 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regclass('public.adn_confirmaciones') is not null) then raise exception 'Falta aplicar antes el tramo 8 de 15: no se sigue.'; end if;
  execute $cuerpo$

create unique index adn_confirmaciones_activa_idx on public.adn_confirmaciones (miembro_id, canal) where estado in ('por_enviar', 'pendiente');
create index adn_confirmaciones_iglesia_idx on public.adn_confirmaciones (iglesia_id, estado);
alter table public.adn_confirmaciones enable row level security;
revoke all on public.adn_confirmaciones from public, anon, authenticated;
grant all on public.adn_confirmaciones to service_role;
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_tipo_check check (tipo in ('checkin', 'importacion', 'confirmacion'));
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_forma check (
  (tipo = 'checkin' and finalidad is not null and texto_version is not null)
  or (tipo = 'importacion' and canal is not null and texto_original is not null)
  or (tipo = 'confirmacion' and canal is not null));

create or replace function private.adn_doble_confirmacion_activa() returns boolean
language sql stable set search_path to '' as $$
  select coalesce((select valor = 'true'::jsonb from public.plataforma_ajustes where clave = 'adn_doble_confirmacion'), false)
$$;
revoke execute on function private.adn_doble_confirmacion_activa() from public, anon, authenticated;
grant execute on function private.adn_doble_confirmacion_activa() to service_role;

-- Prepara un lote de solicitudes por enviar: genera el secreto de cada una (una sola vez), guarda su huella y crea el enlace
-- de baja que acompañará al correo. Con el ajuste apagado no devuelve nada. Solo el servidor.
create or replace function public.adn_confirmacion_preparar(p_max integer default 50, p_dias integer default 3)
returns table (id uuid, destino text, idioma text, nombre text, iglesia text, token text, baja_token text, expira_en timestamptz)
language plpgsql set search_path to '' as $$
declare r record; v_token text; v_baja text; v_exp timestamptz;
begin
  if p_max is null or p_max not between 1 and 500 or p_dias is null or p_dias not between 1 and 14 then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if not private.adn_doble_confirmacion_activa() then return; end if;
  for r in
    select c.id as cid, c.iglesia_id, c.miembro_id, c.destino as cdestino, c.idioma as cidioma, m.nombre as mnombre, i.nombre as inombre
    from public.adn_confirmaciones c
    join public.miembros m on m.id = c.miembro_id and m.iglesia_id = c.iglesia_id
    join public.iglesias i on i.id = c.iglesia_id
    where c.estado = 'por_enviar' order by c.created_at limit p_max for update of c skip locked
  loop
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    v_baja := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    v_exp := now() + make_interval(days => p_dias);
    update public.adn_confirmaciones set estado = 'pendiente', token_hash = encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), expira_en = v_exp where adn_confirmaciones.id = r.cid;
    insert into public.adn_bajas_enlaces (iglesia_id, miembro_id, canal, token_hash, expira_en)
      values (r.iglesia_id, r.miembro_id, 'email', encode(sha256(convert_to(v_baja, 'UTF8')), 'hex'), v_exp + interval '365 days');
    id := r.cid; destino := r.cdestino; idioma := r.cidioma; nombre := r.mnombre; iglesia := r.inombre; token := v_token; baja_token := v_baja; expira_en := v_exp;
    return next;
  end loop;
end $$;
revoke all on function public.adn_confirmacion_preparar(integer, integer) from public, anon, authenticated;
grant execute on function public.adn_confirmacion_preparar(integer, integer) to service_role;

-- Si el envío falla, la solicitud vuelve a por_enviar (sin secreto) para reintentarla
create or replace function public.adn_confirmacion_fallida(p_id uuid) returns void
language sql set search_path to '' as $$
  update public.adn_confirmaciones set estado = 'por_enviar', token_hash = null, expira_en = null where id = p_id and estado = 'pendiente'
$$;
revoke all on function public.adn_confirmacion_fallida(uuid) from public, anon, authenticated;
grant execute on function public.adn_confirmacion_fallida(uuid) to service_role;

-- Consume el enlace de confirmación. Respuesta sin datos de la persona ni de la iglesia.
create or replace function public.adn_confirmacion_consumir(p_token text) returns jsonb
language plpgsql set search_path to '' as $$
declare c public.adn_confirmaciones; v_actual text; v_aplica boolean := false;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false, 'motivo', 'invalido'); end if;
  select * into c from public.adn_confirmaciones where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'invalido'); end if;
  if c.estado = 'confirmada' then return jsonb_build_object('ok', false, 'motivo', 'usado'); end if;
  if c.estado = 'caducada' or c.expira_en < now() then
    update public.adn_confirmaciones set estado = 'caducada' where id = c.id and estado = 'pendiente';
    return jsonb_build_object('ok', false, 'motivo', 'caducado');
  end if;
  update public.adn_confirmaciones set estado = 'confirmada', confirmada_en = now() where id = c.id;
  -- Solo concede si no hay registro o consta sin_dato: nunca deshace una baja ni un «nunca»
  select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = c.miembro_id and k.canal = c.canal;
  if v_actual is null or v_actual = 'sin_dato' then
    perform private.adn_escribir_consentimiento(c.iglesia_id, c.miembro_id, c.canal, 'suscrito', 'qr_confirmado', null);
    v_aplica := true;
  end if;
  insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, aplicado, origen)
    values (c.iglesia_id, c.miembro_id, 'confirmacion', c.canal, v_aplica, 'qr_confirmado');
  return jsonb_build_object('ok', true, 'canal', c.canal);
end $$;
revoke all on function public.adn_confirmacion_consumir(text) from public, anon, authenticated;
grant execute on function public.adn_confirmacion_consumir(text) to service_role;
-- ===== 20261111240000_adn_purga_estado (origen sha256 fba57547598a, compilado sha256 cbc05aaa58f5) =====
-- Estado de la purga programada, para vigilar que la tarea programada de borrado funciona.
--  * adn_purga_estado(p_horas) devuelve solo cifras (sin datos de personas ni de iglesias): cuántas iglesias están en borrado suave,
--    cuántas tienen el plazo vencido y esperan purga, cuántas horas lleva esperando la más atrasada y si ese retraso supera p_horas
--    (48 por defecto). Una purga sana deja las vencidas en cero a las pocas horas.
--  * Solo la ejecuta el servidor. Es de solo lectura: no purga nada. La purga sigue siendo la del ciclo de vida.
-- Reversión: supabase/reversiones/20261111240000_adn_purga_estado.down.sql
create or replace function public.adn_purga_estado(p_horas integer default 48)
returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object(
    'en_borrado', count(*) filter (where adn_borrada_en is not null),
    'vencidas', count(*) filter (where adn_borrada_en is not null and borrado_programado_en <= now()),
    'horas_mas_atrasada', coalesce(floor(max(extract(epoch from now() - borrado_programado_en)) filter (where adn_borrada_en is not null and borrado_programado_en <= now()) / 3600), 0)::int,
    'atrasada', coalesce(bool_or(adn_borrada_en is not null and borrado_programado_en <= now() - make_interval(hours => greatest(coalesce(p_horas, 48), 0))), false))
  from public.iglesias
$$;
revoke all on function public.adn_purga_estado(integer) from public, anon, authenticated;
grant execute on function public.adn_purga_estado(integer) to service_role;
-- ===== 20261111250000_adn_purgas_libro (origen sha256 c0a0e32b9dad, compilado sha256 d32f4dd18c61) =====
-- Libro externo de iglesias purgadas: la pieza de la base que lo hace posible.
-- El problema: restaurar una copia anterior a una purga devuelve los datos de una iglesia ya borrada, y la auditoría de la purga vive
-- en la misma base, así que se pierde con la restauración. El libro es una lista guardada FUERA de la base que dice qué iglesias se
-- purgaron y cuándo. Solo contiene identificadores y fechas: ningún dato de personas ni de iglesias.
--  * adn_purgas_desde(p_desde) exporta ese libro desde la auditoría: una fila por purga, con el identificador y la fecha. Con una fecha
--    devuelve solo lo posterior (o igual), para añadirlo al libro; sin fecha, todo. Es de solo lectura.
--  * adn_repurgar_registradas(p_ids, p_actor) se usa tras una restauración: toma los identificadores del libro y, de los que reaparecen en la
--    base restaurada, los vuelve a marcar como borrados con el plazo vencido. No borra nada por sí misma: la purga normal
--    (adn_iglesias_vencidas y adn_purgar_iglesia, desde la función de borde) las elimina por completo, con sus archivos y cuentas.
--    Las que ya no existen se ignoran. Devuelve los identificadores marcados.
--  * Solo las ejecuta el servidor.
-- Reversión: supabase/reversiones/20261111250000_adn_purgas_libro.down.sql
create or replace function public.adn_purgas_desde(p_desde timestamptz default null)
returns table (iglesia_ref uuid, purgada_en timestamptz) language sql stable set search_path to '' as $$
  select a.iglesia_ref, a.ocurrido_en
  from public.adn_ciclo_auditoria a
  where a.accion = 'purga' and (p_desde is null or a.ocurrido_en >= p_desde)
  order by a.ocurrido_en, a.id
$$;

create or replace function public.adn_repurgar_registradas(p_ids uuid[], p_actor uuid)
returns uuid[] language plpgsql set search_path to '' as $$
declare
  r record;
  marcadas uuid[] := '{}';
begin
  if p_ids is null or cardinality(p_ids) > 5000 then raise exception 'ADN_LISTA_INVALIDA'; end if;
  for r in select id from public.iglesias where id = any (p_ids) order by id for update loop
    update public.iglesias set
      adn_borrada_en = coalesce(adn_borrada_en, now()), adn_borrada_por = coalesce(adn_borrada_por, p_actor),
      etapa = 'suspendida', borrado_programado_en = now()
    where id = r.id;
    perform public.adn_auditar_ciclo(r.id, 'borrado_suave', p_actor, null, jsonb_build_object('origen', 'libro_externo'));
    marcadas := marcadas || r.id;
  end loop;
  return marcadas;
end $$;

revoke all on function public.adn_purgas_desde(timestamptz), public.adn_repurgar_registradas(uuid[], uuid) from public, anon, authenticated;
grant execute on function public.adn_purgas_desde(timestamptz), public.adn_repurgar_registradas(uuid[], uuid) to service_role;
-- ===== 20261111260000_adn_exportacion_paginada (origen sha256 6db9ef062dd7, compilado sha256 39bab7f00543) =====
-- Exportación completa por páginas: para iglesias grandes, donde un único JSON con todo el paquete (adn_exportar_paquete) supera los
-- límites de tamaño y de memoria. adn_exportar_paquete NO se modifica y sigue valiendo para iglesias pequeñas y como reserva.
-- Reversión: supabase/reversiones/20261111260000_adn_exportacion_paginada.down.sql
--
--  * adn_exportar_plan(iglesia): el esqueleto del manifiesto, sin leer filas: por tabla, orden de carga, columnas, omitidas, clave
--    primaria y número de filas. Las tablas, su orden y sus columnas se calculan igual que en adn_exportar_paquete.
--  * adn_exportar_pagina(iglesia, tabla, formato, despues, limite): una página de una tabla, ordenada por su clave primaria y paginada
--    con un cursor de esa clave (nunca con desplazamientos, que se encarecen con cada página). Devuelve, según el formato:
--      'json' -> las filas como un texto JSON ('[...]'), tal como salen en la exportación, y el md5 de cada fila
--      'csv'  -> las filas como CSV sin cabecera (RFC 4180, CRLF)
--    El texto viaja como cadena para conservar exactamente la escala de los numéricos. El md5 de cada fila es el mismo que usa
--    adn_verificar_carga, así que el cliente calcula la huella de la tabla (md5 de los md5 ordenados) sin que la base la lea entera.
--  * Una tabla fuera de adn_tablas_exportables se rechaza: la lista cerrada impide pedir cualquier otra.
--  * Solo las ejecuta el servidor.
create or replace function public.adn_exportar_secretos()
returns text[] language sql immutable set search_path to '' as $$
  -- Columnas que nunca salen: secretos y marcas internas del borrado suave (la misma lista que adn_exportar_paquete)
  select array['token', 'token_hash', 'ip_hash', 'adn_borrada_en', 'adn_borrada_por', 'adn_estado_previo']
$$;

-- Tablas exportables con su filtro y su orden de carga: una tabla va después de las que referencia (las autorreferencias no cuentan)
create or replace function public.adn_exportar_orden()
returns table (o_nombre text, o_filtro text, o_nivel integer) language sql stable set search_path to '' as $$
  with recursive tb as (select x.nombre, x.filtro from public.adn_tablas_exportables() x),
  fk as (
    select co.relname::text collate "default" as origen, cd.relname::text collate "default" as destino
    from pg_constraint c
    join pg_class co on co.oid = c.conrelid join pg_class cd on cd.oid = c.confrelid
    where c.contype = 'f' and c.connamespace = 'public'::regnamespace and c.conrelid <> c.confrelid
  ),
  niv(nombre, n) as (
    select nombre, 0 from tb
    union
    select fk.origen, niv.n + 1 from niv join fk on fk.destino = niv.nombre
    where fk.origen in (select nombre from tb) and niv.n < 50
  )
  select t.nombre, t.filtro, max(niv.n)::integer
  from tb t join niv on niv.nombre = t.nombre
  group by t.nombre, t.filtro
  order by max(niv.n), t.nombre
$$;

create or replace function public.adn_exportar_plan(p_iglesia uuid)
returns jsonb language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
declare
  r record;
  cols jsonb; omitidas text[]; pk text[]; n bigint;
  tablas jsonb := '[]'::jsonb;
  total bigint := 0;
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;
  for r in select * from public.adn_exportar_orden() loop
    select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text = any (public.adn_exportar_secretos())), '{}'),
           coalesce(jsonb_agg(jsonb_build_object('nombre', a.attname, 'tipo', format_type(a.atttypid, a.atttypmod), 'obligatoria', a.attnotnull)
                              order by a.attnum) filter (where a.attname::text <> all (public.adn_exportar_secretos())), '[]')
      into omitidas, cols
      from pg_attribute a
      where a.attrelid = ('public.' || quote_ident(r.o_nombre))::regclass and a.attnum > 0 and not a.attisdropped;
    select array_agg(a.attname::text order by k.ord) into pk
      from pg_index i
      cross join lateral unnest(i.indkey::int2[]) with ordinality k(attnum, ord)
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = k.attnum
      where i.indrelid = ('public.' || quote_ident(r.o_nombre))::regclass and i.indisprimary;
    execute format('select count(*) from public.%I t where %s', r.o_nombre, r.o_filtro) into n using p_iglesia;
    total := total + n;
    tablas := tablas || jsonb_build_array(jsonb_build_object(
      'nombre', r.o_nombre, 'orden_carga', r.o_nivel, 'archivo_csv', 'csv/' || r.o_nombre || '.csv',
      'filas', n, 'columnas', cols, 'omitidas', to_jsonb(omitidas), 'clave', to_jsonb(coalesce(pk, '{}'))));
  end loop;
  return jsonb_build_object('formato', 'viveadn-exportacion-2', 'iglesia_id', p_iglesia, 'exportado_en', now(), 'total_filas', total, 'tablas', tablas);
end $$;
$cuerpo$;
end $tramo$;
select 'ok: tramo 9 de 15 aplicado' as resultado, (to_regprocedure('public.adn_exportar_plan(uuid)') is not null) as comprobado;
