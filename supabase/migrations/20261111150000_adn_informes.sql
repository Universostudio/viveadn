-- Datos de los informes en PDF y Excel (miembros, asistencia, crecimiento).
-- Reversion: supabase/reversiones/20261111150000_adn_informes.down.sql. Solo funciones de lectura.
--
-- Se ejecutan con los permisos de quien las llama: la seguridad por filas decide que filas cuentan, de modo que un
-- informe nunca incluye datos que esa persona no podria ver en pantalla. Ademas exigen el permiso del informe:
-- `miembros.exportar` (dato sensible) para el de miembros y `reportes.ver` para asistencia y crecimiento.

-- Crecimiento mes a mes de los ultimos p_meses meses (1 a 60), incluido el actual
create or replace function public.adn_informe_crecimiento(p_meses integer default 12)
returns table (mes date, nuevos_miembros bigint, miembros_acumulados bigint, conversiones bigint, bautizos bigint,
               consolidaciones_iniciadas bigint, consolidaciones_completadas bigint)
language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
begin
  if not (select private.tiene_permiso('reportes.ver')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_meses is null or p_meses < 1 or p_meses > 60 then raise exception 'ADN_PERIODO_INVALIDO'; end if;
  return query
  with meses as (
    select g::date as m
    from generate_series(date_trunc('month', now()) - make_interval(months => p_meses - 1), date_trunc('month', now()), interval '1 month') g
  )
  select ms.m,
    (select count(*) from public.miembros x where x.created_at >= ms.m and x.created_at < ms.m + interval '1 month'),
    (select count(*) from public.miembros x where x.created_at < ms.m + interval '1 month'),
    (select count(*) from public.miembros x where x.fecha_conversion >= ms.m and x.fecha_conversion < (ms.m + interval '1 month')::date),
    (select count(*) from public.miembros x where x.fecha_bautismo >= ms.m and x.fecha_bautismo < (ms.m + interval '1 month')::date),
    (select count(*) from public.consolidaciones c where c.fecha_conversion >= ms.m and c.fecha_conversion < ms.m + interval '1 month'),
    (select count(*) from public.consolidaciones c where c.completado_at >= ms.m and c.completado_at < ms.m + interval '1 month')
  from meses ms
  order by ms.m;
end $$;

-- Asistencia entre dos fechas (como maximo 366 dias): reuniones de casa por semana y por casa, y eventos
create or replace function public.adn_informe_asistencia(p_desde date, p_hasta date)
returns jsonb language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
declare
  semanal jsonb; por_casa jsonb; eventos jsonb;
  tot_casas record; tot_eventos record;
begin
  if not (select private.tiene_permiso('reportes.ver')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta or p_hasta - p_desde > 366 then raise exception 'ADN_PERIODO_INVALIDO'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'registros', s.registros, 'presentes', s.presentes) order by s.semana), '[]'::jsonb)
    into semanal
    from (select date_trunc('week', a.fecha)::date as semana, count(*) as registros, count(*) filter (where a.presente) as presentes
          from public.asistencias a where a.fecha between p_desde and p_hasta group by 1) s;

  select coalesce(jsonb_agg(jsonb_build_object('casa', c.nombre, 'registros', c.registros, 'presentes', c.presentes, 'personas', c.personas)
                            order by c.presentes desc, c.nombre), '[]'::jsonb)
    into por_casa
    from (select coalesce(h.nombre, h.codigo_zona, '') as nombre, count(*) as registros, count(*) filter (where a.presente) as presentes,
                 count(distinct a.miembro_id) filter (where a.presente) as personas
          from public.asistencias a join public.casas_oracion h on h.id = a.casa_oracion_id
          where a.fecha between p_desde and p_hasta group by h.id, h.nombre, h.codigo_zona) c;

  select coalesce(jsonb_agg(jsonb_build_object('titulo', e.titulo, 'tipo', e.tipo, 'inicia_en', e.inicia_en, 'registros', e.registros, 'presentes', e.presentes)
                            order by e.inicia_en), '[]'::jsonb)
    into eventos
    from (select ev.titulo, ev.tipo, ev.inicia_en, count(*) as registros, count(*) filter (where ae.presente) as presentes
          from public.asistencia_evento ae join public.eventos ev on ev.id = ae.evento_id
          where ev.inicia_en >= p_desde and ev.inicia_en < p_hasta + 1 group by ev.id, ev.titulo, ev.tipo, ev.inicia_en) e;

  select count(*) as registros, count(*) filter (where a.presente) as presentes into tot_casas
    from public.asistencias a where a.fecha between p_desde and p_hasta;
  select count(*) as registros, count(*) filter (where ae.presente) as presentes into tot_eventos
    from public.asistencia_evento ae join public.eventos ev on ev.id = ae.evento_id where ev.inicia_en >= p_desde and ev.inicia_en < p_hasta + 1;

  return jsonb_build_object(
    'desde', p_desde, 'hasta', p_hasta,
    'casas', jsonb_build_object('registros', tot_casas.registros, 'presentes', tot_casas.presentes, 'semanal', semanal, 'por_casa', por_casa),
    'eventos', jsonb_build_object('registros', tot_eventos.registros, 'presentes', tot_eventos.presentes, 'lista', eventos));
end $$;

-- Cifras del conjunto de miembros
create or replace function public.adn_informe_miembros_resumen()
returns jsonb language plpgsql stable set search_path to '' as $$
declare r jsonb;
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  select jsonb_build_object(
    'total', count(*), 'activos', count(*) filter (where activo), 'inactivos', count(*) filter (where not activo),
    'bautizados', count(*) filter (where bautizado), 'con_correo', count(*) filter (where email is not null),
    'con_telefono', count(*) filter (where telefono is not null), 'sin_casa', count(*) filter (where casa_oracion_id is null),
    'por_nivel', coalesce((select jsonb_object_agg(x.nivel, x.n) from (select nivel_compromiso as nivel, count(*) as n from public.miembros group by 1) x), '{}'::jsonb))
  into r
  from public.miembros;
  return r;
end $$;

-- Lista de miembros para el informe, ordenada por codigo. Se pagina con .range() desde la web
create or replace function public.adn_informe_miembros()
returns table (crm_id text, nombre text, apellido text, email text, telefono text, fecha_nacimiento date, genero text, casa text,
               nivel_compromiso text, bautizado boolean, fecha_conversion date, activo boolean, registrado date)
language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  return query
  select m.crm_id, m.nombre, m.apellido, m.email, m.telefono, m.fecha_nacimiento, m.genero, h.nombre,
         m.nivel_compromiso, coalesce(m.bautizado, false), m.fecha_conversion, coalesce(m.activo, false), m.created_at::date
  from public.miembros m left join public.casas_oracion h on h.id = m.casa_oracion_id and h.iglesia_id = m.iglesia_id
  order by m.crm_id;
end $$;

revoke all on function public.adn_informe_crecimiento(integer), public.adn_informe_asistencia(date, date),
  public.adn_informe_miembros_resumen(), public.adn_informe_miembros() from public, anon;
grant execute on function public.adn_informe_crecimiento(integer), public.adn_informe_asistencia(date, date),
  public.adn_informe_miembros_resumen(), public.adn_informe_miembros() to authenticated, service_role;
