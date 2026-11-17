-- Reversion de 20261117100000_precios_por_moneda.sql. Deja un solo precio por plan y modulo (el de USD) y la moneda base sin decidir.
begin;
alter table public.altas_iglesia drop column if exists moneda;
alter table public.altas_iglesia drop column if exists pais_iso;
alter table public.precios_ajustes drop constraint if exists precios_ajustes_moneda_fk;
update public.precios_ajustes set moneda = null;
delete from public.precios_modulo where moneda <> 'USD';
alter table public.precios_modulo drop constraint precios_modulo_pkey, add primary key (modulo);
alter table public.precios_modulo drop column moneda;
delete from public.precios_plan where moneda <> 'USD';
alter table public.precios_plan drop constraint precios_plan_pkey, add primary key (plan);
alter table public.precios_plan drop column moneda;
drop table if exists public.monedas;
commit;
