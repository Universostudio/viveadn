-- Origen: supabase/seeds/sembrar_iglesias_prueba.sql, sha256 92c36e0bf00a
-- Vive ADN: siembra de iglesias de PRUEBA con datos 100 % sintéticos. Solo para un proyecto de pruebas. Es de un solo uso y no necesita psql.
--
-- Qué crea (cuatro iglesias lógicas, seis filas en `iglesias` porque la mega tiene dos sedes):
--   1. Mega, plan Premium, con sedes: prueba-mega (madre) y sus dos sedes prueba-mega-norte y prueba-mega-sur.
--   2. Mediana, plan Básico: prueba-mediana.
--   3. Individual, plan Semilla: prueba-pequena (dentro del tope de 50 personas del plan).
--   4. Individual en periodo de prueba (etapa «prueba», 14 días), en modo alias: prueba-en-prueba.
-- Cada iglesia lleva zonas, casas de oración, personas, seguimientos recientes (con algunos en rojo), asistencia de las últimas
-- cuatro semanas y eventos próximos. Más de 500 personas en total.
--
-- Qué NO hace:
--   * No crea usuarios ni perfiles (no toca auth): para entrar como propietario, Gerencia crea la cuenta desde el Panel Maestro.
--   * No crea consentimientos: nadie queda suscrito a ningún canal, así que ningún envío podría llegar a estas personas aunque se encendiera.
--   * No envía nada ni llama a ningún servicio.
--
-- Datos sintéticos, no reales [H]: no se ha localizado el archivo de usuarios de OP72, así que NO se copia nada de él. La iglesia en prueba usa
-- el modo alias (alias, teléfono y fecha, sin apellido ni correo) porque es lo que se supone que tiene la forma de ese archivo; es una suposición.
--
-- Contactos enmascarados: todos los correos terminan en @demo.invalid (dominio reservado, no existe) y todos los teléfonos empiezan por +999
-- (prefijo internacional no asignado): no pertenecen a nadie. Cada persona lleva en notas «Dato sintético de demostración (siembra)» y cada
-- iglesia está marcada como demo (iglesias.es_demo).
--
-- Se niega a ejecutarse si ya existe alguna de las seis direcciones. Para volver a empezar, la plataforma borra las iglesias demo desde su panel.
set search_path = public, extensions;

create or replace function pg_temp.adn_sembrar(
  p_slug text, p_nombre text, p_plan text, p_etapa text, p_alias boolean, p_madre text, p_ciudad text,
  p_zonas int, p_casas int, p_personas int, p_recientes int, p_rojos int, p_idx int
) returns text language plpgsql as $f$
declare
  v_ig uuid; v_madre uuid;
  nombres text[] := array['Lucía','Pablo','Marta','Andrés','Sara','Jorge','Elena','Daniel','Camila','Mateo','Valentina','Samuel','Isabela','David','Ruth','Esteban','Noemí','Gabriel','Abigail','Tomás','Sofía','Joel','Mariana','Isaac','Paula','Caleb','Débora','Nicolás','Raquel','Efraín','Julia','Adrián','Clara','Rubén','Ester','Óscar','Irene','Félix','Lidia','Hugo'];
  apellidos text[] := array['Romero','Cano','Gil','Vela','Molina','Peña','Ruiz','Herrera','Soto','Navarro','Vargas','Ortiz','Castro','Mejía','Rojas','Prieto','Cortés','Lara','Quintero','Salas','Duarte','Fuentes','Blanco','Moya','Pardo','Ibáñez','Arias','Campos','León','Sáez'];
  alias_base text[] := array['Roble','Cedro','Olivo','Pino','Sauce','Encina','Nogal','Fresno'];
  niveles text[] := array['nuevo','nuevo','en_crecimiento','en_crecimiento','maduro','lider'];
  zonas uuid[] := '{}'; casas uuid[] := '{}'; z uuid; c uuid; m uuid; i int; h int; horas int; w int;
  n_cons int := 0;
begin
  if exists (select 1 from public.iglesias where slug = p_slug) then raise exception 'Ya existe la iglesia %: esta siembra es de un solo uso', p_slug; end if;
  if p_madre is not null then
    select id into v_madre from public.iglesias where slug = p_madre;
    if v_madre is null then raise exception 'No existe la iglesia madre %', p_madre; end if;
  end if;
  insert into public.iglesias (nombre, slug, pais, ciudad, plan, etapa, es_demo, modo_alias, iglesia_madre_id, prueba_hasta, email_contacto)
  values (p_nombre, p_slug, 'España', p_ciudad, p_plan, p_etapa, true, p_alias, v_madre,
          case when p_etapa = 'prueba' then now() + interval '14 days' end, 'contacto@demo.invalid')
  returning id into v_ig;

  for i in 1..p_zonas loop
    z := gen_random_uuid(); zonas := zonas || z;
    insert into public.zonas (id, iglesia_id, codigo, nombre) values (z, v_ig, 'Z' || i, 'Zona ' || i);
  end loop;
  for i in 1..p_casas loop
    c := gen_random_uuid(); casas := casas || c;
    insert into public.casas_oracion (id, iglesia_id, zona_id, codigo_zona, nombre, pais, estado, ciudad, sector, direccion)
    values (c, v_ig, zonas[1 + (i - 1) % p_zonas], (array['MG','MN','MS','MD','PQ','PR'])[p_idx] || '-' || lpad(i::text, 6, '0'),
            'Casa de Oración ' || i, 'España', 'Andalucía', p_ciudad, 'Sector ' || i, 'Dirección de ejemplo ' || i);
  end loop;

  for i in 1..p_personas loop
    m := gen_random_uuid();
    -- Una de cada diez personas aún no tiene casa asignada
    h := case when random() < 0.1 then null else 1 + floor(random() * p_casas)::int end;
    insert into public.miembros (id, iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, nivel_compromiso, fecha_conversion, bautizado,
                                 nivel_formacion, progreso_formacion, puntos, racha_dias, activo, notas)
    values (m, v_ig,
            case when p_alias then alias_base[1 + (i - 1) % 8] || '-' || lpad(i::text, 3, '0') else nombres[1 + floor(random() * 40)::int] end,
            case when p_alias then '' else apellidos[1 + floor(random() * 30)::int] || ' ' || apellidos[1 + floor(random() * 30)::int] end,
            case when p_alias then null else 'demo' || p_idx || '-' || i || '@demo.invalid' end,
            '+999 ' || lpad(p_idx::text, 2, '0') || lpad(i::text, 5, '0'),
            case when h is null then null else casas[h] end,
            niveles[1 + floor(random() * 6)::int], current_date - (floor(random() * 900))::int, random() < 0.6,
            1 + floor(random() * 5)::int, floor(random() * 101)::int, floor(random() * 800)::int, floor(random() * 30)::int, true,
            'Dato sintético de demostración (siembra)');
    if i > p_personas - p_recientes then
      -- Seguimientos recientes: los primeros pasan de 72 h (rojo); el resto se reparte entre verde, amarillo y naranja
      horas := case when i - (p_personas - p_recientes) <= p_rojos then 76 + floor(random() * 60)::int else 1 + floor(random() * 71)::int end;
      update public.miembros set nivel_compromiso = 'nuevo', fecha_conversion = current_date where id = m;
      insert into public.consolidaciones (iglesia_id, miembro_id, casa_oracion_id, fecha_conversion)
      values (v_ig, m, case when h is null then null else casas[h] end, now() - (horas || ' hours')::interval);
      n_cons := n_cons + 1;
    end if;
  end loop;

  -- Asistencia de las últimas cuatro semanas en las casas: algo menos de dos tercios de la gente viene cada semana
  insert into public.asistencias (iglesia_id, casa_oracion_id, miembro_id, fecha, presente)
  select mb.iglesia_id, mb.casa_oracion_id, mb.id, current_date - (s * 7), random() < 0.65
    from public.miembros mb, generate_series(0, 3) s
   where mb.iglesia_id = v_ig and mb.casa_oracion_id is not null and mb.activo;

  -- Eventos próximos para que el panel de inicio y la agenda no estén vacíos
  insert into public.eventos (iglesia_id, titulo, tipo, inicia_en, termina_en, lugar, descripcion) values
    (v_ig, 'Culto de domingo', 'culto', date_trunc('day', now()) + interval '3 days 10 hours', date_trunc('day', now()) + interval '3 days 12 hours', 'Templo principal', 'Evento sintético de demostración'),
    (v_ig, 'Casas de oración de la semana', 'casa_oracion', date_trunc('day', now()) + interval '5 days 19 hours', null, 'En cada casa', 'Evento sintético de demostración'),
    (v_ig, 'Taller de formación', 'formacion', date_trunc('day', now()) + interval '9 days 18 hours', date_trunc('day', now()) + interval '9 days 20 hours', 'Sala 2', 'Evento sintético de demostración');

  return format('%s: plan %s, etapa %s%s, %s zonas, %s casas, %s personas, %s seguimientos (%s en rojo)',
                p_slug, p_plan, p_etapa, case when p_alias then ', modo alias' else '' end, p_zonas, p_casas, p_personas, n_cons, p_rojos);
end $f$;

do $$
declare r text; slugs text[] := array['prueba-mega', 'prueba-mega-norte', 'prueba-mega-sur', 'prueba-mediana', 'prueba-pequena', 'prueba-en-prueba'];
begin
  if exists (select 1 from public.iglesias where slug = any (slugs)) then
    raise exception 'Alguna de las iglesias de prueba ya existe (%): esta siembra es de un solo uso', (select string_agg(slug, ', ') from public.iglesias where slug = any (slugs));
  end if;
  perform setseed(0.37);
  --                                  slug                 nombre                               plan       etapa    alias  madre         ciudad     zonas casas pers. rec. rojos idx
  raise notice '%', pg_temp.adn_sembrar('prueba-mega',        'Iglesia Mega (prueba)',             'premium', 'activa', false, null,         'Sevilla',   8,   32,  220,  30,   4,    1);
  raise notice '%', pg_temp.adn_sembrar('prueba-mega-norte',  'Iglesia Mega, sede Norte (prueba)', 'premium', 'activa', false, 'prueba-mega', 'Sevilla',   2,    6,   60,   8,   1,    2);
  raise notice '%', pg_temp.adn_sembrar('prueba-mega-sur',    'Iglesia Mega, sede Sur (prueba)',   'premium', 'activa', false, 'prueba-mega', 'Cádiz',     2,    6,   55,   7,   1,    3);
  raise notice '%', pg_temp.adn_sembrar('prueba-mediana',     'Iglesia Mediana (prueba)',          'basico',  'activa', false, null,         'Málaga',    4,   12,  120,  14,   2,    4);
  raise notice '%', pg_temp.adn_sembrar('prueba-pequena',     'Iglesia Pequeña (prueba)',          'semilla', 'activa', false, null,         'Huelva',    1,    4,   45,   6,   1,    5);
  raise notice '%', pg_temp.adn_sembrar('prueba-en-prueba',   'Iglesia en periodo de prueba',      'semilla', 'prueba', true,  null,         'Córdoba',   1,    3,   30,   5,   1,    6);
end $$;

-- Resumen visible en el editor SQL: una fila por iglesia
select i.slug, i.plan, i.etapa, i.es_demo, i.modo_alias, m.slug as madre,
       (select count(*) from public.zonas z where z.iglesia_id = i.id) as zonas,
       (select count(*) from public.casas_oracion c where c.iglesia_id = i.id) as casas,
       (select count(*) from public.miembros x where x.iglesia_id = i.id) as personas,
       (select count(*) from public.consolidaciones k where k.iglesia_id = i.id) as seguimientos
  from public.iglesias i left join public.iglesias m on m.id = i.iglesia_madre_id
 where i.slug like 'prueba-%' order by i.slug;
