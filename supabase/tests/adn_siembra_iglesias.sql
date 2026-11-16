-- Siembra de la estructura de iglesias de prueba (supabase/seeds/sembrar_iglesias_prueba.sql): qué crea, que respeta los planes, que los contactos
-- están enmascarados, que nadie queda suscrito, que adopta una iglesia existente sin tocar sus personas, el gancho de líderes y que es de un solo uso.
-- Cada escenario ocurre dentro de una transacción que se deshace.
\set ON_ERROR_STOP on
-- ========== Escenario 1: la mega no existe, se crea ==========
begin;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm not like '%' || texto || '%' then raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm; end if;
    raise notice 'OK: % (%)', msg, left(sqlerrm, 90); return;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
\i seeds/sembrar_iglesias_prueba.sql

select pg_temp.igual((select count(*)::text from public.iglesias where es_demo and slug in ('casa-reino', 'casa-reino-norte', 'casa-reino-sur', 'prueba-mediana', 'prueba-pequena', 'prueba-en-prueba')), '6', 'seis filas de iglesias, todas marcadas como demo');
select pg_temp.igual((select count(*)::text from public.iglesias where iglesia_madre_id is null and slug in ('casa-reino', 'prueba-mediana', 'prueba-pequena', 'prueba-en-prueba')), '4', 'cuatro iglesias lógicas: la mega y sus sedes cuentan como una');
select pg_temp.igual((select string_agg(s.slug, ',' order by s.slug) from public.iglesias s join public.iglesias m on m.id = s.iglesia_madre_id where m.slug = 'casa-reino'), 'casa-reino-norte,casa-reino-sur', 'la mega tiene dos sedes');
select pg_temp.igual((select string_agg(slug || ':' || plan || ':' || etapa, ',' order by slug) from public.iglesias where es_demo),
  'casa-reino:premium:activa,casa-reino-norte:premium:activa,casa-reino-sur:premium:activa,prueba-en-prueba:semilla:prueba,prueba-mediana:basico:activa,prueba-pequena:semilla:activa', 'planes y etapas: mega Premium, mediana Básico, pequeña Semilla y una en prueba');
select pg_temp.igual((select (prueba_hasta between now() + interval '13 days' and now() + interval '15 days')::text from public.iglesias where slug = 'prueba-en-prueba'), 'true', 'la iglesia en prueba tiene su periodo de unos 14 días');
select pg_temp.igual((select count(*)::text from public.iglesias where es_demo and modo_alias), '1', 'solo la iglesia en prueba usa el modo alias');
-- Estructura
select pg_temp.igual((select string_agg(i.slug || '=' || z || '/' || c, ',' order by i.slug) from public.iglesias i,
   lateral (select (select count(*) from public.zonas where iglesia_id = i.id) z, (select count(*) from public.casas_oracion where iglesia_id = i.id) c) x where i.es_demo),
  'casa-reino=3/9,casa-reino-norte=1/3,casa-reino-sur=1/3,prueba-en-prueba=1/2,prueba-mediana=2/6,prueba-pequena=1/3', 'zonas y casas por iglesia');
select pg_temp.igual((select count(*)::text from public.casas_oracion c join public.zonas z on z.id = c.zona_id where z.iglesia_id <> c.iglesia_id), '0', 'cada casa está en una zona de su propia iglesia');
select pg_temp.igual((select count(*)::text from public.casas_oracion c join public.iglesias i on i.id = c.iglesia_id where i.es_demo and c.codigo_zona !~ '^[A-Z]{2}-[0-9]{6}$'), '0', 'los códigos de casa tienen la forma de siempre');
-- Pocas personas sintéticas
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo), '36', 'solo 36 personas sintéticas: seis por iglesia, no cientos');
select pg_temp.igual((select (min(n) = 6 and max(n) = 6)::text from (select count(*) n from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo group by i.id) x), 'true', 'seis en cada una');
select pg_temp.igual((select count(*)::text from public.miembros m join public.casas_oracion c on c.id = m.casa_oracion_id where c.iglesia_id <> m.iglesia_id), '0', 'nadie está en una casa de otra iglesia');
-- Contactos enmascarados y marca
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo and m.email is not null and m.email !~ '@demo[.]invalid$'), '0', 'ningún correo es real: todos terminan en @demo.invalid');
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo and (m.telefono is null or m.telefono !~ '^[+]999 [0-9]{7}$')), '0', 'ningún teléfono es marcable: todos empiezan por +999, un prefijo no asignado');
select pg_temp.igual((select count(distinct m.telefono)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo), '36', 'cada persona tiene su propio teléfono sintético');
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo and m.notas is distinct from 'Dato sintético de demostración (siembra)'), '0', 'cada persona lleva la marca de dato sintético');
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug = 'prueba-en-prueba' and (m.apellido <> '' or m.email is not null or m.nombre !~ '^[A-Za-z]+-[0-9]{3}$')), '0', 'en modo alias hay alias, sin apellido ni correo');
-- Nadie suscrito, sin perfiles
select pg_temp.igual((select count(*)::text from public.adn_consentimientos k join public.iglesias i on i.id = k.iglesia_id where i.es_demo), '0', 'ningún consentimiento de comunicación: nadie está suscrito a ningún canal');
select pg_temp.igual((select count(*)::text from public.perfiles p join public.iglesias i on i.id = p.iglesia_id where i.es_demo), '0', 'no crea perfiles ni usuarios');
-- Seguimientos
select pg_temp.igual((select string_agg(i.slug || '=' || n || '/' || rojos, ',' order by i.slug) from public.iglesias i,
    lateral (select count(*) n, count(*) filter (where k.fecha_conversion < now() - interval '72 hours') rojos from public.consolidaciones k where k.iglesia_id = i.id) x where i.es_demo),
  'casa-reino=2/1,casa-reino-norte=2/1,casa-reino-sur=2/1,prueba-en-prueba=2/1,prueba-mediana=2/1,prueba-pequena=2/1', 'dos seguimientos por iglesia y uno pasa de 72 horas');
-- Asistencia y eventos
select pg_temp.igual((select count(distinct fecha)::text from public.asistencias a join public.iglesias i on i.id = a.iglesia_id where i.slug = 'casa-reino'), '4', 'asistencia de cuatro semanas');
select pg_temp.igual((select (min(n) = 3 and max(n) = 3)::text from (select count(*) n from public.eventos e join public.iglesias i on i.id = e.iglesia_id where i.es_demo group by i.id) x), 'true', 'tres eventos próximos en cada iglesia');
-- De un solo uso
select pg_temp.falla($$select pg_temp.adn_sembrar('casa-reino', 'Otra', 'premium', 'activa', false, null, 'Sevilla', 1, 1, 1, 1, 0, 1, true)$$, 'ya tiene zonas o casas', 'la mega ya sembrada no se siembra otra vez');
select pg_temp.falla($$select pg_temp.adn_sembrar('prueba-mediana', 'Otra', 'basico', 'activa', false, null, 'Sevilla', 1, 1, 1, 1, 0, 4)$$, 'un solo uso', 'una iglesia que no es la mega y ya existe no se adopta');
insert into public.iglesias (nombre, slug, pais, ciudad, plan, es_demo) values ('No demo', 'no-demo-x', 'ES', 'Sevilla', 'premium', false);
select pg_temp.falla($$select pg_temp.adn_sembrar('no-demo-x', 'x', 'premium', 'activa', false, null, 'Sevilla', 1, 1, 1, 1, 0, 1, true)$$, 'no está marcada como demostración', 'una iglesia real (no demo) nunca se siembra');
-- Gancho de líderes: con perfiles que ya existen
insert into auth.users (id) values ('af700000-0000-0000-0000-000000000001'), ('af700000-0000-0000-0000-000000000002');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) select 'af700000-0000-0000-0000-000000000001', id, 'Lider', 'Casa', 'lc@demo.invalid', 'lider_casa', true from public.iglesias where slug = 'casa-reino';
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) select 'af700000-0000-0000-0000-000000000002', id, 'Otro', 'Lider', 'ol@demo.invalid', 'lider_casa', true from public.iglesias where slug = 'prueba-mediana';
select pg_temp.adn_aplicar_lideres('[{"iglesia": "casa-reino", "casa": 2, "perfil": "af700000-0000-0000-0000-000000000001"}, {"iglesia": "casa-reino", "zona": 1, "perfil": "af700000-0000-0000-0000-000000000001"}]'::jsonb);
select pg_temp.igual((select count(*)::text from public.casas_oracion where lider_id = 'af700000-0000-0000-0000-000000000001' and codigo_zona = 'MG-000002'), '1', 'el gancho nombra al líder de la casa número 2');
select pg_temp.igual((select count(*)::text from public.zonas where lider_id = 'af700000-0000-0000-0000-000000000001' and codigo = 'Z1'), '1', 'y al de la zona número 1');
select pg_temp.falla($$select pg_temp.adn_aplicar_lideres('[{"iglesia": "casa-reino", "casa": 1, "perfil": "af700000-0000-0000-0000-000000000002"}]'::jsonb)$$, 'no existe o no es de la iglesia', 'un perfil de otra iglesia no se acepta como líder');
select pg_temp.falla($$select pg_temp.adn_aplicar_lideres('[{"iglesia": "casa-reino", "casa": 99, "perfil": "af700000-0000-0000-0000-000000000001"}]'::jsonb)$$, 'no tiene la casa número 99', 'una casa que no existe se dice');
select pg_temp.falla($$select pg_temp.adn_aplicar_lideres('[{"iglesia": "casa-reino", "perfil": "af700000-0000-0000-0000-000000000001"}]'::jsonb)$$, 'lleva «casa» o «zona»', 'un elemento sin casa ni zona se rechaza');
-- Quitar solo las personas sintéticas (las tres sentencias del final del script)
delete from public.asistencias where miembro_id in (select id from public.miembros where notas = 'Dato sintético de demostración (siembra)');
delete from public.consolidaciones where miembro_id in (select id from public.miembros where notas = 'Dato sintético de demostración (siembra)');
delete from public.miembros where notas = 'Dato sintético de demostración (siembra)';
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo), '0', 'las tres sentencias de limpieza quitan las 36 personas sintéticas');
select pg_temp.igual((select count(*)::text from public.casas_oracion c join public.iglesias i on i.id = c.iglesia_id where i.es_demo), '26', 'y la estructura se conserva (26 casas)');
rollback;

-- ========== Escenario 2: la mega ya existe (la creó el Panel Maestro) con una persona que no se toca ==========
begin;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan, es_demo) values ('af710000-0000-0000-0000-00000000000a', 'Casa Reino', 'casa-reino', 'ES', 'Sevilla', 'premium', true);
insert into public.miembros (iglesia_id, nombre, apellido, email, notas) values ('af710000-0000-0000-0000-00000000000a', 'Previa', 'Prueba', 'previa@demo.invalid', 'Cargada antes');
\i seeds/sembrar_iglesias_prueba.sql
select pg_temp.igual((select count(*)::text from public.iglesias where slug like 'casa-reino%'), '3', 'la mega existente no se duplica: solo se añaden sus dos sedes');
select pg_temp.igual((select nombre || '/' || plan from public.iglesias where slug = 'casa-reino'), 'Casa Reino/premium', 'su fila no se toca (nombre y plan siguen igual)');
select pg_temp.igual((select count(*) filter (where notas = 'Cargada antes')::text || '/' || count(*) from public.miembros where iglesia_id = 'af710000-0000-0000-0000-00000000000a'), '1/7', 'su persona cargada antes sigue ahí y se suman seis sintéticas');
select pg_temp.igual((select count(*)::text from public.zonas where iglesia_id = 'af710000-0000-0000-0000-00000000000a'), '3', 'la estructura se le añade');
rollback;
