-- Pruebas de la importacion de contactos: duplicados por correo, datos adicionales, claves, permisos,
-- modo alias, aislamiento entre iglesias, limite del plan y atomicidad.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then
    raise exception 'Este script no se ejecuta en una base con iglesias reales';
  end if;
end $$;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm like '%' || texto || '%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text) to authenticated, anon, service_role;

insert into auth.users (id) values
  ('ac000000-0000-0000-0000-000000000001'), ('ac000000-0000-0000-0000-000000000002'), ('ac000000-0000-0000-0000-000000000003'),
  ('ac000000-0000-0000-0000-000000000004'), ('ac000000-0000-0000-0000-000000000005');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ac100000-0000-0000-0000-00000000000a', 'Prueba Imp A', 'prueba-imp-a', 'ES', 'Sevilla', 'premium'),
  ('ac100000-0000-0000-0000-00000000000b', 'Prueba Imp B', 'prueba-imp-b', 'ES', 'Sevilla', 'premium'),
  ('ac100000-0000-0000-0000-00000000000c', 'Prueba Imp C', 'prueba-imp-c', 'ES', 'Sevilla', 'semilla'),
  ('ac100000-0000-0000-0000-00000000000d', 'Prueba Imp D', 'prueba-imp-d', 'ES', 'Sevilla', 'premium');
update public.iglesias set modo_alias = true where slug = 'prueba-imp-d';
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('ac000000-0000-0000-0000-000000000001', 'ac100000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@prueba.test', 'propietario', true),
  ('ac000000-0000-0000-0000-000000000002', 'ac100000-0000-0000-0000-00000000000a', 'Col', 'A', 'cola@prueba.test', 'colaborador', true),
  ('ac000000-0000-0000-0000-000000000003', 'ac100000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@prueba.test', 'propietario', true),
  ('ac000000-0000-0000-0000-000000000004', 'ac100000-0000-0000-0000-00000000000c', 'P', 'C', 'pc@prueba.test', 'propietario', true),
  ('ac000000-0000-0000-0000-000000000005', 'ac100000-0000-0000-0000-00000000000d', 'P', 'D', 'pd@prueba.test', 'propietario', true);

-- 1. Un lote con de todo, importado por el propietario de A
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table r1 as select public.adn_importar_miembros($j$[
  {"nombre": "Ana", "apellido": "Pérez", "email": "  ANA@X.test ", "telefono": "+34 600 111 222", "fecha_nacimiento": "1990-05-21", "notas": "Llegó por una amiga",
   "contactos": [
     {"tipo": "correo", "valor": "Ana2@X.test"}, {"tipo": "correo", "valor": "ana@x.test"},
     {"tipo": "telefono", "valor": "(91) 555-01-23", "etiqueta": "Casa"}, {"tipo": "telefono", "valor": "+34600111222"},
     {"tipo": "direccion", "etiqueta": "Casa", "valor": "Calle Falsa 123, Sevilla"},
     {"tipo": "etiqueta", "valor": "Célula Norte"}, {"tipo": "etiqueta", "valor": "Voluntarios"},
     {"tipo": "password", "valor": "secreto-no-importar"}, {"tipo": "otra", "valor": "x"}]},
  {"nombre": "Luis", "apellido": "", "telefono": "600 333 444"},
  {"nombre": "Segunda", "apellido": "Persona", "email": "ana2@x.test"},
  {"nombre": "Solo Nombre", "apellido": ""},
  {"nombre": "", "apellido": "Sin nombre", "email": "sinnombre@x.test"}
]$j$::jsonb) r;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select r ->> 'importados' from r1), '3', 'se importan Ana, Luis y Solo Nombre');
select pg_temp.igual((select r ->> 'duplicados_correo' from r1), '1', 'un correo adicional ya usado marca duplicado');
select pg_temp.igual((select r ->> 'invalidas' from r1), '1', 'una fila sin nombre es invalida');
select pg_temp.igual((select email || '|' || telefono || '|' || fecha_nacimiento::text || '|' || notas from public.miembros where nombre = 'Ana'), 'ana@x.test|+34600111222|1990-05-21|Llegó por una amiga', 'el correo va en minusculas y el telefono en forma canonica');
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos c join public.miembros m on m.id = c.miembro_id where m.nombre = 'Ana' and c.tipo = 'correo' and c.valor = 'ana2@x.test'), '1', 'el segundo correo queda como dato adicional');
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos c join public.miembros m on m.id = c.miembro_id where m.nombre = 'Ana' and c.tipo = 'correo'), '1', 'el correo principal repetido no se duplica');
select pg_temp.igual((select string_agg(valor, ',' order by orden) from public.adn_miembro_contactos c join public.miembros m on m.id = c.miembro_id where m.nombre = 'Ana' and c.tipo = 'telefono'), '915550123', 'el segundo telefono se guarda; el repetido del principal no');
select pg_temp.igual((select etiqueta || ':' || valor from public.adn_miembro_contactos c join public.miembros m on m.id = c.miembro_id where m.nombre = 'Ana' and c.tipo = 'direccion'), 'Casa:Calle Falsa 123, Sevilla', 'la direccion conserva su etiqueta');
select pg_temp.igual((select string_agg(valor, ',' order by valor) from public.adn_miembro_contactos c join public.miembros m on m.id = c.miembro_id where m.nombre = 'Ana' and c.tipo = 'etiqueta' and c.etiqueta is null), 'Célula Norte,Voluntarios', 'las etiquetas se guardan');
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos where tipo not in ('correo', 'telefono', 'direccion', 'etiqueta') or valor like '%secreto%'), '0', 'un tipo desconocido (p. ej. password) no se guarda');
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos where etiqueta = 'importacion' and valor like 'Importado % (google)'), '3', 'cada importado lleva la marca de la importacion');
select pg_temp.igual((select telefono from public.miembros where nombre = 'Luis'), '600333444', 'un telefono sin prefijo se guarda solo con digitos');

-- 2. Importar lo mismo otra vez no duplica nada
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table r2 as select public.adn_importar_miembros($j$[
  {"nombre": "Ana", "apellido": "Pérez", "email": "ana@x.test"},
  {"nombre": "Luis", "apellido": "", "telefono": "600-333-444 "},
  {"nombre": "Solo", "apellido": "Nombre"},
  {"nombre": "SOLO  nombre", "apellido": ""}
]$j$::jsonb) r;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select (r = '{"invalidas": 0, "importados": 0, "duplicados_correo": 1, "duplicados_nombre": 2, "duplicados_telefono": 1, "notas_descartadas": 0}'::jsonb)::text from r2), 'true',
  'repetir la importacion no duplica nada: por correo, por telefono (con otro formato) ni por nombre');

-- 3. Repetidos dentro del propio lote, valores invalidos y claves
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
create temp table r3 as select public.adn_importar_miembros($j$[
  {"nombre": "Rep", "apellido": "Uno", "email": "rep@x.test"},
  {"nombre": "Rep", "apellido": "Dos", "email": "REP@x.test"},
  {"nombre": "Mal", "apellido": "Datos", "email": "no-es-correo", "telefono": "abc", "fecha_nacimiento": "2999-01-01"},
  {"nombre": "Mal", "apellido": "Fecha", "email": "fecha@x.test", "fecha_nacimiento": "31/02/2000"},
  {"nombre": "Ceros", "apellido": "Tel", "email": "ceros@x.test", "telefono": "0000000"},
  {"nombre": "Con", "apellido": "Clave", "email": "clave@x.test", "notas": "Contraseña: abc123"},
  {"nombre": "Con", "apellido": "Clave2", "email": "clave2@x.test", "notas": "password = hunter2"},
  {"nombre": "Con", "apellido": "Clave3", "email": "clave3@x.test", "notas": "PIN: 1234"},
  {"nombre": "Nota", "apellido": "Normal", "email": "nota@x.test", "notas": "No recuerda la contraseña del wifi, preguntar"},
  {"nombre": "Nota", "apellido": "Spin", "email": "spin@x.test", "notas": "Clase de spin: martes"}
]$j$::jsonb) r;
reset role;
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.igual((select r ->> 'importados' from r3), '9', 'en el lote entran 9 y el repetido por correo se omite');
select pg_temp.igual((select r ->> 'duplicados_correo' from r3), '1', 'dos filas del mismo lote con el mismo correo (aunque cambie la caja): una sola');
select pg_temp.igual((select r ->> 'notas_descartadas' from r3), '3', 'tres notas con claves se descartan');
select pg_temp.igual((select count(*)::text from public.miembros where apellido in ('Clave', 'Clave2', 'Clave3') and notas is not null), '0', 'ninguna clave llega a la base');
select pg_temp.igual((select notas from public.miembros where apellido = 'Normal'), 'No recuerda la contraseña del wifi, preguntar', 'una nota normal que menciona la palabra se conserva');
select pg_temp.igual((select notas from public.miembros where apellido = 'Spin'), 'Clase de spin: martes', 'una nota con "spin:" no se toma por una clave');
select pg_temp.igual((select (email is null and telefono is null and fecha_nacimiento is null)::text from public.miembros where apellido = 'Datos'), 'true', 'correo, telefono y fecha invalidos se descartan, el contacto entra');
select pg_temp.igual((select fecha_nacimiento::text from public.miembros where apellido = 'Fecha'), null, 'una fecha imposible se descarta');
select pg_temp.igual((select telefono from public.miembros where apellido = 'Tel'), null, 'un telefono de ceros se descarta');

-- 4. Permisos, modo alias, tamano del lote
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_importar_miembros('[{"nombre": "X", "apellido": "Y", "email": "x1@x.test"}]'::jsonb)$$, 'ADN_SIN_PERMISO', 'un colaborador, que puede crear pero no importar, no importa');
reset role;
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000005', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_importar_miembros('[{"nombre": "X", "apellido": "Y"}]'::jsonb)$$, 'ADN_MODO_ALIAS', 'una iglesia en modo alias no importa contactos');
reset role;
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_importar_miembros((select jsonb_agg(jsonb_build_object('nombre', 'N' || i, 'apellido', 'L')) from generate_series(1, 1001) i))$$, 'ADN_LOTE_INVALIDO', 'un lote de mas de 1000 se rechaza');
select pg_temp.falla($$select public.adn_importar_miembros('{"nombre": "X"}'::jsonb)$$, 'ADN_LOTE_INVALIDO', 'un objeto en lugar de una lista se rechaza');
select pg_temp.falla($$select public.adn_importar_miembros('[]'::jsonb, 'MAL ORIGEN')$$, 'ADN_ORIGEN_INVALIDO', 'un origen con formato raro se rechaza');
select pg_temp.igual((select (public.adn_importar_miembros('[]'::jsonb) ->> 'importados')), '0', 'un lote vacio no importa nada y no falla');
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select pg_temp.falla($$select public.adn_importar_miembros('[]'::jsonb)$$, 'permission denied', 'un visitante no ejecuta la importacion');
select pg_temp.falla($$select * from public.adn_miembro_contactos$$, 'permission denied', 'un visitante no lee contactos');
reset role;

-- 5. Aislamiento: el mismo correo en otra iglesia no es duplicado y sus datos no se ven entre iglesias
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000003', true);
set local role authenticated;
create temp table rb as select public.adn_importar_miembros('[{"nombre": "Ana", "apellido": "Otra", "email": "ana@x.test", "contactos": [{"tipo": "correo", "valor": "ana2@x.test"}]}]'::jsonb) r;
select pg_temp.igual((select r ->> 'importados' from rb), '1', 'el mismo correo en otra iglesia se importa');
select pg_temp.igual((select count(*)::text from public.miembros), '1', 'B solo ve su miembro');
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos), '2', 'B solo ve sus datos adicionales (el segundo correo y la marca)');
reset role;
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos c where c.iglesia_id = 'ac100000-0000-0000-0000-00000000000b'), '0', 'A no ve los datos adicionales de B');
select pg_temp.falla($$insert into public.adn_miembro_contactos (iglesia_id, miembro_id, tipo, valor) select 'ac100000-0000-0000-0000-00000000000b', id, 'correo', 'x@x.test' from public.miembros limit 1$$, 'row-level security', 'A no escribe datos adicionales en B');
reset role;
select set_config('request.jwt.claim.sub', '', true);
-- Una clave foranea compuesta impide colgar datos de un miembro de otra iglesia
select pg_temp.falla($$insert into public.adn_miembro_contactos (iglesia_id, miembro_id, tipo, valor)
  select 'ac100000-0000-0000-0000-00000000000a', id, 'correo', 'cruce@x.test' from public.miembros where iglesia_id = 'ac100000-0000-0000-0000-00000000000b' limit 1$$, 'adn_miembro_contactos_miembro_fk', 'no se cuelgan datos de un miembro de otra iglesia');

-- 6. Limite del plan y atomicidad: la semilla admite 50; con 48 ya dentro, un lote de 3 no entra ni en parte
insert into public.miembros (iglesia_id, nombre, apellido) select 'ac100000-0000-0000-0000-00000000000c', 'M' || i, 'C' from generate_series(1, 48) i;
select set_config('request.jwt.claim.sub', 'ac000000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.falla($$select public.adn_importar_miembros('[{"nombre": "L1", "apellido": "x", "email": "l1@x.test"}, {"nombre": "L2", "apellido": "x", "email": "l2@x.test"}, {"nombre": "L3", "apellido": "x", "email": "l3@x.test"}]'::jsonb)$$, 'PLAN_LIMITE', 'el limite del plan corta la importacion');
select pg_temp.igual((select count(*)::text from public.miembros), '48', 'la importacion fallida no deja ninguno: es atomica');
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos), '0', 'ni datos adicionales sueltos');
reset role;
select set_config('request.jwt.claim.sub', '', true);

-- 7. Los datos adicionales se van con el miembro
delete from public.miembros where nombre = 'Ana' and apellido = 'Pérez';
select pg_temp.igual((select count(*)::text from public.adn_miembro_contactos c where c.valor = 'ana2@x.test' and c.iglesia_id = 'ac100000-0000-0000-0000-00000000000a'), '0', 'borrar al miembro borra sus datos adicionales');
rollback;
