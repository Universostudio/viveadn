-- Libro externo de iglesias purgadas: la pieza de la base que lo hace posible.
-- El problema: restaurar una copia anterior a una purga devuelve los datos de una iglesia ya borrada, y la auditoría de la purga vive
-- en la misma base, así que se pierde con la restauración. El libro es una lista guardada FUERA de la base que dice qué iglesias se
-- purgaron y cuándo. Solo contiene identificadores y fechas: ningún dato de personas ni de iglesias.
--  * adn_purgas_desde(p_desde) exporta ese libro desde la auditoría: una fila por purga, con el identificador y la fecha. Con una fecha
--    devuelve solo lo posterior (o igual), para añadirlo al libro; sin fecha, todo. Es de solo lectura.
--  * adn_repurgar_registradas(p_ids, p_actor) se usa tras una restauración: toma los identificadores del libro y, de los que reaparecen en la
--    base restaurada, los vuelve a marcar como borrados con el plazo vencido. No borra nada por sí misma: la purga normal
--    (adn_iglesias_vencidas y adn_purgar_iglesia, desde la función de borde) las elimina por completo, con sus archivos y cuentas.
--    Las que ya no existen se ignoran. Devuelve los identificadores marcados.
--  * Solo las ejecuta el servidor.
-- Reversión: supabase/reversiones/20261111250000_adn_purgas_libro.down.sql
create or replace function public.adn_purgas_desde(p_desde timestamptz default null)
returns table (iglesia_ref uuid, purgada_en timestamptz) language sql stable set search_path to '' as $$
  select a.iglesia_ref, a.ocurrido_en
  from public.adn_ciclo_auditoria a
  where a.accion = 'purga' and (p_desde is null or a.ocurrido_en >= p_desde)
  order by a.ocurrido_en, a.id
$$;

create or replace function public.adn_repurgar_registradas(p_ids uuid[], p_actor uuid)
returns uuid[] language plpgsql set search_path to '' as $$
declare
  r record;
  marcadas uuid[] := '{}';
begin
  if p_ids is null or cardinality(p_ids) > 5000 then raise exception 'ADN_LISTA_INVALIDA'; end if;
  for r in select id from public.iglesias where id = any (p_ids) order by id for update loop
    update public.iglesias set
      adn_borrada_en = coalesce(adn_borrada_en, now()), adn_borrada_por = coalesce(adn_borrada_por, p_actor),
      etapa = 'suspendida', borrado_programado_en = now()
    where id = r.id;
    perform public.adn_auditar_ciclo(r.id, 'borrado_suave', p_actor, null, jsonb_build_object('origen', 'libro_externo'));
    marcadas := marcadas || r.id;
  end loop;
  return marcadas;
end $$;

revoke all on function public.adn_purgas_desde(timestamptz), public.adn_repurgar_registradas(uuid[], uuid) from public, anon, authenticated;
grant execute on function public.adn_purgas_desde(timestamptz), public.adn_repurgar_registradas(uuid[], uuid) to service_role;
