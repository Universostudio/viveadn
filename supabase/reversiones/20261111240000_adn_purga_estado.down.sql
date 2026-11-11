-- Reversión de 20261111240000_adn_purga_estado.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita la función de lectura.
\set ON_ERROR_STOP on
begin;
drop function public.adn_purga_estado(integer);
commit;
