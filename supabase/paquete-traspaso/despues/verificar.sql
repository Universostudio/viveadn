-- Origen: scripts/entorno/purga-programada/verificar.sql, sha256 7e480feec807. Solo cambia que se quitan las órdenes propias de psql.
-- Vive ADN: comprueba que la purga programada está bien puesta. Solo lee y no muestra ningún secreto. Resultado correcto: TODAS las filas con ok = true.
-- «p07» y «p08» son lo que prueba que corre de verdad: salen en verde cuando ha pasado al menos una pasada (espera a la hora programada o fuerza una con
-- «select net.http_post(...)» según la guía de PURGA.md) y la última respuesta fue 200.
set search_path = pg_catalog;
with f(nombre, obtenido, esperado) as (values
  ('p01_extensiones', (select string_agg(extname, ',' order by extname) from pg_extension where extname in ('pg_cron', 'pg_net')), 'pg_cron,pg_net'),
  ('p02_secretos_en_vault', (select count(*)::text from vault.decrypted_secrets where name in ('adn_cron_secret', 'adn_anon_key', 'adn_funciones_url') and length(decrypted_secret) > 0), '3'),
  ('p03_tareas_programadas', (select string_agg(jobname, ',' order by jobname) from cron.job where jobname like 'adn-%'), 'adn-avisar-purga,adn-purga-vencidas'),
  ('p04_todas_activas', (select bool_and(active)::text from cron.job where jobname like 'adn-%'), 'true'),
  ('p05_horario_de_la_purga', (select schedule from cron.job where jobname = 'adn-purga-vencidas'), '15 3 * * *'),
  ('p06_la_orden_lleva_la_cabecera_y_la_accion',
    (select (command like '%x-adn-cron%' and command like '%purgar_vencidas%' and command like '%vault.decrypted_secrets%' and command not like '%eyJ%')::text from cron.job where jobname = 'adn-purga-vencidas'), 'true'),
  ('p07_ha_corrido_alguna_vez',
    (select (count(*) > 0)::text from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'adn-purga-vencidas'), 'true'),
  ('p08_la_ultima_pasada_termino_bien',
    (select d.status from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'adn-purga-vencidas' order by d.start_time desc limit 1), 'succeeded'),
  ('p09_la_ultima_respuesta_de_la_funcion_fue_200',
    (select r.status_code::text from net._http_response r order by r.created desc limit 1), '200')
)
select nombre, obtenido, esperado, (obtenido is not distinct from esperado) as ok from f
union all
select 'zz_todo_ok', null, null, bool_and(obtenido is not distinct from esperado) from f
order by 1;
