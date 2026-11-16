-- Método de seguimiento configurable, fase 1: plantillas, restricciones, regla del color (con los bordes exactos de 24, 48 y 72 horas),
-- disparador de consolidaciones, integridad entre iglesias y seguridad por filas. Todo dentro de una transacción que se deshace.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then raise exception 'Este script no se ejecuta en una base con iglesias reales'; end if;
end $$;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm not like '%' || texto || '%' and sqlstate <> texto then raise exception 'FALLO: % (error inesperado % %)', msg, sqlstate, sqlerrm; end if;
    raise notice 'OK: % (%)', msg, sqlstate; return;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
create or replace function pg_temp.filas(sentencia text) returns text language plpgsql as $$
declare n integer;
begin execute sentencia; get diagnostics n = row_count; return n::text; end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text), pg_temp.filas(text) to authenticated, anon, service_role;

insert into auth.users (id) values ('af800000-0000-0000-0000-000000000001'), ('af800000-0000-0000-0000-000000000002');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('af810000-0000-0000-0000-00000000000a', 'Prueba Metodos A', 'prueba-metodos-a', 'ES', 'Sevilla', 'premium'),
  ('af810000-0000-0000-0000-00000000000b', 'Prueba Metodos B', 'prueba-metodos-b', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('af800000-0000-0000-0000-000000000001', 'af810000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@metodos.test', 'propietario', true),
  ('af800000-0000-0000-0000-000000000002', 'af810000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@metodos.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) values
  ('af820000-0000-0000-0000-0000000000a1', 'af810000-0000-0000-0000-00000000000a', 'A', 'Uno'),
  ('af820000-0000-0000-0000-0000000000b1', 'af810000-0000-0000-0000-00000000000b', 'B', 'Uno');
-- Un método propio de cada iglesia
insert into public.adn_seguimiento_metodos (id, iglesia_id, clave, nombre, plantilla_origen, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values
  ('af830000-0000-0000-0000-0000000000a1', 'af810000-0000-0000-0000-00000000000a', 'propio', 'Propio de A', '5e000000-0000-4000-8000-000000000072', 2, 96, 30, 60),
  ('af830000-0000-0000-0000-0000000000b1', 'af810000-0000-0000-0000-00000000000b', 'propio', 'Propio de B', null, 1, 48, 12, 24);

-- 1. Plantillas
select pg_temp.igual((select clave || ':' || pasos || ':' || plazo_horas || ':' || umbral_amarillo_horas || ':' || umbral_naranja_horas || ':' || primer_contacto_horas from public.adn_seguimiento_metodos where id = '5e000000-0000-4000-8000-000000000072'),
  'op72:3:72:24:48:24', 'OP72 lleva los valores de siempre: 3 pasos, 72 horas, colores a 24 y 48, primer contacto a 24');
select pg_temp.igual((select clave || ':' || pasos || ':' || plazo_horas || ':' || umbral_amarillo_horas || ':' || umbral_naranja_horas from public.adn_seguimiento_metodos where id = '5e000000-0000-4000-8000-000000000001'),
  'simple:1:168:72:120', 'Seguimiento simple lleva los valores propuestos (por validar)');
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_metodos where iglesia_id is null), '2', 'solo dos plantillas de plataforma');

-- 2. Restricciones
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000a', 'x1', 'X', 1, 72, 48, 48)$$, 'umbrales', 'amarillo y naranja deben ir en orden estricto');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000a', 'x2', 'X', 1, 72, 24, 80)$$, 'umbrales', 'el naranja no puede pasar del plazo');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000a', 'x3', 'X', 4, 72, 24, 48)$$, 'pasos', 'más de tres pasos no cabe todavía');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000a', 'x4', 'X', 1, 721, 24, 48)$$, 'plazo_horas', 'el plazo máximo son 720 horas');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000a', 'Mal Clave', 'X', 1, 72, 24, 48)$$, 'clave', 'la clave tiene una forma fija');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas, primer_contacto_horas) values ('af810000-0000-0000-0000-00000000000a', 'x5', 'X', 1, 72, 24, 48, 100)$$, 'primer', 'el primer contacto no puede pasar del plazo');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000a', 'propio', 'Otro', 1, 72, 24, 48)$$, 'adn_seguimiento_metodos_clave_idx', 'una iglesia no repite clave');
insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000b', 'otra', 'Misma clave que A en otra iglesia', 1, 72, 24, 48);
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values (null, 'op72', 'Duplicada', 1, 72, 24, 48)$$, 'adn_seguimiento_metodos_clave_idx', 'una plantilla de plataforma tampoco repite clave');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, plantilla_origen, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000a', 'copia', 'Copia ajena', 'af830000-0000-0000-0000-0000000000b1', 1, 72, 24, 48)$$, 'ADN_PLANTILLA_DE_OTRA_IGLESIA', 'no se copia el método propio de otra iglesia');

-- 3. La regla del color con los bordes exactos (hora fija para que nada dependa del reloj)
create or replace function pg_temp.antiguo(horas numeric) returns text language plpgsql as $$
begin  -- el código que había escrito a mano en el disparador anterior
  if horas <= 24 then return 'verde'; elsif horas <= 48 then return 'amarillo'; elsif horas <= 72 then return 'naranja'; else return 'rojo'; end if;
end $$;
create or replace function pg_temp.nuevo(horas numeric, metodo uuid default '5e000000-0000-4000-8000-000000000072') returns text language sql as $$
  select public.adn_seguimiento_alerta(timestamptz '2026-11-16 12:00+00' - horas * interval '1 hour', false, metodo, timestamptz '2026-11-16 12:00+00') $$;
select pg_temp.igual((select string_agg(case when pg_temp.nuevo(h) = pg_temp.antiguo(h) then 'ok' else 'DISTINTO@' || h end, ',' order by h)
    from unnest(array[0, 0.5, 1, 23.99, 24, 24.01, 47.99, 48, 48.01, 71.99, 72, 72.01, 100, 500]::numeric[]) h),
  'ok,ok,ok,ok,ok,ok,ok,ok,ok,ok,ok,ok,ok,ok', 'con OP72 el color coincide con el código antiguo en 14 edades, incluidos los bordes de 24, 48 y 72 horas');
select pg_temp.igual(pg_temp.nuevo(24) || '/' || pg_temp.nuevo(24.01) || '/' || pg_temp.nuevo(48) || '/' || pg_temp.nuevo(48.01) || '/' || pg_temp.nuevo(72) || '/' || pg_temp.nuevo(72.01), 'verde/amarillo/amarillo/naranja/naranja/rojo', 'cada borde pertenece al color de antes (24 verde, 48 amarillo, 72 naranja)');
select pg_temp.igual(public.adn_seguimiento_alerta(timestamptz '2026-11-01 00:00+00', true, '5e000000-0000-4000-8000-000000000072', timestamptz '2026-11-16 12:00+00'), 'verde', 'un proceso completado es verde, por antiguo que sea');
select pg_temp.igual(pg_temp.nuevo(300, 'af830000-0000-0000-0000-0000000000a1'), 'rojo', 'un método propio se lee con sus números (96 horas de plazo: a 300 es rojo)');
select pg_temp.igual(pg_temp.nuevo(95, 'af830000-0000-0000-0000-0000000000a1'), 'naranja', 'y a 95 horas, dentro de su plazo de 96, es naranja');
select pg_temp.igual(pg_temp.nuevo(100, gen_random_uuid()), 'rojo', 'un método inexistente se trata como OP72: 100 horas es rojo');
select pg_temp.igual(pg_temp.nuevo(60, gen_random_uuid()), 'naranja', 'y 60 horas es naranja, como siempre');
select pg_temp.igual(pg_temp.nuevo(72, '5e000000-0000-4000-8000-000000000001') || '/' || pg_temp.nuevo(72.01, '5e000000-0000-4000-8000-000000000001') || '/' || pg_temp.nuevo(120, '5e000000-0000-4000-8000-000000000001') || '/' || pg_temp.nuevo(120.01, '5e000000-0000-4000-8000-000000000001') || '/' || pg_temp.nuevo(168, '5e000000-0000-4000-8000-000000000001') || '/' || pg_temp.nuevo(168.01, '5e000000-0000-4000-8000-000000000001'),
  'verde/amarillo/amarillo/naranja/naranja/rojo', 'Seguimiento simple usa sus propios números (72, 120 y 168)');

-- 4. Disparador de consolidaciones: sin método se comporta como siempre; con otro método usa el suyo
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion) values
  ('af840000-0000-0000-0000-000000000010', 'af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', now() - interval '10 hours'),
  ('af840000-0000-0000-0000-000000000030', 'af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', now() - interval '30 hours'),
  ('af840000-0000-0000-0000-000000000060', 'af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', now() - interval '60 hours'),
  ('af840000-0000-0000-0000-000000000100', 'af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', now() - interval '100 hours');
select pg_temp.igual((select string_agg(estado_alerta, ',' order by id) from public.consolidaciones where id in ('af840000-0000-0000-0000-000000000010', 'af840000-0000-0000-0000-000000000030', 'af840000-0000-0000-0000-000000000060', 'af840000-0000-0000-0000-000000000100')), 'verde,amarillo,naranja,rojo', 'sin método, el color guardado es el de siempre (10, 30, 60 y 100 horas)');
select pg_temp.igual((select count(*)::text from public.consolidaciones where id in ('af840000-0000-0000-0000-000000000010', 'af840000-0000-0000-0000-000000000030', 'af840000-0000-0000-0000-000000000060', 'af840000-0000-0000-0000-000000000100') and metodo_id = '5e000000-0000-4000-8000-000000000072'), '4', 'todo proceso nuevo sin método nace con OP72');
select pg_temp.igual((select count(*)::text from public.consolidaciones where id in ('af840000-0000-0000-0000-000000000010', 'af840000-0000-0000-0000-000000000030', 'af840000-0000-0000-0000-000000000060', 'af840000-0000-0000-0000-000000000100') and fecha_limite = fecha_conversion + interval '72 hours'), '4', 'la fecha límite sigue siendo conversión más 72 horas');
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion, metodo_id) values
  ('af840000-0000-0000-0000-000000000501', 'af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', now() - interval '100 hours', '5e000000-0000-4000-8000-000000000001'),
  ('af840000-0000-0000-0000-000000000502', 'af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', now() - interval '100 hours', 'af830000-0000-0000-0000-0000000000a1');
select pg_temp.igual((select estado_alerta || '/' || (fecha_limite = fecha_conversion + interval '168 hours')::text from public.consolidaciones where id = 'af840000-0000-0000-0000-000000000501'), 'amarillo/true', 'con Seguimiento simple: 100 horas es amarillo y la fecha límite es a 168 horas');
select pg_temp.igual((select estado_alerta || '/' || (fecha_limite = fecha_conversion + interval '96 hours')::text from public.consolidaciones where id = 'af840000-0000-0000-0000-000000000502'), 'rojo/true', 'con un método propio de 96 horas: 100 horas es rojo y la fecha límite es a 96 horas');
-- Completar y reabrir siguen igual
update public.consolidaciones set completado = true where id = 'af840000-0000-0000-0000-000000000100';
select pg_temp.igual((select (completado_at is not null)::text from public.consolidaciones where id = 'af840000-0000-0000-0000-000000000100'), 'true', 'completar fija la fecha de cierre');
update public.consolidaciones set completado = false where id = 'af840000-0000-0000-0000-000000000100';
select pg_temp.igual((select (completado_at is null)::text || '/' || estado_alerta from public.consolidaciones where id = 'af840000-0000-0000-0000-000000000100'), 'true/rojo', 'reabrir limpia la fecha de cierre y recalcula el color');

-- 5. Integridad: un proceso solo usa un método de plataforma o de su propia iglesia
select pg_temp.falla($$insert into public.consolidaciones (iglesia_id, miembro_id, metodo_id) values ('af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', 'af830000-0000-0000-0000-0000000000b1')$$, 'ADN_METODO_DE_OTRA_IGLESIA', 'A no puede usar el método propio de B');
select pg_temp.falla($$update public.consolidaciones set metodo_id = 'af830000-0000-0000-0000-0000000000b1' where id = 'af840000-0000-0000-0000-000000000010'$$, 'ADN_METODO_DE_OTRA_IGLESIA', 'tampoco cambiándolo después');
select pg_temp.falla($$insert into public.consolidaciones (iglesia_id, miembro_id, metodo_id) values ('af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', gen_random_uuid())$$, '23503', 'un método que no existe se rechaza');
update public.adn_seguimiento_metodos set archivado_en = now() where id = 'af830000-0000-0000-0000-0000000000a1';
select pg_temp.falla($$insert into public.consolidaciones (iglesia_id, miembro_id, metodo_id) values ('af810000-0000-0000-0000-00000000000a', 'af820000-0000-0000-0000-0000000000a1', 'af830000-0000-0000-0000-0000000000a1')$$, 'ADN_METODO_ARCHIVADO', 'un método archivado no se elige para un proceso nuevo');
update public.consolidaciones set notas = 'sigue con su método archivado' where id = 'af840000-0000-0000-0000-000000000502';
select pg_temp.igual((select metodo_id::text from public.consolidaciones where id = 'af840000-0000-0000-0000-000000000502'), 'af830000-0000-0000-0000-0000000000a1', 'un proceso que ya lo usaba lo conserva aunque se archive');
select pg_temp.falla($$update public.consolidaciones set metodo_id = 'af830000-0000-0000-0000-0000000000a1' where id = 'af840000-0000-0000-0000-000000000010'$$, 'ADN_METODO_ARCHIVADO', 'pero no se cambia a un método archivado');
-- Configuración
select pg_temp.falla($$insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('af810000-0000-0000-0000-00000000000a', 'af830000-0000-0000-0000-0000000000b1')$$, 'ADN_METODO_DE_OTRA_IGLESIA', 'la configuración de A no puede apuntar al método de B');
select pg_temp.igual(private.adn_metodo_activo('af810000-0000-0000-0000-00000000000a')::text, '5e000000-0000-4000-8000-000000000072', 'sin configuración, el método activo es OP72');
update public.adn_seguimiento_metodos set archivado_en = null where id = 'af830000-0000-0000-0000-0000000000a1';
insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('af810000-0000-0000-0000-00000000000a', 'af830000-0000-0000-0000-0000000000a1');
select pg_temp.igual(private.adn_metodo_activo('af810000-0000-0000-0000-00000000000a')::text, 'af830000-0000-0000-0000-0000000000a1', 'con configuración, el método activo es el elegido');
select pg_temp.igual(private.adn_metodo_activo('af810000-0000-0000-0000-00000000000b')::text, '5e000000-0000-4000-8000-000000000072', 'y la otra iglesia sigue con OP72');

-- 6. Seguridad por filas
select set_config('request.jwt.claim.sub', 'af800000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual((select string_agg(clave, ',' order by clave) from public.adn_seguimiento_metodos), 'op72,propio,simple', 'A ve las dos plantillas y su propio método, no el de B (ni «otra» de B)');
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_config), '1', 'A ve su configuración');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('af810000-0000-0000-0000-00000000000b', 'mio', 'M', 1, 72, 24, 48)$$, '42501', 'con sesión no se crea un método a nombre de otra iglesia (crear los propios es de la fase 3, probada aparte)');
select pg_temp.igual(pg_temp.filas($$update public.adn_seguimiento_metodos set nombre = 'Cambiada' where id = '5e000000-0000-4000-8000-000000000072'$$), '0', 'nadie con sesión edita las plantillas de plataforma (la fase 3 permite editar los propios, no estos: ninguna fila cambia)');
select pg_temp.falla($$delete from public.adn_seguimiento_metodos where id = 'af830000-0000-0000-0000-0000000000a1'$$, '42501', 'ni borra métodos');
select pg_temp.falla($$update public.adn_seguimiento_config set metodo_id = 'af830000-0000-0000-0000-0000000000b1'$$, 'ADN_METODO_DE_OTRA_IGLESIA', 'ni elige el método propio de otra iglesia (elegir los suyos es de la fase 3, probada aparte)');
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_estado), '6', 'la vista de estado muestra solo los procesos de A (seis)');
select pg_temp.igual((select estado from public.adn_seguimiento_estado where id = 'af840000-0000-0000-0000-000000000060'), 'naranja', 'la vista da el color calculado ahora (60 horas con OP72 es naranja)');
reset role;
select set_config('request.jwt.claim.sub', 'af800000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.igual((select string_agg(clave, ',' order by clave) from public.adn_seguimiento_metodos), 'op72,otra,propio,simple', 'B ve las plantillas y sus dos métodos propios, no los de A');
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_estado), '0', 'B no ve ningún proceso de A en la vista');
reset role;
set local role anon;
select pg_temp.falla($$select count(*) from public.adn_seguimiento_metodos$$, '42501', 'sin sesión no se lee nada');
reset role;
rollback;
