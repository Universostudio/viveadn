-- Reversion de 20261116130000_altas_iglesia.sql. Borra lo que cada iglesia declaro al registrarse; no toca iglesias ni modulos.
begin;
drop table if exists public.altas_iglesia;
commit;
