-- Reversion de 20261111150000_adn_informes.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Solo borra funciones de lectura (adn_informe_*): no toca ninguna tabla ni ningun dato.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_informe_miembros();
drop function if exists public.adn_informe_miembros_resumen();
drop function if exists public.adn_informe_asistencia(date, date);
drop function if exists public.adn_informe_crecimiento(integer);
commit;
