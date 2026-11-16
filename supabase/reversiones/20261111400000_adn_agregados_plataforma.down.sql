-- Reversión de 20261111400000_adn_agregados_plataforma.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las tres funciones de agregado (solo leen, no tocan datos).
-- Sin ellas, la función de borde 'plataforma' lee las filas y cuenta ella misma, por páginas, como antes de esta migración.
\set ON_ERROR_STOP on
begin;
drop function public.adn_avisos_estadisticas(uuid[]);
drop function public.adn_soporte_resumen(boolean);
drop function public.adn_plataforma_facturacion();
commit;
