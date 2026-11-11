-- Reversión de 20261111250000_adn_purgas_libro.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita las dos funciones; no toca datos ni la
-- auditoría del ciclo de vida, y las iglesias que ya se hubieran marcado con adn_repurgar_registradas siguen su curso normal.
\set ON_ERROR_STOP on
begin;
drop function public.adn_repurgar_registradas(uuid[], uuid);
drop function public.adn_purgas_desde(timestamptz);
commit;
