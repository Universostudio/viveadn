-- Reversión de 20261111360000_adn_precios_plan.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena.
-- Quita las tres columnas de precio de planes; los precios que alguien hubiera fijado se pierden (no hay otra copia). El resto de planes no se toca.
\set ON_ERROR_STOP on
begin;
alter table public.planes drop constraint if exists adn_planes_precio_coherente;
alter table public.planes drop column if exists moneda;
alter table public.planes drop column if exists precio_anual_centimos;
alter table public.planes drop column if exists precio_mensual_centimos;
commit;
