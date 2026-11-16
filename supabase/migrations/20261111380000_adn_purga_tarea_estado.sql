-- Estado de la tarea programada de purga, para mostrarlo en «Sistema». Lee pg_cron si existe y, si no, dice «no disponible» (la base local no tiene la extensión).
-- Solo devuelve el nombre de la tarea, su horario, si está activa y cómo terminó su última pasada: nunca la orden completa, que lleva cabeceras con secretos.
-- Función de definidor en `private` y envoltorio de invocador en `public`, ejecutable solo por el servidor. Reversión: reversiones/20261111380000_adn_purga_tarea_estado.down.sql.
create or replace function private.adn_purga_tarea_estado() returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare r jsonb;
begin
  if to_regclass('cron.job') is null or to_regclass('cron.job_run_details') is null then
    return jsonb_build_object('disponible', false, 'tareas', '[]'::jsonb);
  end if;
  execute $q$
    select jsonb_build_object('disponible', true, 'tareas', coalesce(jsonb_agg(jsonb_build_object(
      'nombre', j.jobname, 'programacion', j.schedule, 'activa', j.active,
      'ultima_pasada', u.start_time, 'ultimo_resultado', u.status) order by j.jobname), '[]'::jsonb))
    from cron.job j
    left join lateral (select d.start_time, d.status from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1) u on true
    where j.jobname like 'adn-%'
  $q$ into r;
  return r;
end $$;
revoke all on function private.adn_purga_tarea_estado() from public, anon, authenticated, service_role;
grant execute on function private.adn_purga_tarea_estado() to service_role;

create or replace function public.adn_purga_tarea_estado() returns jsonb language sql stable set search_path to '' as $$
  select private.adn_purga_tarea_estado()
$$;
revoke all on function public.adn_purga_tarea_estado() from public, anon, authenticated, service_role;
grant execute on function public.adn_purga_tarea_estado() to service_role;
