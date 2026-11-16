-- Vive ADN, incremental tras 20261111280000. Aplicar una vez, solo sobre un proyecto que ya tiene el paquete completo hasta esa migración. Detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261111290000_adn_plataforma_resumen.sql (sha256 b29a88b874b4) =====
-- Panel Maestro: lecturas agregadas para la administración de la plataforma, sin datos de personas. Hasta ahora la función de borde
-- contaba miembros y usuarios con 2 consultas por iglesia (con 500 iglesias, 1.000 consultas por carga). Estas funciones lo hacen en una
-- sola consulta y devuelven únicamente identificadores, nombres de iglesia, acciones, fechas y números.
--  * adn_plataforma_resumen(): una fila por iglesia con su número de miembros y de usuarios (perfiles). Nada más.
--  * adn_plataforma_actividad(p_limite): las últimas altas de iglesias y acciones de plataforma, de más reciente a más antigua, hasta
--    p_limite (entre 1 y 100). De la auditoría de plataforma solo sale la acción, la iglesia y la fecha: NUNCA el detalle, que puede
--    contener datos que no deben verse.
--  * adn_plataforma_historial(p_iglesia, p_limite): las acciones de plataforma de una iglesia (acción y fecha), hasta p_limite (1 a 200).
--  * Solo las ejecuta el servidor (la función 'plataforma', que antes comprueba que quien llama es administrador de plataforma).
-- Reversión: supabase/reversiones/20261111290000_adn_plataforma_resumen.down.sql
create or replace function public.adn_plataforma_resumen()
returns table (iglesia_id uuid, miembros bigint, usuarios bigint) language sql stable set search_path to '' as $$
  select i.id, coalesce(m.n, 0), coalesce(p.n, 0)
  from public.iglesias i
  left join (select iglesia_id, count(*) as n from public.miembros group by iglesia_id) m on m.iglesia_id = i.id
  left join (select iglesia_id, count(*) as n from public.perfiles group by iglesia_id) p on p.iglesia_id = i.id
$$;

create or replace function public.adn_plataforma_actividad(p_limite integer default 20)
returns table (tipo text, accion text, iglesia_id uuid, iglesia_nombre text, fecha timestamptz) language sql stable set search_path to '' as $$
  select e.tipo, e.accion, e.iglesia_id, e.iglesia_nombre, e.fecha
  from (
    select 'alta'::text as tipo, 'crear_iglesia'::text as accion, i.id as iglesia_id, i.nombre as iglesia_nombre, i.created_at as fecha
    from public.iglesias i
    union all
    select 'accion', a.accion, a.iglesia_id, i.nombre, a.created_at
    from public.plataforma_auditoria a
    left join public.iglesias i on i.id = a.iglesia_id
    -- La alta ya sale como «alta»: no se repite como acción
    where a.accion <> 'crear_iglesia'
  ) e
  order by e.fecha desc, e.tipo, e.accion
  limit greatest(1, least(coalesce(p_limite, 20), 100))
$$;

create or replace function public.adn_plataforma_historial(p_iglesia uuid, p_limite integer default 50)
returns table (accion text, fecha timestamptz) language sql stable set search_path to '' as $$
  select a.accion, a.created_at
  from public.plataforma_auditoria a
  where a.iglesia_id = p_iglesia
  order by a.created_at desc, a.id desc
  limit greatest(1, least(coalesce(p_limite, 50), 200))
$$;

revoke all on function public.adn_plataforma_resumen(), public.adn_plataforma_actividad(integer), public.adn_plataforma_historial(uuid, integer) from public, anon, authenticated;
grant execute on function public.adn_plataforma_resumen(), public.adn_plataforma_actividad(integer), public.adn_plataforma_historial(uuid, integer) to service_role;
