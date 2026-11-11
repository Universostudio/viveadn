-- Reversión de 20261111260000_adn_exportacion_paginada.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita las funciones de la exportación por páginas;
-- adn_exportar_paquete, que sigue existiendo, no se toca.
\set ON_ERROR_STOP on
begin;
drop function public.adn_exportar_pagina(uuid, text, text, jsonb, integer);
drop function public.adn_exportar_plan(uuid);
drop function public.adn_exportar_orden();
drop function public.adn_exportar_secretos();
commit;
