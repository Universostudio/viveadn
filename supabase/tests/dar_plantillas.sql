-- Plantillas de dar: fondos propios, tope de fondos, apariencia por iglesia y permisos.
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
create or replace function pg_temp.debe_fallar(q text, msg text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then raise notice 'OK: %', msg; return; end;
  raise exception 'FALLO: debia fallar: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.debe_fallar(text, text) to authenticated, service_role;

insert into auth.users (id) values ('e3000000-0000-0000-0000-000000000001'), ('e3000000-0000-0000-0000-000000000002'), ('e3000000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('1b000000-0000-0000-0000-00000000000a', 'Prueba D1', 'prueba-pd1', 'ES', 'Sevilla', 'premium'),
  ('1b000000-0000-0000-0000-00000000000b', 'Prueba D2', 'prueba-pd2', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('e3000000-0000-0000-0000-000000000001', '1b000000-0000-0000-0000-00000000000a', 'Pro', 'Uno', 'p@pd1.test', 'propietario', true),
  ('e3000000-0000-0000-0000-000000000002', '1b000000-0000-0000-0000-00000000000a', 'Mie', 'Dos', 'm@pd1.test', 'miembro', true),
  ('e3000000-0000-0000-0000-000000000003', '1b000000-0000-0000-0000-00000000000b', 'Pro', 'Tres', 'p@pd2.test', 'propietario', true);

-- Fondos: claves libres pero acotadas
insert into public.enlaces_dar (iglesia_id, tipo, url, nombre, descripcion, orden) values
  ('1b000000-0000-0000-0000-00000000000a', 'misiones', 'https://dar.pd1.test/misiones', 'Misiones y Expansión', 'Expansión del Reino', 2),
  ('1b000000-0000-0000-0000-00000000000a', 'casas_oracion', 'https://dar.pd1.test/casas', 'Casas de Oración', null, 3),
  ('1b000000-0000-0000-0000-00000000000a', 'diezmo', 'https://dar.pd1.test/diezmo', null, null, 1);
select pg_temp.igual((select count(*)::text from public.enlaces_dar where iglesia_id = '1b000000-0000-0000-0000-00000000000a'), '3', 'se aceptan fondos propios y los tres tipos originales');
select pg_temp.igual((select orden::text from public.enlaces_dar where tipo = 'diezmo' and iglesia_id = '1b000000-0000-0000-0000-00000000000a'), '1', 'el orden se guarda');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'Con Mayuscula', 'https://x.test') $q$, 'clave con mayusculas');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'con espacio', 'https://x.test') $q$, 'clave con espacios');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', '', 'https://x.test') $q$, 'clave vacia');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'a-b', 'https://x.test') $q$, 'clave con guion medio');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', repeat('a', 41), 'https://x.test') $q$, 'clave de mas de 40 caracteres');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url, nombre) values ('1b000000-0000-0000-0000-00000000000a', 'otro', 'https://x.test', repeat('n', 81)) $q$, 'nombre de mas de 80 caracteres');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url, nombre) values ('1b000000-0000-0000-0000-00000000000a', 'otro', 'https://x.test', '   ') $q$, 'nombre en blanco');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url, descripcion) values ('1b000000-0000-0000-0000-00000000000a', 'otro', 'https://x.test', repeat('d', 201)) $q$, 'descripcion de mas de 200 caracteres');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'otro', 'javascript:alert(1)') $q$, 'la direccion sigue debiendo ser https');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'misiones', 'https://otra.test') $q$, 'un fondo no se repite en la misma iglesia');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url, orden) values ('1b000000-0000-0000-0000-00000000000a', 'otro', 'https://x.test', -1) $q$, 'orden negativo');

-- Tope de 20 fondos por iglesia
do $$ declare i int; begin
  for i in 4..20 loop
    insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'fondo_' || i, 'https://dar.pd1.test/' || i);
  end loop;
  perform pg_temp.igual((select count(*)::text from public.enlaces_dar where iglesia_id = '1b000000-0000-0000-0000-00000000000a'), '20', 'una iglesia llega a 20 fondos');
  begin
    insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'fondo_21', 'https://dar.pd1.test/21');
    raise exception 'FALLO: se admitio el fondo 21';
  exception when check_violation then raise notice 'OK: el fondo 21 se rechaza'; end;
end $$;
-- Con 20 fondos, guardar cambios (upsert) en los que ya existen debe seguir funcionando
insert into public.enlaces_dar (iglesia_id, tipo, url, nombre, orden)
  select '1b000000-0000-0000-0000-00000000000a', tipo, url, 'Guardado de nuevo', 5 from public.enlaces_dar where iglesia_id = '1b000000-0000-0000-0000-00000000000a'
  on conflict (iglesia_id, tipo) do update set nombre = excluded.nombre, orden = excluded.orden;
select pg_temp.igual((select count(*)::text from public.enlaces_dar where iglesia_id = '1b000000-0000-0000-0000-00000000000a' and nombre = 'Guardado de nuevo'), '20', 'con 20 fondos, el upsert de los existentes funciona');
select pg_temp.igual((select count(*)::text from public.enlaces_dar where iglesia_id = '1b000000-0000-0000-0000-00000000000a'), '20', 'y no se crean fondos de mas');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000a', 'fondo_nuevo', 'https://x.test') on conflict (iglesia_id, tipo) do update set url = excluded.url $q$, 'un upsert que crearia el fondo 21 se rechaza');
select pg_temp.igual((select count(*)::text from public.enlaces_dar where iglesia_id = '1b000000-0000-0000-0000-00000000000b'), '0', 'el tope es por iglesia: otra iglesia no se ve afectada');
insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000b', 'diezmo', 'https://dar.pd2.test/diezmo');
select pg_temp.igual(has_function_privilege('authenticated', 'private.limitar_fondos_dar()', 'execute')::text, 'false', 'la funcion del tope no es ejecutable desde fuera');

-- Apariencia: valores por defecto y restricciones
insert into public.dar_config (iglesia_id) values ('1b000000-0000-0000-0000-00000000000a');
select pg_temp.igual((select plantilla || '|' || color_primario || '|' || color_acento || '|' || calculadora || '|' || moneda from public.dar_config), 'clasica|#00523c|#f5a623|dia|EUR', 'valores por defecto de la apariencia');
select pg_temp.debe_fallar($q$ insert into public.dar_config (iglesia_id) values ('1b000000-0000-0000-0000-00000000000a') $q$, 'una sola configuracion por iglesia');
select pg_temp.debe_fallar($q$ update public.dar_config set plantilla = 'neon' $q$, 'plantilla inexistente');
select pg_temp.debe_fallar($q$ update public.dar_config set color_primario = 'rojo' $q$, 'color que no es hexadecimal');
select pg_temp.debe_fallar($q$ update public.dar_config set color_primario = '#12345' $q$, 'color de 5 digitos');
select pg_temp.debe_fallar($q$ update public.dar_config set color_acento = 'red;background:url(x)' $q$, 'color con codigo CSS');
select pg_temp.debe_fallar($q$ update public.dar_config set logo_url = 'http://x.test/logo.png' $q$, 'logo sin https');
select pg_temp.debe_fallar($q$ update public.dar_config set logo_url = 'https://x.test/a b.png' $q$, 'logo con espacios');
select pg_temp.debe_fallar($q$ update public.dar_config set calculadora = 'otra' $q$, 'modo de calculadora inexistente');
select pg_temp.debe_fallar($q$ update public.dar_config set moneda = 'eur' $q$, 'moneda en minusculas');
select pg_temp.debe_fallar($q$ update public.dar_config set titulo = repeat('t', 101) $q$, 'titulo de mas de 100 caracteres');
update public.dar_config set plantilla = 'dia', color_primario = '#0F2C4A', logo_url = 'https://x.test/logo.png', calculadora = 'diezmo', moneda = 'USD', titulo = 'Generosidad', subtitulo = 'Gracias';
select pg_temp.igual((select plantilla || '|' || color_primario || '|' || calculadora || '|' || moneda from public.dar_config), 'dia|#0F2C4A|diezmo|USD', 'una configuracion valida se guarda');

-- Permisos
select set_config('request.jwt.claim.sub', 'e3000000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.dar_config), '1', 'un miembro ve la apariencia de su iglesia');
select pg_temp.igual((select count(*)::text from public.enlaces_dar), '20', 'un miembro ve los fondos de su iglesia y no los de otra');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (tipo, url) values ('nuevo', 'https://x.test') $q$, 'un miembro no crea fondos');
do $$ declare n int; begin
  update public.dar_config set titulo = 'Cambiado'; get diagnostics n = row_count; perform pg_temp.igual(n::text, '0', 'un miembro no cambia la apariencia');
  update public.enlaces_dar set nombre = 'X'; get diagnostics n = row_count; perform pg_temp.igual(n::text, '0', 'un miembro no cambia los fondos');
end $$;
reset role;

select set_config('request.jwt.claim.sub', 'e3000000-0000-0000-0000-000000000001', true);
set local role authenticated;
do $$ declare n int; begin
  update public.dar_config set titulo = 'Del propietario'; get diagnostics n = row_count; perform pg_temp.igual(n::text, '1', 'el propietario cambia la apariencia');
  update public.enlaces_dar set nombre = 'Renombrado' where tipo = 'misiones'; get diagnostics n = row_count; perform pg_temp.igual(n::text, '1', 'el propietario cambia un fondo');
  delete from public.enlaces_dar where tipo = 'fondo_20'; get diagnostics n = row_count; perform pg_temp.igual(n::text, '1', 'el propietario borra un fondo');
end $$;
select pg_temp.debe_fallar($q$ insert into public.dar_config (iglesia_id) values ('1b000000-0000-0000-0000-00000000000b') $q$, 'no crea la apariencia de otra iglesia');
select pg_temp.debe_fallar($q$ insert into public.enlaces_dar (iglesia_id, tipo, url) values ('1b000000-0000-0000-0000-00000000000b', 'intruso', 'https://x.test') $q$, 'no crea fondos en otra iglesia');
reset role;

select set_config('request.jwt.claim.sub', 'e3000000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.dar_config), '0', 'otra iglesia no ve la apariencia ajena');
select pg_temp.igual((select count(*)::text from public.enlaces_dar), '1', 'otra iglesia solo ve sus fondos');
reset role;

-- Borrar la iglesia borra su apariencia
delete from public.iglesias where id = '1b000000-0000-0000-0000-00000000000a';
select pg_temp.igual((select count(*)::text from public.dar_config where iglesia_id = '1b000000-0000-0000-0000-00000000000a'), '0', 'borrar la iglesia borra su apariencia');
rollback;
