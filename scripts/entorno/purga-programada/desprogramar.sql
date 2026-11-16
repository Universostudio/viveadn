-- Vive ADN: quita las tareas programadas de purga. Solo borra las dos tareas «adn-», ninguna otra, y no toca los secretos ni ningún dato. Lo ejecuta Gerencia a mano.
\set ON_ERROR_STOP on
begin;
select cron.unschedule(jobname) from cron.job where jobname in ('adn-purga-vencidas', 'adn-avisar-purga');
commit;
