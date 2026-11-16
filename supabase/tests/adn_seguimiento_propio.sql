-- Método de seguimiento configurable, fase 3: elegir método y, con el módulo (Premium), crear y editar el propio. Aislamiento entre iglesias,
-- permisos, módulo, restricciones, método activo para procesos nuevos, recálculo al editar plazos y límite. Todo dentro de una transacción que se deshace.
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
-- Filas que cambia una sentencia (la seguridad por filas no da error al editar una fila ajena: simplemente no la toca)
create or replace function pg_temp.filas(sentencia text) returns text language plpgsql as $$
declare n integer;
begin execute sentencia; get diagnostics n = row_count; return n::text; end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text), pg_temp.filas(text) to authenticated, anon, service_role;

insert into auth.users (id) values ('b1a00000-0000-0000-0000-000000000001'), ('b1a00000-0000-0000-0000-000000000002'), ('b1a00000-0000-0000-0000-000000000003'), ('b1a00000-0000-0000-0000-000000000004');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('b1a10000-0000-0000-0000-00000000000a', 'Prueba Propio A', 'prueba-propio-a', 'ES', 'Sevilla', 'premium'),
  ('b1a10000-0000-0000-0000-00000000000b', 'Prueba Propio B', 'prueba-propio-b', 'ES', 'Sevilla', 'premium'),
  ('b1a10000-0000-0000-0000-00000000000c', 'Prueba Propio C', 'prueba-propio-c', 'ES', 'Sevilla', 'semilla');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('b1a00000-0000-0000-0000-000000000001', 'b1a10000-0000-0000-0000-00000000000a', 'P', 'A', 'pa@propio.test', 'propietario', true),
  ('b1a00000-0000-0000-0000-000000000002', 'b1a10000-0000-0000-0000-00000000000a', 'C', 'A', 'ca@propio.test', 'colaborador', true),
  ('b1a00000-0000-0000-0000-000000000003', 'b1a10000-0000-0000-0000-00000000000b', 'P', 'B', 'pb@propio.test', 'propietario', true),
  ('b1a00000-0000-0000-0000-000000000004', 'b1a10000-0000-0000-0000-00000000000c', 'P', 'C', 'pc@propio.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) values
  ('b1a20000-0000-0000-0000-0000000000a1', 'b1a10000-0000-0000-0000-00000000000a', 'A', 'Uno'),
  ('b1a20000-0000-0000-0000-0000000000b1', 'b1a10000-0000-0000-0000-00000000000b', 'B', 'Uno'),
  ('b1a20000-0000-0000-0000-0000000000c1', 'b1a10000-0000-0000-0000-00000000000c', 'C', 'Uno');

-- Un método de B que ya existía (lo crea el servidor), para probar que A no puede copiarlo
insert into public.adn_seguimiento_metodos (id, iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas)
  values ('b1a30000-0000-0000-0000-0000000000b2', 'b1a10000-0000-0000-0000-00000000000b', 'previo_b', 'Previo de B', 1, 48, 12, 24);

-- 1. El módulo existe solo en Premium
select pg_temp.igual((select string_agg(plan, ',' order by plan) from public.plan_modulos where modulo = 'seguimiento_propio'), 'premium', 'el módulo seguimiento_propio está solo en el plan Premium');
select pg_temp.igual((select count(*)::text from public.modulos where clave = 'seguimiento_propio'), '1', 'y hay una sola fila de módulo');
select pg_temp.igual((select count(*)::text from public.plan_modulos where modulo = 'consolidacion_etapas' and plan = 'premium'), '1', 'consolidacion_etapas sigue aparte, sin tocar');

-- 2. La propietaria de A (Premium) crea su método copiando OP72
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.adn_seguimiento_metodos (id, iglesia_id, clave, nombre, plantilla_origen, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas, primer_contacto_horas)
  values ('b1a30000-0000-0000-0000-0000000000a1', 'b1a10000-0000-0000-0000-00000000000a', 'propio_a1', 'Mi método', '5e000000-0000-4000-8000-000000000072', 2, 96, 30, 60, 12);
select pg_temp.igual((select pasos || ':' || plazo_horas || ':' || umbral_amarillo_horas || ':' || umbral_naranja_horas || ':' || primer_contacto_horas || ':' || plantilla_origen::text from public.adn_seguimiento_metodos where id = 'b1a30000-0000-0000-0000-0000000000a1'),
  '2:96:30:60:12:5e000000-0000-4000-8000-000000000072', 'A crea su método con sus valores y la plantilla de origen');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000b', 'ajeno', 'X', 1, 72, 24, 48)$$, '42501', 'no se crea un método a nombre de otra iglesia');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values (null, 'plantilla', 'X', 1, 72, 24, 48)$$, '42501', 'ni una plantilla de plataforma');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'malo1', 'X', 1, 72, 48, 24)$$, '23514', 'umbrales al revés: se rechaza');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'malo2', 'X', 1, 72, 24, 80)$$, '23514', 'el naranja por encima del plazo: se rechaza');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'malo3', 'X', 4, 72, 24, 48)$$, '23514', 'cuatro pasos: se rechaza (más de tres es la fase 4)');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'malo4', 'X', 3, 721, 24, 48)$$, '23514', 'un plazo de más de 720 horas: se rechaza');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'malo5', '   ', 3, 72, 24, 48)$$, '23514', 'un nombre vacío: se rechaza');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'propio_a1', 'Repetido', 3, 72, 24, 48)$$, '23505', 'una clave repetida en la misma iglesia: se rechaza');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, plantilla_origen, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'copia_ajena', 'X', 'b1a30000-0000-0000-0000-0000000000b2', 3, 72, 24, 48)$$, 'ADN_PLANTILLA_DE_OTRA_IGLESIA', 'no se copia (ni existe) un método de otra iglesia como origen');
-- Editar: solo las columnas de contenido
update public.adn_seguimiento_metodos set nombre = 'Mi método v2', primer_contacto_horas = 10 where id = 'b1a30000-0000-0000-0000-0000000000a1';
select pg_temp.igual((select nombre || ':' || primer_contacto_horas from public.adn_seguimiento_metodos where id = 'b1a30000-0000-0000-0000-0000000000a1'), 'Mi método v2:10', 'A edita nombre y objetivo de su método');
select pg_temp.falla($$update public.adn_seguimiento_metodos set iglesia_id = 'b1a10000-0000-0000-0000-00000000000b' where id = 'b1a30000-0000-0000-0000-0000000000a1'$$, '42501', 'no se cambia la iglesia de un método');
select pg_temp.falla($$update public.adn_seguimiento_metodos set plantilla_origen = null where id = 'b1a30000-0000-0000-0000-0000000000a1'$$, '42501', 'ni su plantilla de origen');
select pg_temp.falla($$update public.adn_seguimiento_metodos set clave = 'otra' where id = 'b1a30000-0000-0000-0000-0000000000a1'$$, '42501', 'ni su clave');
select pg_temp.igual(pg_temp.filas($$update public.adn_seguimiento_metodos set plazo_horas = 1, umbral_amarillo_horas = 1, umbral_naranja_horas = 1 where id = '5e000000-0000-4000-8000-000000000072'$$), '0', 'las plantillas de plataforma no se editan (ninguna fila cambia)');
select pg_temp.igual(pg_temp.filas($$update public.adn_seguimiento_metodos set archivado_en = now() where id = '5e000000-0000-4000-8000-000000000001'$$), '0', 'ni se archivan');
select pg_temp.falla($$delete from public.adn_seguimiento_metodos where id = 'b1a30000-0000-0000-0000-0000000000a1'$$, '42501', 'nada se borra: se archiva');
select pg_temp.falla($$update public.adn_seguimiento_metodos set plazo_horas = 10 where id = 'b1a30000-0000-0000-0000-0000000000a1'$$, '23514', 'editar con valores incoherentes (plazo 10 con colores a 30 y 60) se rechaza');
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_metodos where iglesia_id is null), '2', 'las dos plantillas siguen intactas');
reset role;
select pg_temp.igual((select plazo_horas || ':' || umbral_amarillo_horas || ':' || umbral_naranja_horas from public.adn_seguimiento_metodos where id = '5e000000-0000-4000-8000-000000000072'), '72:24:48', 'OP72 conserva 72, 24 y 48 tras los intentos de cambiarla');

-- 3. Quien no tiene permiso de configuración (colaborador de A) no escribe nada
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000002', true);
set local role authenticated;
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000a', 'colab', 'X', 1, 72, 24, 48)$$, '42501', 'un colaborador no crea métodos');
select pg_temp.igual(pg_temp.filas($$update public.adn_seguimiento_metodos set nombre = 'Hackeado' where id = 'b1a30000-0000-0000-0000-0000000000a1'$$), '0', 'ni edita los de su iglesia');
select pg_temp.falla($$insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('b1a10000-0000-0000-0000-00000000000a', '5e000000-0000-4000-8000-000000000001')$$, '42501', 'ni elige el método activo');
select pg_temp.igual((select (public.adn_seguimiento_en_uso('5e000000-0000-4000-8000-000000000072') is null)::text), 'true', 'ni consulta cuántos procesos usan un método');
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_metodos where clave = 'propio_a1'), '1', 'pero sí lee los métodos de su iglesia');
reset role;

-- 4. La otra iglesia (B, Premium) no ve ni toca lo de A
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000003', true);
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_metodos where clave = 'propio_a1'), '0', 'B no ve el método de A');
select pg_temp.igual(pg_temp.filas($$update public.adn_seguimiento_metodos set nombre = 'De B' where id = 'b1a30000-0000-0000-0000-0000000000a1'$$), '0', 'B no edita el método de A');
select pg_temp.falla($$insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('b1a10000-0000-0000-0000-00000000000b', 'b1a30000-0000-0000-0000-0000000000a1')$$, 'ADN_METODO_DE_OTRA_IGLESIA', 'B no elige el método de A como activo');
select pg_temp.falla($$insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('b1a10000-0000-0000-0000-00000000000a', '5e000000-0000-4000-8000-000000000001')$$, '42501', 'B no cambia la configuración de A');
select pg_temp.igual((select public.adn_seguimiento_en_uso('b1a30000-0000-0000-0000-0000000000a1')::text), '{"total": 0, "abiertos": 0}', 'B pregunta por un método de A y solo cuenta lo suyo (cero)');
-- B crea el suyo con la misma clave que usó A: cada iglesia tiene su propio espacio de claves
insert into public.adn_seguimiento_metodos (id, iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas)
  values ('b1a30000-0000-0000-0000-0000000000b1', 'b1a10000-0000-0000-0000-00000000000b', 'propio_a1', 'De B', 1, 48, 12, 24);
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_metodos where clave = 'propio_a1'), '1', 'B crea el suyo con la misma clave y solo ve el suyo');
reset role;

-- 5. La iglesia sin el módulo (C, Semilla): elige plantillas, pero no crea ni elige métodos propios
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000c', 'propio', 'X', 1, 72, 24, 48)$$, '42501', 'sin el módulo no se crea un método propio');
insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('b1a10000-0000-0000-0000-00000000000c', '5e000000-0000-4000-8000-000000000001');
select pg_temp.igual((select metodo_id::text from public.adn_seguimiento_config), '5e000000-0000-4000-8000-000000000001', 'pero sí elige la plantilla Seguimiento simple');
update public.adn_seguimiento_config set metodo_id = '5e000000-0000-4000-8000-000000000072';
select pg_temp.igual((select metodo_id::text from public.adn_seguimiento_config), '5e000000-0000-4000-8000-000000000072', 'y vuelve a OP72');
update public.adn_seguimiento_config set metodo_id = '5e000000-0000-4000-8000-000000000001';
select pg_temp.falla($$update public.adn_seguimiento_config set metodo_id = 'b1a30000-0000-0000-0000-0000000000a1'$$, 'ADN_METODO_DE_OTRA_IGLESIA', 'no apunta al método de otra iglesia');
reset role;
-- Un método propio que quedó en C de cuando tuvo el módulo (lo crea el servidor) no se puede elegir sin el módulo
insert into public.adn_seguimiento_metodos (id, iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas)
  values ('b1a30000-0000-0000-0000-0000000000c1', 'b1a10000-0000-0000-0000-00000000000c', 'antiguo', 'Antiguo de C', 1, 48, 12, 24);
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000004', true);
set local role authenticated;
select pg_temp.falla($$update public.adn_seguimiento_config set metodo_id = 'b1a30000-0000-0000-0000-0000000000c1'$$, '42501', 'ni lo elige: sin el módulo solo se eligen plantillas');
select pg_temp.igual(pg_temp.filas($$update public.adn_seguimiento_metodos set nombre = 'Editado sin módulo' where id = 'b1a30000-0000-0000-0000-0000000000c1'$$), '0', 'ni lo edita');
reset role;

-- 6. Elegir el método activo y que los procesos nuevos lo tomen
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('b1a10000-0000-0000-0000-00000000000a', 'b1a30000-0000-0000-0000-0000000000a1');
select pg_temp.igual((select metodo_id::text from public.adn_seguimiento_config), 'b1a30000-0000-0000-0000-0000000000a1', 'A elige su método propio como activo');
reset role;
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion) values
  ('b1a40000-0000-0000-0000-0000000000a1', 'b1a10000-0000-0000-0000-00000000000a', 'b1a20000-0000-0000-0000-0000000000a1', now() - interval '10 hours'),
  ('b1a40000-0000-0000-0000-0000000000b1', 'b1a10000-0000-0000-0000-00000000000b', 'b1a20000-0000-0000-0000-0000000000b1', now() - interval '10 hours'),
  ('b1a40000-0000-0000-0000-0000000000c1', 'b1a10000-0000-0000-0000-00000000000c', 'b1a20000-0000-0000-0000-0000000000c1', now() - interval '10 hours');
select pg_temp.igual((select metodo_id::text || '/' || (fecha_limite = fecha_conversion + interval '96 hours')::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a1'), 'b1a30000-0000-0000-0000-0000000000a1/true', 'un proceso nuevo de A toma su método activo y su plazo de 96 horas');
select pg_temp.igual((select metodo_id::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000b1'), '5e000000-0000-4000-8000-000000000072', 'uno de B, que no eligió nada, nace con OP72');
select pg_temp.igual((select metodo_id::text || '/' || (fecha_limite = fecha_conversion + interval '168 hours')::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000c1'), '5e000000-0000-4000-8000-000000000001/true', 'uno de C nace con Seguimiento simple y su plazo de 168 horas');
-- Un método dado a mano en la inserción se respeta
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion, metodo_id) values
  ('b1a40000-0000-0000-0000-0000000000a2', 'b1a10000-0000-0000-0000-00000000000a', 'b1a20000-0000-0000-0000-0000000000a1', now() - interval '10 hours', '5e000000-0000-4000-8000-000000000001');
select pg_temp.igual((select metodo_id::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a2'), '5e000000-0000-4000-8000-000000000001', 'si se da a mano un método distinto de OP72 al crear el proceso, se respeta');
-- Una carga sin disparadores (restauración) conserva lo que trae, incluido OP72 en una iglesia que usa otro método
set local session_replication_role = replica;
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion, metodo_id, fecha_limite, estado_alerta, completado) values
  ('b1a40000-0000-0000-0000-0000000000a5', 'b1a10000-0000-0000-0000-00000000000a', 'b1a20000-0000-0000-0000-0000000000a1', now() - interval '10 hours', '5e000000-0000-4000-8000-000000000072', now() + interval '62 hours', 'verde', false);
reset session_replication_role;
select pg_temp.igual((select metodo_id::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a5'), '5e000000-0000-4000-8000-000000000072', 'una carga sin disparadores (restauración) conserva OP72 aunque la iglesia use otro método');
delete from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a5';
-- Cambiar el activo no toca los procesos abiertos
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.adn_seguimiento_config set metodo_id = '5e000000-0000-4000-8000-000000000001';
reset role;
select pg_temp.igual((select metodo_id::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a1'), 'b1a30000-0000-0000-0000-0000000000a1', 'cambiar el método activo no cambia el de los procesos ya abiertos');
update public.adn_seguimiento_config set updated_at = timestamptz '2020-01-01 00:00+00' where iglesia_id = 'b1a10000-0000-0000-0000-00000000000a';
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.adn_seguimiento_config set metodo_id = '5e000000-0000-4000-8000-000000000072';
reset role;
select pg_temp.igual((select (updated_at > timestamptz '2020-01-01')::text from public.adn_seguimiento_config where iglesia_id = 'b1a10000-0000-0000-0000-00000000000a'), 'true', 'la configuración guarda la fecha del cambio');

-- 7. Archivar: el método activo no se archiva; uno archivado no se elige
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.adn_seguimiento_config set metodo_id = 'b1a30000-0000-0000-0000-0000000000a1';
select pg_temp.falla($$update public.adn_seguimiento_metodos set archivado_en = now() where id = 'b1a30000-0000-0000-0000-0000000000a1'$$, 'ADN_METODO_ACTIVO', 'el método activo no se archiva');
update public.adn_seguimiento_config set metodo_id = '5e000000-0000-4000-8000-000000000072';
update public.adn_seguimiento_metodos set archivado_en = now() where id = 'b1a30000-0000-0000-0000-0000000000a1';
select pg_temp.igual((select (archivado_en is not null)::text from public.adn_seguimiento_metodos where id = 'b1a30000-0000-0000-0000-0000000000a1'), 'true', 'tras elegir otro, se archiva');
select pg_temp.falla($$update public.adn_seguimiento_config set metodo_id = 'b1a30000-0000-0000-0000-0000000000a1'$$, 'ADN_METODO_ARCHIVADO', 'un método archivado no se elige');
reset role;
select pg_temp.igual((select metodo_id::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a1'), 'b1a30000-0000-0000-0000-0000000000a1', 'los procesos abiertos conservan el método archivado');
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.adn_seguimiento_metodos set archivado_en = null where id = 'b1a30000-0000-0000-0000-0000000000a1';
reset role;

-- 8. Editar plazos recalcula la fecha límite y el color de los procesos abiertos, no los completados
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion, metodo_id, completado) values
  ('b1a40000-0000-0000-0000-0000000000a3', 'b1a10000-0000-0000-0000-00000000000a', 'b1a20000-0000-0000-0000-0000000000a1', now() - interval '100 hours', 'b1a30000-0000-0000-0000-0000000000a1', false),
  ('b1a40000-0000-0000-0000-0000000000a4', 'b1a10000-0000-0000-0000-00000000000a', 'b1a20000-0000-0000-0000-0000000000a1', now() - interval '100 hours', 'b1a30000-0000-0000-0000-0000000000a1', true);
select pg_temp.igual((select estado_alerta from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a3'), 'rojo', 'con 96 horas de plazo, un proceso de 100 horas está en rojo');
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
select pg_temp.igual(public.adn_seguimiento_en_uso('b1a30000-0000-0000-0000-0000000000a1')::text, '{"total": 3, "abiertos": 2}', 'antes de guardar se ve cuántos procesos usan el método (3, dos abiertos)');
update public.adn_seguimiento_metodos set plazo_horas = 200, umbral_amarillo_horas = 50, umbral_naranja_horas = 150 where id = 'b1a30000-0000-0000-0000-0000000000a1';
reset role;
select pg_temp.igual((select (fecha_limite = fecha_conversion + interval '200 hours')::text || '/' || estado_alerta from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a3'), 'true/amarillo', 'el proceso abierto recalcula su fecha límite a 200 horas y su color (100 horas con colores a 50 y 150 es amarillo)');
select pg_temp.igual((select (fecha_limite = fecha_conversion + interval '96 hours')::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a4'), 'true', 'el proceso completado conserva su fecha límite');
select pg_temp.igual((select (fecha_limite = fecha_conversion + interval '168 hours')::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a2'), 'true', 'y los procesos de otros métodos no cambian');
-- Cambiar solo el nombre no recalcula nada
update public.consolidaciones set fecha_limite = fecha_conversion + interval '1 hour' where id = 'b1a40000-0000-0000-0000-0000000000a3';
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000001', true);
set local role authenticated;
update public.adn_seguimiento_metodos set nombre = 'Solo nombre' where id = 'b1a30000-0000-0000-0000-0000000000a1';
reset role;
select pg_temp.igual((select (fecha_limite = fecha_conversion + interval '1 hour')::text from public.consolidaciones where id = 'b1a40000-0000-0000-0000-0000000000a3'), 'true', 'cambiar solo el nombre no toca los procesos');

-- 9. Límite de diez métodos propios sin archivar por iglesia
select set_config('request.jwt.claim.sub', 'b1a00000-0000-0000-0000-000000000003', true);
set local role authenticated;
do $$ begin
  for i in 1..8 loop
    insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas)
      values ('b1a10000-0000-0000-0000-00000000000b', 'm' || i, 'M' || i, 1, 72, 24, 48);
  end loop;
end $$;
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_metodos where iglesia_id = 'b1a10000-0000-0000-0000-00000000000b'), '10', 'B llega a diez métodos propios');
select pg_temp.falla($$insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000b', 'm10', 'M10', 1, 72, 24, 48)$$, 'ADN_DEMASIADOS_METODOS', 'el undécimo se rechaza');
update public.adn_seguimiento_metodos set archivado_en = now() where clave = 'm1' and iglesia_id = 'b1a10000-0000-0000-0000-00000000000b';
insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('b1a10000-0000-0000-0000-00000000000b', 'm10', 'M10', 1, 72, 24, 48);
select pg_temp.igual((select count(*)::text from public.adn_seguimiento_metodos where iglesia_id = 'b1a10000-0000-0000-0000-00000000000b' and archivado_en is null), '10', 'al archivar uno se libera un hueco');
reset role;

-- 10. Sin sesión no se escribe ni se consulta nada
set local role anon;
select pg_temp.falla($$insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('b1a10000-0000-0000-0000-00000000000a', '5e000000-0000-4000-8000-000000000001')$$, '42501', 'sin sesión no se elige método');
select pg_temp.falla($$select public.adn_seguimiento_en_uso('5e000000-0000-4000-8000-000000000072')$$, '42501', 'ni se consulta el uso de un método');
reset role;
rollback;
