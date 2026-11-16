-- Reversión de 20261111310000_adn_asistencias_unico.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo
-- ordena, y tests/adn_reversion.sh y tests/adn_asistencias_unico.sh demuestran que deja el esquema idéntico al anterior.
-- Quita el índice único y DEVUELVE a asistencias las filas duplicadas que la limpieza archivó, para que los datos
-- queden como estaban antes de aplicar la migración. Después borra la tabla de archivo.
\set ON_ERROR_STOP on
begin;
drop index public.adn_asistencias_unica_idx;
insert into public.asistencias (id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente, notas, created_at)
  select id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente, notas, created_at from public.adn_asistencias_duplicadas;
drop table public.adn_asistencias_duplicadas;
commit;
