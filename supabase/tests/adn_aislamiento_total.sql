-- Aislamiento entre iglesias con dos usuarios de prueba, sobre TODAS las tablas con iglesia_id y sobre las funciones
-- que operan con datos. Se ejecuta dentro de tests/exportacion/origen.sql (variable despues), que deja sembradas dos
-- iglesias: A con filas en casi todas las tablas y B con unas pocas, y los usuarios:
--   A, propietaria de la iglesia A (ea000000-...-01)    B, propietaria de la iglesia B (ea000000-...-03)
-- Todo ocurre dentro de la transaccion de origen.sql y se deshace al final.
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text) to authenticated, anon;

-- Una sentencia debe fallar con uno de los codigos SQLSTATE indicados (por ejemplo 42501: sin permiso o fila bloqueada
-- por la politica; 23503: clave foranea compuesta)
create or replace function pg_temp.falla(sentencia text, codigos text, msg text) returns void language plpgsql as $$
begin
  begin
    execute sentencia;
  exception when others then
    if position(sqlstate in codigos) = 0 then raise exception 'FALLO: % (fallo con % y se esperaba %: %)', msg, sqlstate, codigos, sqlerrm; end if;
    raise notice 'OK: % (%)', msg, sqlstate;
    return;
  end;
  raise exception 'FALLO: % (la sentencia se ejecuto)', msg;
end $$;
grant execute on function pg_temp.falla(text, text, text) to authenticated, anon;

-- Filas de muestra de cada iglesia (como postgres, para poder intentar copiarlas despues)
create temp table muestra (tabla text, iglesia uuid, fila jsonb);
do $$
declare r record; ig uuid;
begin
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
      and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and not a.attisdropped)
  loop
    foreach ig in array array['ea100000-0000-0000-0000-00000000000a', 'ea100000-0000-0000-0000-00000000000b']::uuid[] loop
      execute format('insert into muestra select %L, %L, to_jsonb(t) from public.%I t where iglesia_id = %L limit 1', r.relname, ig, r.relname, ig);
    end loop;
  end loop;
end $$;
grant select on muestra to authenticated, anon;
select pg_temp.igual((select count(distinct tabla)::text from muestra where iglesia = 'ea100000-0000-0000-0000-00000000000a'),
  (select count(*)::text from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
     and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and not a.attisdropped)),
  'la iglesia A tiene filas en todas las tablas con iglesia_id (la prueba no deja tablas sin probar)');

-- Ataques de una usuaria contra todas las tablas. Devuelve cuantas tablas probo y cuantas le dejaron ver filas propias.
create or replace function pg_temp.atacar(p_propia uuid, p_otra uuid) returns jsonb language plpgsql as $$
declare r record; n bigint; antes bigint; despues bigint; insertada boolean; reasignadas int := 0; fila jsonb; tablas int := 0; con_propias int := 0; sin_acceso int := 0; propias jsonb := '{}'::jsonb; por_politica int := 0; por_otra text[] := '{}';
begin
  for r in
    select c.relname as t from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r'
      and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and not a.attisdropped)
    order by 1
  loop
    tablas := tablas + 1;
    -- 1. Lectura: ninguna fila de otra iglesia, con o sin filtro
    begin
      execute format('select count(*) from public.%I where iglesia_id <> %L', r.t, p_propia) into n;
      if n > 0 then raise exception 'FALLO: % filas de otra iglesia visibles en %', n, r.t; end if;
      execute format('select count(*) from public.%I where iglesia_id = %L', r.t, p_otra) into n;
      if n > 0 then raise exception 'FALLO: % filas de la iglesia objetivo visibles en %', n, r.t; end if;
      execute format('select count(*) from public.%I where iglesia_id = %L', r.t, p_propia) into n;
      propias := propias || jsonb_build_object(r.t, n);
      if n > 0 then con_propias := con_propias + 1; end if;
    exception when insufficient_privilege then sin_acceso := sin_acceso + 1;
    end;
    -- 2. Modificacion y borrado de filas ajenas: ninguna fila afectada
    begin
      execute format('update public.%I set iglesia_id = iglesia_id where iglesia_id = %L', r.t, p_otra);
      get diagnostics n = row_count;
      if n > 0 then raise exception 'FALLO: se modificaron % filas ajenas en %', n, r.t; end if;
    exception when insufficient_privilege then null;
    end;
    begin
      execute format('delete from public.%I where iglesia_id = %L', r.t, p_otra);
      get diagnostics n = row_count;
      if n > 0 then raise exception 'FALLO: se borraron % filas ajenas en %', n, r.t; end if;
    exception when insufficient_privilege then null;
    end;
    -- 3. Insercion de una copia de una fila ajena (con su iglesia_id): no puede quedar a nombre de la otra iglesia
    select m.fila into fila from muestra m where m.tabla = r.t and m.iglesia = p_otra;
    if fila is not null and not has_table_privilege(current_user, 'public.' || quote_ident(r.t), 'insert') then
      por_politica := por_politica + 1; -- sin permiso de insercion: ni siquiera llega a la politica
    elsif fila is not null then
      -- Clave primaria nueva: si no, una colision de clave podria ocultar una politica de insercion demasiado abierta
      if fila ->> 'id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then fila := jsonb_set(fila, '{id}', to_jsonb(gen_random_uuid()::text));
      elsif fila ? 'id' then fila := fila - 'id';
      end if;
      insertada := false; antes := null; despues := null;
      begin
        begin execute format('select count(*) from public.%I where iglesia_id = %L', r.t, p_propia) into antes;
        exception when insufficient_privilege then antes := null; end;
        -- Sin RETURNING: devolver la fila exigiria poder leerla, y eso ocultaria una insercion a ciegas en la otra iglesia
        execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I, $1)', r.t, r.t) using fila;
        insertada := true;
        if antes is not null then execute format('select count(*) from public.%I where iglesia_id = %L', r.t, p_propia) into despues; end if;
        raise exception using errcode = 'ZZ999', message = 'deshacer';
      exception when sqlstate 'ZZ999' then null;
                when insufficient_privilege then por_politica := por_politica + 1;
                -- Rechazada por otra restriccion (clave unica, clave foranea, disparador): la politica no llego a probarse
                when others then por_otra := por_otra || (r.t || ':' || sqlstate);
      end;
      if insertada then
        -- Si la fila aparece como propia, un disparador la reasigno a la iglesia de quien inserta (no hay fuga); si no, quedo en la otra
        if antes is null or despues is distinct from antes + 1 then raise exception 'FALLO: se inserto en % una fila a nombre de la otra iglesia', r.t; end if;
        reasignadas := reasignadas + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object('tablas', tablas, 'con_propias', con_propias, 'sin_acceso', sin_acceso, 'propias', propias, 'insert_por_politica', por_politica, 'insert_por_otra', to_jsonb(por_otra), 'insert_reasignadas', reasignadas);
end $$;
grant execute on function pg_temp.atacar(uuid, uuid) to authenticated;

-- ============ Usuaria A ataca a B, y usuaria B ataca a A ============
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table res_a on commit drop as select pg_temp.atacar('ea100000-0000-0000-0000-00000000000a', 'ea100000-0000-0000-0000-00000000000b') j;
reset role;
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);
set local role authenticated;
create temp table res_b on commit drop as select pg_temp.atacar('ea100000-0000-0000-0000-00000000000b', 'ea100000-0000-0000-0000-00000000000a') j;
reset role;
select set_config('request.jwt.claim.sub', '', true);

select pg_temp.igual((select (j->>'tablas')::int >= 25 from res_a)::text, 'true', 'A ataco al menos 25 tablas');
select pg_temp.igual((select (j->'propias'->>'miembros')::int > 0 and (j->'propias'->>'casas_oracion')::int > 0 and (j->'propias'->>'roles')::int > 0 from res_a)::text, 'true',
  'control positivo: A si ve sus propios miembros, casas y roles (el aislamiento no es una negacion general)');
select pg_temp.igual((select (j->>'con_propias')::int >= 15 from res_a)::text, 'true', 'control positivo: A ve filas propias en al menos 15 tablas');
select pg_temp.igual((select (j->'propias'->>'miembros')::int from res_b)::text, '1', 'control positivo: B ve sus propios miembros y solo los suyos');
select pg_temp.igual((select (j->'propias'->>'zonas')::int from res_b)::text, '1', 'control positivo: B ve su propia zona');
select pg_temp.igual((select (j->>'tablas')::int from res_b)::text, (select (j->>'tablas')::int from res_a)::text, 'A y B atacan las mismas tablas');
select pg_temp.igual((select (j->'insert_por_otra')::text from res_a), '[]', 'toda insercion de A a nombre de B la rechazo la politica o el permiso, no otra restriccion que la tapara');
select pg_temp.igual((select (j->'insert_por_otra')::text from res_b), '[]', 'toda insercion de B a nombre de A la rechazo la politica o el permiso, no otra restriccion que la tapara');
do $$
declare a jsonb; b jsonb; t text;
begin
  select j into a from res_a; select j into b from res_b;
  raise notice 'INFO: A ve filas propias en % tablas (sin acceso a %); B en % tablas (sin acceso a %)',
    a->>'con_propias', a->>'sin_acceso', b->>'con_propias', b->>'sin_acceso';
  raise notice 'INFO: insertar una fila a nombre de la otra iglesia lo rechazo la politica o el permiso en % tablas (A) y % (B); otra restriccion en: A %, B %',
    a->>'insert_por_politica', b->>'insert_por_politica', a->'insert_por_otra', b->'insert_por_otra';
end $$;
-- Los datos de A y B siguen intactos tras todos los ataques (como postgres)
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ea100000-0000-0000-0000-00000000000a'), '4', 'los miembros de A siguen intactos tras los ataques');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ea100000-0000-0000-0000-00000000000b'), '1', 'los miembros de B siguen intactos tras los ataques');

-- ============ Sin sesion y sin iglesia ============
set local role anon;
do $$
declare r record; n bigint; probadas int := 0;
begin
  for r in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' loop
    begin
      execute format('select count(*) from public.%I', r.relname) into n;
      if n > 0 then raise exception 'FALLO: anon lee % filas de %', n, r.relname; end if;
    exception when insufficient_privilege then null;
    end;
    probadas := probadas + 1;
  end loop;
  raise notice 'OK: anon no lee ninguna fila de ninguna de las % tablas', probadas;
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-0000000000ff', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.miembros), '0', 'un usuario autenticado sin iglesia no ve ningun miembro');
select pg_temp.igual((select count(*)::text from public.iglesias), '0', 'un usuario autenticado sin iglesia no ve ninguna iglesia');
select pg_temp.falla($$select public.adn_vista_previa_envio('email', 'todos')$$, 'P0001', 'sin iglesia no se puede calcular un envio');
select pg_temp.falla($$select public.adn_importar_miembros('[{"nombre":"X","apellido":"Y","email":"x@x.test"}]'::jsonb, 'prueba')$$, 'P0001 42501', 'sin iglesia no se puede importar');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ============ Funciones: ninguna cruza iglesias ============
select pg_temp.igual((select coalesce(string_agg(p.proname, ',' order by p.proname), '') from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (pg_get_function_identity_arguments(p.oid) ilike '%iglesia%' or p.proname ilike '%iglesia%')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
  '', 'ninguna funcion que recibe una iglesia es ejecutable por usuarios ni por anon');

-- B pide cifras, informes y vista previa: solo ve lo suyo
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);
set local role authenticated;
create temp table sal_b on commit drop as select
  public.adn_panel_inicio() panel,
  (select coalesce(jsonb_agg(to_jsonb(x)), '[]')::text from public.adn_informe_miembros() x) miembros,
  public.adn_informe_miembros_resumen()::text resumen,
  public.adn_informe_asistencia('2026-01-01', '2026-12-31')::text asistencia,
  (select coalesce(jsonb_agg(to_jsonb(x)), '[]')::text from public.adn_informe_crecimiento(12) x) crecimiento,
  public.adn_vista_previa_envio('email', 'todos') vista;
reset role;
select pg_temp.igual((select (panel->'miembros'->>'activos') from sal_b), '1', 'B ve en su panel solo su miembro activo');
select pg_temp.igual((select jsonb_array_length(panel->'eventos_proximos')::text from sal_b), '0', 'B no ve los eventos de A en su panel');
select pg_temp.igual((select (panel->'formacion'->>'en_curso') from sal_b), '0', 'B no ve la formacion de A en su panel');
select pg_temp.igual((select (panel->'comunicacion'->>'mensajes_30d') from sal_b), '0', 'B no ve los mensajes de A en su panel');
select pg_temp.igual((select (miembros || resumen || asistencia || crecimiento || panel::text) ~ '(Zoë|María|Espacios|O''Brien|zoe@prueba|Casa de Oración 1)' from sal_b)::text, 'false', 'los informes y el panel de B no contienen ningun dato de A');
select pg_temp.igual((select miembros ~ 'OTRA-IGLESIA-SECRETO' from sal_b)::text, 'true', 'control positivo: el informe de B si contiene los datos de B');
select pg_temp.igual((select (vista->>'recibiran') from sal_b), '1', 'la vista previa de envio de B cuenta solo a B');

-- A hace lo mismo y no ve los datos de B
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table sal_a on commit drop as select
  public.adn_panel_inicio() panel,
  (select coalesce(jsonb_agg(to_jsonb(x)), '[]')::text from public.adn_informe_miembros() x) miembros,
  public.adn_informe_miembros_resumen()::text resumen,
  public.adn_informe_asistencia('2026-01-01', '2026-12-31')::text asistencia,
  (select coalesce(jsonb_agg(to_jsonb(x)), '[]')::text from public.adn_informe_crecimiento(12) x) crecimiento;
reset role;
select pg_temp.igual((select (miembros || resumen || asistencia || crecimiento || panel::text) ~ 'OTRA-IGLESIA-SECRETO' from sal_a)::text, 'false', 'los informes y el panel de A no contienen ningun dato de B');
select pg_temp.igual((select miembros ~ 'Zoë' from sal_a)::text, 'true', 'control positivo: el informe de A si contiene los datos de A');

-- ============ Envio: los destinatarios son solo de la iglesia que envia ============
set local role authenticated;
select public.adn_enviar_mensaje('ea900000-0000-0000-0000-000000000001', 'email', 'todos', 'Aviso', 'Hola {{nombre}}', 'lunes');
reset role;
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios d join public.adn_mensajes m on m.id = d.mensaje_id
   where m.clave = 'ea900000-0000-0000-0000-000000000001' and d.iglesia_id <> m.iglesia_id), '0', 'el envio de A no registra destinatarios de otra iglesia');
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios d join public.adn_mensajes m on m.id = d.mensaje_id
   where m.clave = 'ea900000-0000-0000-0000-000000000001' and (d.destino ilike '%otra-secreto%' or d.texto_final ilike '%OTRA-IGLESIA%')), '0', 'el buzon de A no contiene correos ni textos de B');
select pg_temp.igual((select count(*)::text from public.adn_mensaje_destinatarios d join public.adn_mensajes m on m.id = d.mensaje_id
   where m.clave = 'ea900000-0000-0000-0000-000000000001' and d.estado = 'enviado'), '1', 'control positivo: el envio de A llego a su unico miembro con correo valido');

-- Una baja de A no afecta a B, aunque compartan la direccion
insert into public.adn_comunicacion_bajas (iglesia_id, miembro_id, canal) values ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000001', 'email');
update public.miembros set email = 'otra-secreto@prueba.test' where id = 'ea400000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((public.adn_vista_previa_envio('email', 'todos')->>'recibiran'), '1', 'la baja de una direccion en A no deja sin correo a B, que comparte esa direccion');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ============ Importacion: deduplicar por correo no cruza iglesias ============
-- (se restaura el correo de la prueba anterior: si no, A tendria de verdad ese correo duplicado)
update public.miembros set email = 'zoe@prueba.test' where id = 'ea400000-0000-0000-0000-000000000001';
select pg_temp.igual((select nombre from public.miembros where id = 'ea400000-0000-0000-0000-000000000009'), 'OTRA-IGLESIA-SECRETO', 'antes de importar, el miembro de B tiene su nombre');
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select public.adn_importar_miembros('[{"nombre": "Intruso", "apellido": "Importado", "email": "otra-secreto@prueba.test"}]'::jsonb, 'prueba');
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select nombre from public.miembros where id = 'ea400000-0000-0000-0000-000000000009'), 'OTRA-IGLESIA-SECRETO',
  'importar en A un correo que ya tiene un miembro de B no modifica al miembro de B');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ea100000-0000-0000-0000-00000000000a' and nombre = 'Intruso'), '1',
  'importar en A un correo que existe solo en B crea un miembro nuevo en A');
select pg_temp.igual((select count(*)::text from public.miembros where iglesia_id = 'ea100000-0000-0000-0000-00000000000b'), '1', 'la importacion de A no anade ni quita miembros a B');

-- ============ Referencias cruzadas con claves foraneas compuestas ============
select set_config('request.jwt.claim.sub', 'ea000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.falla($$insert into public.miembros (iglesia_id, nombre, apellido, casa_oracion_id) values ('ea100000-0000-0000-0000-00000000000a', 'X', 'Y', 'ea300000-0000-0000-0000-000000000002')$$,
  '23503 42501', 'A no puede crear un miembro asignado a una casa de B');
select pg_temp.falla($$update public.miembros set casa_oracion_id = 'ea300000-0000-0000-0000-000000000002' where id = 'ea400000-0000-0000-0000-000000000001'$$,
  '23503 42501', 'A no puede asignar su miembro a una casa de B');
select pg_temp.falla($$insert into public.adn_miembro_contactos (iglesia_id, miembro_id, tipo, valor, orden) values ('ea100000-0000-0000-0000-00000000000a', 'ea400000-0000-0000-0000-000000000009', 'correo', 'x@x.test', 1)$$,
  '23503 42501', 'A no puede colgar un contacto de un miembro de B');
select pg_temp.falla($$update public.casas_oracion set zona_id = 'ea200000-0000-0000-0000-000000000002' where id = 'ea300000-0000-0000-0000-000000000001'$$,
  '23503 42501', 'A no puede mover su casa a una zona de B');
reset role;
select set_config('request.jwt.claim.sub', '', true);
