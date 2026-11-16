-- Reversion de 20261116120000_precios_catalogo.sql. Borra el catalogo de precios; no toca planes, modulos ni iglesias.
begin;
drop table if exists public.precios_modulo;
drop table if exists public.precios_plan;
drop table if exists public.precios_ajustes;
commit;
