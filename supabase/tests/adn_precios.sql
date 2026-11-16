-- Precios por plan: valen vacíos, se validan, la iglesia los lee pero no los cambia, y la reversión es la de adn_reversion.sh.
\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm not like '%' || texto || '%' then raise exception 'FALLO: % (error inesperado % %)', msg, sqlstate, sqlerrm; end if;
    raise notice 'OK: % (%)', msg, sqlstate; return;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text), pg_temp.falla(text, text, text) to authenticated;
select pg_temp.igual((select count(*)::text from public.planes where precio_mensual_centimos is not null or precio_anual_centimos is not null or moneda is not null), '0', 'los planes existentes quedan sin precio inventado');
select pg_temp.falla($$update public.planes set precio_mensual_centimos = -1, moneda = 'EUR' where clave = (select clave from public.planes limit 1)$$, 'adn_planes_precio_coherente', 'un precio negativo se rechaza');
select pg_temp.falla($$update public.planes set precio_mensual_centimos = 1000 where clave = (select clave from public.planes limit 1)$$, 'adn_planes_precio_coherente', 'un precio sin moneda se rechaza');
select pg_temp.falla($$update public.planes set precio_mensual_centimos = 1000, moneda = 'euro' where clave = (select clave from public.planes limit 1)$$, 'adn_planes_precio_coherente', 'una moneda que no es de tres letras se rechaza');
update public.planes set precio_mensual_centimos = 1900, precio_anual_centimos = 19000, moneda = 'EUR' where clave = (select clave from public.planes order by orden limit 1);
select pg_temp.igual((select count(*)::text from public.planes where moneda = 'EUR' and precio_anual_centimos = 19000), '1', 'un precio válido se guarda');
set local role authenticated;
select pg_temp.igual((select count(*)::text from public.planes where precio_mensual_centimos = 1900), '1', 'una sesión puede leer el precio');
select pg_temp.falla($$update public.planes set precio_mensual_centimos = 1 where true$$, 'permission denied', 'una sesión no puede cambiar precios');
reset role;
rollback;
