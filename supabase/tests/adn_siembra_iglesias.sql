-- Siembra de iglesias de prueba (supabase/seeds/sembrar_iglesias_prueba.sql): qué crea, que respeta los planes, que los contactos están
-- enmascarados, que nadie queda suscrito a ningún canal y que es de un solo uso. Todo dentro de una transacción que se deshace.
\set ON_ERROR_STOP on
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
    raise notice 'OK: % (%)', msg, sqlerrm; return;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;

\i seeds/sembrar_iglesias_prueba.sql

-- 1. Qué crea
select pg_temp.igual((select count(*)::text from public.iglesias where slug like 'prueba-%' and es_demo), '6', 'seis filas de iglesias, todas marcadas como demo');
select pg_temp.igual((select count(*)::text from public.iglesias where slug like 'prueba-%' and iglesia_madre_id is null), '4', 'cuatro iglesias lógicas: la mega y sus sedes cuentan como una');
select pg_temp.igual((select string_agg(s.slug, ',' order by s.slug) from public.iglesias s join public.iglesias m on m.id = s.iglesia_madre_id where m.slug = 'prueba-mega'), 'prueba-mega-norte,prueba-mega-sur', 'la mega tiene dos sedes');
select pg_temp.igual((select string_agg(slug || ':' || plan || ':' || etapa, ',' order by slug) from public.iglesias where slug like 'prueba-%'),
  'prueba-en-prueba:semilla:prueba,prueba-mediana:basico:activa,prueba-mega:premium:activa,prueba-mega-norte:premium:activa,prueba-mega-sur:premium:activa,prueba-pequena:semilla:activa', 'planes y etapas: mega Premium, mediana Básico, pequeña Semilla y una en prueba');
select pg_temp.igual((select (prueba_hasta between now() + interval '13 days' and now() + interval '15 days')::text from public.iglesias where slug = 'prueba-en-prueba'), 'true', 'la iglesia en prueba tiene su periodo de unos 14 días');
select pg_temp.igual((select count(*)::text from public.iglesias where slug like 'prueba-%' and modo_alias), '1', 'solo la iglesia en prueba usa el modo alias');

-- 2. Personas
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug like 'prueba-%'), '530', 'más de 500 personas sintéticas en total');
select pg_temp.igual((select string_agg(i.slug || '=' || n, ',' order by i.slug) from public.iglesias i, lateral (select count(*) n from public.miembros m where m.iglesia_id = i.id) x where i.slug like 'prueba-%'),
  'prueba-en-prueba=30,prueba-mediana=120,prueba-mega=220,prueba-mega-norte=60,prueba-mega-sur=55,prueba-pequena=45', 'personas por iglesia');
select pg_temp.igual(((select count(*) from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug = 'prueba-pequena') <= 50)::text, 'true', 'la iglesia Semilla respeta el tope de 50 personas de su plan');
select pg_temp.igual((select count(*)::text from public.miembros m join public.casas_oracion c on c.id = m.casa_oracion_id where c.iglesia_id <> m.iglesia_id), '0', 'nadie está en una casa de otra iglesia');
select pg_temp.igual((select (count(*) filter (where casa_oracion_id is null) between 1 and 80)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug = 'prueba-mega'), 'true', 'hay personas sin casa, para ver ese caso');

-- 3. Contactos enmascarados y marca de demo
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug like 'prueba-%' and m.email is not null and m.email !~ '@demo[.]invalid$'), '0', 'ningún correo es real: todos terminan en @demo.invalid');
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug like 'prueba-%' and (m.telefono is null or m.telefono !~ '^[+]999 [0-9]{7}$')), '0', 'ningún teléfono es marcable: todos empiezan por +999, un prefijo no asignado');
select pg_temp.igual((select count(distinct m.telefono)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug like 'prueba-%'), '530', 'cada persona tiene su propio teléfono sintético');
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug like 'prueba-%' and m.notas is distinct from 'Dato sintético de demostración (siembra)'), '0', 'cada persona lleva la marca de dato sintético');
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug = 'prueba-en-prueba' and (m.apellido <> '' or m.email is not null)), '0', 'en modo alias no hay apellido ni correo');
select pg_temp.igual((select count(*)::text from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.slug = 'prueba-en-prueba' and m.nombre !~ '^[A-Za-z]+-[0-9]{3}$'), '0', 'en modo alias el nombre es un alias');
select pg_temp.igual((select count(*)::text from public.casas_oracion c join public.iglesias i on i.id = c.iglesia_id where i.slug like 'prueba-%' and c.codigo_zona !~ '^[A-Z]{2}-[0-9]{6}$'), '0', 'los códigos de casa tienen la forma de siempre');

-- 4. Nadie queda suscrito: ningún envío podría llegar a estas personas
select pg_temp.igual((select count(*)::text from public.adn_consentimientos k join public.iglesias i on i.id = k.iglesia_id where i.slug like 'prueba-%'), '0', 'ningún consentimiento de comunicación: nadie está suscrito a ningún canal');

-- 5. Seguimientos: los rojos exactos y el resto dentro de plazo
select pg_temp.igual((select string_agg(i.slug || '=' || n || '/' || rojos, ',' order by i.slug) from public.iglesias i,
    lateral (select count(*) n, count(*) filter (where k.fecha_conversion < now() - interval '72 hours') rojos from public.consolidaciones k where k.iglesia_id = i.id) x where i.slug like 'prueba-%'),
  'prueba-en-prueba=5/1,prueba-mediana=14/2,prueba-mega=30/4,prueba-mega-norte=8/1,prueba-mega-sur=7/1,prueba-pequena=6/1', 'seguimientos por iglesia y cuántos pasan de 72 horas');
select pg_temp.igual((select count(*)::text from public.consolidaciones k join public.iglesias i on i.id = k.iglesia_id where i.slug like 'prueba-%' and k.completado), '0', 'ninguno está completado');

-- 6. Asistencia y eventos
select pg_temp.igual((select count(distinct fecha)::text from public.asistencias a join public.iglesias i on i.id = a.iglesia_id where i.slug = 'prueba-mega'), '4', 'asistencia de cuatro semanas');
select pg_temp.igual((select (count(*) > 0)::text from public.asistencias a join public.iglesias i on i.id = a.iglesia_id where i.slug = 'prueba-en-prueba'), 'true', 'también en la iglesia en prueba');
select pg_temp.igual((select (min(n) = 3 and max(n) = 3)::text from (select count(*) n from public.eventos e join public.iglesias i on i.id = e.iglesia_id where i.slug like 'prueba-%' group by i.id) x), 'true', 'tres eventos próximos en cada iglesia');
select pg_temp.igual((select count(*)::text from public.eventos e join public.iglesias i on i.id = e.iglesia_id where i.slug like 'prueba-%' and e.inicia_en <= now()), '0', 'todos los eventos son futuros');

-- 7. No crea usuarios ni perfiles
select pg_temp.igual((select count(*)::text from public.perfiles p join public.iglesias i on i.id = p.iglesia_id where i.slug like 'prueba-%'), '0', 'no crea perfiles ni usuarios');

-- 8. De un solo uso
select pg_temp.falla($$select pg_temp.adn_sembrar('prueba-mega', 'Otra', 'premium', 'activa', false, null, 'Sevilla', 1, 1, 1, 1, 0, 1)$$, 'esta siembra es de un solo uso', 'repetir la siembra de una iglesia existente se niega');
rollback;
