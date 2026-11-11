-- Datos del panel de inicio, en una sola llamada. Reversion: supabase/reversiones/20261111170000_adn_panel_inicio.down.sql.
-- Solo lectura y con los permisos de quien llama: la seguridad por filas decide que cuenta, de modo que cada bloque
-- refleja lo que esa persona puede ver (un lider de casa ve a los miembros que le corresponden, no a toda la iglesia).
-- La web decide ademas que bloques mostrar segun los permisos del rol.
-- p_hoy fija el dia de referencia de las semanas y los cumpleaños; sirve para las pruebas (el 29 de febrero, el cambio de año).
create or replace function public.adn_panel_inicio(p_hoy date default null)
returns jsonb language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
declare
  hoy date := coalesce(p_hoy, (now() at time zone 'UTC')::date);
  lunes date := date_trunc('week', coalesce(p_hoy, (now() at time zone 'UTC')::date)::timestamp)::date;
begin
  return jsonb_build_object(
    'miembros', (select jsonb_build_object(
        'activos', count(*) filter (where activo),
        'nuevos_30d', count(*) filter (where created_at >= now() - interval '30 days'),
        'nuevos_30d_previos', count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days'),
        'sin_casa', count(*) filter (where activo and casa_oracion_id is null),
        'bautizados', count(*) filter (where activo and bautizado))
      from public.miembros),
    'asistencia', jsonb_build_object(
      'semana_actual', (select jsonb_build_object('semana', lunes, 'registros', count(*), 'presentes', count(*) filter (where presente))
                        from public.asistencias where fecha >= lunes and fecha < lunes + 7),
      'semana_anterior', (select jsonb_build_object('semana', lunes - 7, 'registros', count(*), 'presentes', count(*) filter (where presente))
                          from public.asistencias where fecha >= lunes - 7 and fecha < lunes),
      'serie', (select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'presentes', s.presentes) order by s.semana), '[]'::jsonb)
                from (select w::date as semana,
                             (select count(*) from public.asistencias a where a.presente and a.fecha >= w::date and a.fecha < w::date + 7) as presentes
                      from generate_series((lunes - 49)::timestamp, lunes::timestamp, interval '7 days') w) s)),
    'eventos_proximos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'tipo', e.tipo, 'inicia_en', e.inicia_en, 'lugar', e.lugar) order by e.inicia_en), '[]'::jsonb)
                         from (select id, titulo, tipo, inicia_en, lugar from public.eventos where not cancelado and inicia_en >= now() order by inicia_en limit 5) e),
    -- Cumpleaños de los proximos 14 dias. El 29 de febrero se celebra el ultimo dia de febrero en los años no bisiestos.
    'cumpleanos', (select coalesce(jsonb_agg(jsonb_build_object('nombre', c.nombre, 'apellido', c.apellido, 'fecha', c.prox, 'en_dias', c.prox - hoy) order by c.prox, c.nombre), '[]'::jsonb)
                   from (select m.nombre, m.apellido, f.prox
                         from public.miembros m
                         cross join lateral (
                           select min(x.d) as prox from (
                             select (make_date(y, extract(month from m.fecha_nacimiento)::int, 1)
                                     + (least(extract(day from m.fecha_nacimiento)::int,
                                              extract(day from (make_date(y, extract(month from m.fecha_nacimiento)::int, 1) + interval '1 month - 1 day'))::int) - 1))::date as d
                             from unnest(array[extract(year from hoy)::int, extract(year from hoy)::int + 1]) as t(y)
                           ) x where x.d >= hoy
                         ) f
                         where m.activo and m.fecha_nacimiento is not null and f.prox <= hoy + 14
                         order by f.prox, m.nombre limit 10) c),
    'formacion', jsonb_build_object(
      'en_curso', (select count(*) from public.inscripciones_formacion where estado = 'en_curso'),
      'completadas_mes', (select count(*) from public.inscripciones_formacion where completado_en >= date_trunc('month', now())),
      'certificados_mes', (select count(*) from public.certificados where emitido_en >= date_trunc('month', now()) and revocado_en is null)),
    'comunicacion', (select jsonb_build_object('mensajes_30d', count(*), 'enviados_30d', coalesce(sum(enviados), 0))
                     from public.adn_mensajes where created_at >= now() - interval '30 days'),
    'crecimiento', (select coalesce(jsonb_agg(jsonb_build_object('mes', g::date, 'nuevos',
                              (select count(*) from public.miembros where created_at >= g and created_at < g + interval '1 month')) order by g), '[]'::jsonb)
                    from generate_series(date_trunc('month', now()) - interval '5 months', date_trunc('month', now()), interval '1 month') g)
  );
end $$;
revoke all on function public.adn_panel_inicio(date) from public, anon;
grant execute on function public.adn_panel_inicio(date) to authenticated, service_role;
