-- Reversión de 20261111290000_adn_plataforma_resumen.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las tres funciones de lectura del Panel Maestro
-- (no tocan datos: solo leen). Sin ellas, la función de borde 'plataforma' vuelve a contar con 2 consultas por iglesia y las pantallas
-- de actividad e historial dicen que no están disponibles; el resto del panel sigue funcionando.
\set ON_ERROR_STOP on
begin;
drop function public.adn_plataforma_historial(uuid, integer);
drop function public.adn_plataforma_actividad(integer);
drop function public.adn_plataforma_resumen();
commit;
