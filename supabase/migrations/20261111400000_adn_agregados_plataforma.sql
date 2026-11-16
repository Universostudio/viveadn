-- Panel Maestro: agregados en SQL. La función de borde 'plataforma' leía filas enteras para contarlas (iglesias para la facturación, tickets y
-- entregas para el soporte, entregas para las estadísticas de avisos). El límite de filas por respuesta del servicio alojado (por defecto en
-- torno a 1.000, sin verificar aquí) las cortaba en silencio. Estas tres funciones devuelven solo números, ya agrupados:
--  * adn_plataforma_facturacion(): iglesias por plan, etapa, demo y borrado suave (sin nombres ni identificadores).
--  * adn_soporte_resumen(p_incluir_demo): cifras de tickets, avisos vigentes, entregas y novedades; con p_incluir_demo = false no cuentan
--    los tickets ni las entregas de iglesias de demostración (el mismo interruptor que el resto del panel).
--  * adn_avisos_estadisticas(p_ids): entregas, lecturas y descartes de cada aviso pedido.
-- Solo las ejecuta el servidor (la función 'plataforma', que antes comprueba que quien llama es administrador de plataforma).
-- Reversión: supabase/reversiones/20261111400000_adn_agregados_plataforma.down.sql
create or replace function public.adn_plataforma_facturacion()
returns table (plan text, activa boolean, etapa text, es_demo boolean, borrada boolean, n bigint) language sql stable set search_path to '' as $$
  select i.plan, i.activa, i.etapa, i.es_demo, (i.adn_borrada_en is not null), count(*)
  from public.iglesias i
  group by i.plan, i.activa, i.etapa, i.es_demo, (i.adn_borrada_en is not null)
$$;

create or replace function public.adn_soporte_resumen(p_incluir_demo boolean default true)
returns table (tickets_abiertos bigint, tickets_respondidos bigint, tickets_cerrados bigint, tickets_urgentes bigint,
               avisos_vigentes bigint, entregas bigint, leidos bigint, descartados bigint, novedades_total bigint, ultima_version text, ultima_publicada timestamptz)
language sql stable set search_path to '' as $$
  with t as (
    select x.estado, x.prioridad from public.adn_tickets x
    where coalesce(p_incluir_demo, true) or not exists (select 1 from public.iglesias i where i.id = x.iglesia_id and i.es_demo)
  ), v as (
    select a.id from public.adn_avisos a
    where a.retirado_en is null and a.desde <= now() and (a.hasta is null or a.hasta > now())
  ), e as (
    select x.leido_en, x.descartado_en from public.adn_avisos_entregas x
    where x.aviso_id in (select id from v)
      and (coalesce(p_incluir_demo, true) or not exists (select 1 from public.iglesias i where i.id = x.iglesia_id and i.es_demo))
  ), n as (
    select count(*) as total, (array_agg(version order by publicada_en desc))[1] as version, max(publicada_en) as publicada
    from public.adn_novedades where retirada_en is null
  )
  select (select count(*) from t where estado = 'abierto'), (select count(*) from t where estado = 'respondido'), (select count(*) from t where estado = 'cerrado'),
         (select count(*) from t where estado <> 'cerrado' and prioridad = 'urgente'),
         (select count(*) from v), (select count(*) from e), (select count(*) from e where leido_en is not null), (select count(*) from e where descartado_en is not null),
         n.total, n.version, n.publicada
  from n
$$;

create or replace function public.adn_avisos_estadisticas(p_ids uuid[])
returns table (aviso_id uuid, entregas bigint, leidos bigint, descartados bigint) language sql stable set search_path to '' as $$
  select e.aviso_id, count(*), count(e.leido_en), count(e.descartado_en)
  from public.adn_avisos_entregas e
  where e.aviso_id = any (coalesce(p_ids, '{}'::uuid[]))
  group by e.aviso_id
$$;

revoke all on function public.adn_plataforma_facturacion(), public.adn_soporte_resumen(boolean), public.adn_avisos_estadisticas(uuid[]) from public, anon, authenticated;
grant execute on function public.adn_plataforma_facturacion(), public.adn_soporte_resumen(boolean), public.adn_avisos_estadisticas(uuid[]) to service_role;
