-- Exportación por páginas: se ejecuta dentro de la transacción de origen.sql (-v despues=exportacion/paginas.sql), con la iglesia sintética
-- que tiene filas en todas las tablas, claves compuestas incluidas. Comprueba el plan, las páginas con un cursor de clave primaria,
-- que las huellas son las de adn_exportar_paquete, los errores y los permisos.
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text) to authenticated, anon, service_role;
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm like '%' || texto || '%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm;
  end;
  raise exception 'FALLO: % (no falló)', msg;
end $$;
grant execute on function pg_temp.falla(text, text, text) to authenticated, anon, service_role;

create temp table paquete as select public.adn_exportar_paquete('ea100000-0000-0000-0000-00000000000a') as p;
create temp table plan as select public.adn_exportar_plan('ea100000-0000-0000-0000-00000000000a') as p;
create temp table paginas (tabla text, pagina int, n int, json_ text, csv text, hashes jsonb);
grant all on paquete, plan, paginas to public;

-- 1. El plan coincide con el manifiesto de adn_exportar_paquete en todo lo que no son las filas leídas
select pg_temp.igual((select jsonb_array_length(p -> 'tablas')::text from plan), (select jsonb_array_length(p -> 'manifiesto' -> 'tablas')::text from paquete), 'el plan lista las mismas tablas que el paquete');
select pg_temp.igual(
  (select md5(jsonb_agg(jsonb_build_object('n', t ->> 'nombre', 'o', t -> 'orden_carga', 'f', t -> 'filas', 'c', t -> 'columnas', 'u', t -> 'omitidas', 'a', t ->> 'archivo_csv') order by ord)::text)
     from plan, jsonb_array_elements(p -> 'tablas') with ordinality e(t, ord)),
  (select md5(jsonb_agg(jsonb_build_object('n', t ->> 'nombre', 'o', t -> 'orden_carga', 'f', t -> 'filas', 'c', t -> 'columnas', 'u', t -> 'omitidas', 'a', t ->> 'archivo_csv') order by ord)::text)
     from paquete, jsonb_array_elements(p -> 'manifiesto' -> 'tablas') with ordinality e(t, ord)),
  'nombre, orden de carga, filas, columnas, omitidas y archivo de cada tabla, en el mismo orden, son idénticos a los del paquete');
select pg_temp.igual((select (p ->> 'total_filas') from plan), (select (p -> 'manifiesto' ->> 'total_filas') from paquete), 'el total de filas coincide');
select pg_temp.igual((select count(*)::text from plan, jsonb_array_elements(p -> 'tablas') t where jsonb_array_length(t -> 'clave') = 0), '0', 'todas las tablas tienen clave primaria');
select pg_temp.igual((select (t -> 'clave')::text from plan, jsonb_array_elements(p -> 'tablas') t where t ->> 'nombre' = 'rol_permisos'), '["rol_id", "permiso"]', 'una clave compuesta sale completa y en orden');

-- 2. Se recorren todas las tablas con páginas de 2 filas, en los dos formatos
do $$
declare t record; despues jsonb; pag int; r jsonb; f text;
begin
  for t in select e ->> 'nombre' as nombre from plan, jsonb_array_elements(p -> 'tablas') e loop
    foreach f in array array['json', 'csv'] loop
      despues := null; pag := 0;
      loop
        pag := pag + 1;
        r := public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', t.nombre, f, despues, 2);
        insert into paginas values (t.nombre || ':' || f, pag, (r ->> 'n')::int, r ->> 'json', r ->> 'csv', r -> 'hashes');
        despues := r -> 'siguiente';
        exit when despues is null;
        if pag > 1000 then raise exception 'FALLO: la paginación no termina en %', t.nombre; end if;
      end loop;
    end loop;
  end loop;
end $$;

-- 3. Cada tabla se recorre completa, sin repetir ni perder filas, con huella idéntica a la del paquete
select pg_temp.igual(
  (select count(*)::text from (
    select e ->> 'nombre' as nombre, (e ->> 'filas')::int as filas,
           (select coalesce(sum(n), 0) from paginas where tabla = e ->> 'nombre' || ':json') as leidas
    from paquete, jsonb_array_elements(p -> 'manifiesto' -> 'tablas') e) x where filas <> leidas), '0',
  'la suma de las páginas de cada tabla es su número de filas');
select pg_temp.igual(
  (select count(*)::text from (
    select e ->> 'nombre' as nombre, e ->> 'huella' as huella,
           (select md5(coalesce(string_agg(h, ',' order by h), '')) from paginas pg, jsonb_array_elements_text(pg.hashes) h where pg.tabla = e ->> 'nombre' || ':json') as calculada
    from paquete, jsonb_array_elements(p -> 'manifiesto' -> 'tablas') e) x where huella <> calculada), '0',
  'la huella calculada con los md5 de las páginas es la del paquete en las 32 tablas');
select pg_temp.igual(
  (select count(*)::text from (
    select e ->> 'nombre' as nombre,
           (select count(distinct h) from paginas pg, jsonb_array_elements_text(pg.hashes) h where pg.tabla = e ->> 'nombre' || ':json') as distintas,
           (e ->> 'filas')::int as filas
    from paquete, jsonb_array_elements(p -> 'manifiesto' -> 'tablas') e where (e ->> 'nombre') <> 'rol_permisos') x where distintas <> filas), '0',
  'ninguna fila se repite entre páginas');
-- Las filas de las páginas son las del paquete (mismo contenido, otro orden)
select pg_temp.igual(
  (select count(*)::text from (
    select e ->> 'nombre' as nombre,
           (select md5(coalesce(jsonb_agg(r order by r::text), '[]'::jsonb)::text) from paginas pg, jsonb_array_elements(pg.json_::jsonb) r where pg.tabla = e ->> 'nombre' || ':json') as pag,
           (select md5(coalesce(jsonb_agg(r order by r::text), '[]'::jsonb)::text) from jsonb_array_elements(case e ->> 'nombre' when 'iglesias' then jsonb_build_array(p -> 'iglesia') else p -> 'tablas' -> (e ->> 'nombre') end) r) as paq
    from paquete, jsonb_array_elements(p -> 'manifiesto' -> 'tablas') e) x where pag <> paq), '0',
  'las filas de las páginas son las del paquete, tabla a tabla');
select pg_temp.igual((select count(*)::text from paginas where tabla like '%:json' and pagina > 1), (select count(*)::text from paginas where tabla like '%:csv' and pagina > 1), 'el recorrido en JSON y en CSV tiene las mismas páginas');
select pg_temp.igual((select (max(pagina) > 3)::text from paginas where tabla = 'rol_permisos:json'), 'true', 'la clave compuesta de rol_permisos se recorre en más de tres páginas, con el cursor de las dos columnas');
select pg_temp.igual((select (count(distinct tabla) >= 2)::text from paginas where tabla like '%:json' and pagina > 1), 'true', 'al menos dos tablas se recorren con más de una página');
-- El CSV de la tabla de una sola fila es exactamente el del paquete, sin la cabecera
select pg_temp.igual((select csv from paginas where tabla = 'iglesias:csv' and pagina = 1),
  (select substring(p -> 'csv' ->> 'iglesias' from position(E'\r\n' in p -> 'csv' ->> 'iglesias') + 2) from paquete), 'el CSV de una fila es el del paquete sin cabecera');
select pg_temp.igual((select count(*)::text from paginas where tabla like '%:csv' and csv <> '' and csv !~ '\r\n$'), '0', 'cada página de CSV termina en CRLF');
select pg_temp.igual((select count(*)::text from paginas where tabla like '%:json' and (json_ is null or csv is not null)), '0', 'en formato json solo viaja el JSON');
select pg_temp.igual((select count(*)::text from paginas where tabla like '%:csv' and (csv is null or json_ is not null or hashes is not null)), '0', 'en formato csv solo viaja el CSV');

-- 4. Secretos y otras iglesias no salen en ninguna página
select pg_temp.igual((select count(*)::text from paginas where coalesce(json_, '') || coalesce(csv, '') ~ 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb|cccccccccccccccccccccccccccccccc|dddddddddddddddddddddddddddddddd|OTRA-IGLESIA-SECRETO|otra-secreto@prueba|adn_borrada'), '0', 'ni los secretos, ni las marcas internas ni los datos de otra iglesia salen en las páginas');

-- 5. Cursor y límite
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', null, 0) ->> 'n'), '1', 'un límite de cero se sube a una fila');
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', null, -5) ->> 'n'), '1', 'un límite negativo también');
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', null, null) ->> 'n'), (select least(1000, (e ->> 'filas')::int)::text from plan, jsonb_array_elements(p -> 'tablas') e where e ->> 'nombre' = 'miembros'), 'sin límite se usa el de 1000 o todas las filas si hay menos');
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', null, 1000000) ->> 'n'), (select least(5000, (e ->> 'filas')::int)::text from plan, jsonb_array_elements(p -> 'tablas') e where e ->> 'nombre' = 'miembros'), 'un límite enorme se recorta a 5000');
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', jsonb_build_array('ffffffff-ffff-ffff-ffff-ffffffffffff'), 10) ->> 'n'), '0', 'un cursor posterior a la última clave da una página vacía');
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', jsonb_build_array('ffffffff-ffff-ffff-ffff-ffffffffffff'), 10) ->> 'json'), '[]', 'y su JSON es una lista vacía');
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'csv', jsonb_build_array('ffffffff-ffff-ffff-ffff-ffffffffffff'), 10) ->> 'csv'), '', 'y su CSV está vacío');
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', null, 5000) ? 'siguiente')::text, 'false', 'con todas las filas en una página no hay siguiente');

-- 6. Errores
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'plataforma_auditoria', 'json')$$, 'ADN_TABLA_NO_EXPORTABLE', 'una tabla interna no se exporta');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'adn_confirmaciones', 'json')$$, 'ADN_TABLA_NO_EXPORTABLE', 'ni los secretos efímeros');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros; drop table public.miembros', 'json')$$, 'ADN_TABLA_NO_EXPORTABLE', 'un nombre de tabla con una inyección se rechaza');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'pg_catalog.pg_class', 'json')$$, 'ADN_TABLA_NO_EXPORTABLE', 'ni una tabla de otro esquema');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'xml')$$, 'ADN_FORMATO_INVALIDO', 'un formato desconocido se rechaza');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', null)$$, 'ADN_FORMATO_INVALIDO', 'y uno nulo');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-0000000000ff', 'miembros', 'json')$$, 'La iglesia no existe', 'una iglesia inexistente se rechaza');
select pg_temp.falla($$select public.adn_exportar_plan('ea100000-0000-0000-0000-0000000000ff')$$, 'La iglesia no existe', 'también en el plan');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', '"x"'::jsonb)$$, 'ADN_CURSOR_INVALIDO', 'un cursor que no es una lista se rechaza');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', '["a","b"]'::jsonb)$$, 'ADN_CURSOR_INVALIDO', 'un cursor con más valores que la clave se rechaza');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'rol_permisos', 'json', '["ffffffff-ffff-ffff-ffff-ffffffffffff"]'::jsonb)$$, 'ADN_CURSOR_INVALIDO', 'un cursor con menos valores que una clave compuesta se rechaza');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', '[1]'::jsonb)$$, 'ADN_CURSOR_INVALIDO', 'un cursor con un valor que no es texto se rechaza');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', '["no es un uuid"]'::jsonb)$$, 'invalid input syntax', 'un cursor con un valor que no es de su tipo se rechaza');

-- 7. Solo el servidor
set local role authenticated;
select pg_temp.falla($$select public.adn_exportar_plan('ea100000-0000-0000-0000-00000000000a')$$, 'permission denied', 'una persona con sesión no lee el plan');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json')$$, 'permission denied', 'ni una página');
reset role;
set local role anon;
select pg_temp.falla($$select public.adn_exportar_plan('ea100000-0000-0000-0000-00000000000a')$$, 'permission denied', 'un visitante tampoco el plan');
select pg_temp.falla($$select public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json')$$, 'permission denied', 'ni una página');
reset role;
set local role service_role;
select pg_temp.igual((public.adn_exportar_pagina('ea100000-0000-0000-0000-00000000000a', 'miembros', 'json', null, 1) ->> 'n'), '1', 'el servidor sí');
reset role;
