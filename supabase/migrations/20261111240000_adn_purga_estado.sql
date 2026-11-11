-- Estado de la purga programada, para vigilar que la tarea programada de borrado funciona.
--  * adn_purga_estado(p_horas) devuelve solo cifras (sin datos de personas ni de iglesias): cuántas iglesias están en borrado suave,
--    cuántas tienen el plazo vencido y esperan purga, cuántas horas lleva esperando la más atrasada y si ese retraso supera p_horas
--    (48 por defecto). Una purga sana deja las vencidas en cero a las pocas horas.
--  * Solo la ejecuta el servidor. Es de solo lectura: no purga nada. La purga sigue siendo la del ciclo de vida.
-- Reversión: supabase/reversiones/20261111240000_adn_purga_estado.down.sql
create or replace function public.adn_purga_estado(p_horas integer default 48)
returns jsonb language sql stable set search_path to '' as $$
  select jsonb_build_object(
    'en_borrado', count(*) filter (where adn_borrada_en is not null),
    'vencidas', count(*) filter (where adn_borrada_en is not null and borrado_programado_en <= now()),
    'horas_mas_atrasada', coalesce(floor(max(extract(epoch from now() - borrado_programado_en)) filter (where adn_borrada_en is not null and borrado_programado_en <= now()) / 3600), 0)::int,
    'atrasada', coalesce(bool_or(adn_borrada_en is not null and borrado_programado_en <= now() - make_interval(hours => greatest(coalesce(p_horas, 48), 0))), false))
  from public.iglesias
$$;
revoke all on function public.adn_purga_estado(integer) from public, anon, authenticated;
grant execute on function public.adn_purga_estado(integer) to service_role;
