-- Reversión de 20261111380000_adn_purga_tarea_estado.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena. No toca ningún dato ni ninguna tarea programada.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_purga_tarea_estado();
drop function if exists private.adn_purga_tarea_estado();
commit;
