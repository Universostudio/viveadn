-- Reversion de 20261111170000_adn_panel_inicio.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena.
-- Solo borra una funcion de lectura: no toca ninguna tabla ni ningun dato.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_panel_inicio(date);
commit;
