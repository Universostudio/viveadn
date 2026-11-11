-- Topes de envío de correo: contador diario atómico, orden de los topes, liberación y privilegios.
\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
grant execute on function pg_temp.igual(text, text, text) to authenticated, anon, service_role;
create or replace function pg_temp.falla(sentencia text, texto text, msg text) returns void language plpgsql as $$
begin
  begin execute sentencia; exception when others then
    if sqlerrm like '%' || texto || '%' then raise notice 'OK: %', msg; return; end if;
    raise exception 'FALLO: % (error inesperado: %)', msg, sqlerrm;
  end;
  raise exception 'FALLO: % (no fallo)', msg;
end $$;
grant execute on function pg_temp.falla(text, text, text) to authenticated, anon, service_role;
delete from public.adn_envios_dia;

-- 1. Aviso de baja: 2 por iglesia y día
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000a', 2, null, 100), 'ok', 'la primera reserva pasa');
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000a', 2, null, 100), 'ok', 'la segunda pasa');
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000a', 2, null, 100), 'tope_iglesia', 'la tercera de la misma iglesia se rechaza');
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000b', 2, null, 100), 'ok', 'otra iglesia tiene su propio cupo');
select pg_temp.igual((select n::text from public.adn_envios_dia where tipo = 'baja' and iglesia_ref = 'b1000000-0000-0000-0000-00000000000a'), '2', 'lo rechazado no suma');

-- 2. Liberar devuelve el cupo
select public.adn_envio_liberar('baja', 'b1000000-0000-0000-0000-00000000000a');
select pg_temp.igual((select n::text from public.adn_envios_dia where tipo = 'baja' and iglesia_ref = 'b1000000-0000-0000-0000-00000000000a'), '1', 'liberar resta uno');
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000a', 2, null, 100), 'ok', 'y se puede volver a reservar');
select public.adn_envio_liberar('baja', 'b1000000-0000-0000-0000-0000000000cc');
select pg_temp.igual((select count(*)::text from public.adn_envios_dia where iglesia_ref = 'b1000000-0000-0000-0000-0000000000cc'), '0', 'liberar algo que no existe no crea filas');
update public.adn_envios_dia set n = 0 where tipo = 'baja' and iglesia_ref = 'b1000000-0000-0000-0000-00000000000b';
select public.adn_envio_liberar('baja', 'b1000000-0000-0000-0000-00000000000b');
select pg_temp.igual((select n::text from public.adn_envios_dia where tipo = 'baja' and iglesia_ref = 'b1000000-0000-0000-0000-00000000000b'), '0', 'liberar nunca deja el contador negativo');

-- 3. Purga: 1 al día para toda la plataforma (sin iglesia)
select pg_temp.igual(public.adn_envio_reservar('purga', null, null, 1, 100), 'ok', 'la alerta de purga pasa una vez');
select pg_temp.igual(public.adn_envio_reservar('purga', null, null, 1, 100), 'tope_tipo', 'la segunda del día se rechaza');

-- 4. Doble confirmación: tope por tipo en toda la plataforma
select pg_temp.igual(public.adn_envio_reservar('confirmacion', 'b1000000-0000-0000-0000-00000000000a', 200, 2, 100), 'ok', 'confirmación 1');
select pg_temp.igual(public.adn_envio_reservar('confirmacion', 'b1000000-0000-0000-0000-00000000000b', 200, 2, 100), 'ok', 'confirmación 2 de otra iglesia');
select pg_temp.igual(public.adn_envio_reservar('confirmacion', 'b1000000-0000-0000-0000-00000000000c', 200, 2, 100), 'tope_tipo', 'el tope del tipo vale para toda la plataforma');

-- 5. Tope global: manda sobre todo lo demás (plan gratuito: falla limpio)
delete from public.adn_envios_dia;
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000a', 2, 2, 3), 'ok', 'global 1');
select pg_temp.igual(public.adn_envio_reservar('purga', null, null, 1, 3), 'ok', 'global 2');
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000b', 2, 2, 3), 'ok', 'global 3');
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000c', 2, 2, 3), 'tope_global', 'el cuarto del día se rechaza por el tope global');
select pg_temp.igual(public.adn_envio_reservar('purga', null, null, 1, 3), 'tope_global', 'y el global se comprueba antes que el del tipo');
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000c', 2, 2, 0), 'tope_global', 'un tope global de 0 apaga todo');
select pg_temp.igual((select sum(n)::text from public.adn_envios_dia), '3', 'el total del día no pasó de 3');

-- 6. Otro día, otro contador
update public.adn_envios_dia set dia = dia - 1;
select pg_temp.igual(public.adn_envio_reservar('baja', 'b1000000-0000-0000-0000-00000000000c', 2, 2, 3), 'ok', 'al día siguiente el cupo está vacío');

-- 7. Validación y privilegios
select pg_temp.falla($$select public.adn_envio_reservar('otro', null, null, null, 5)$$, 'ADN_TIPO_INVALIDO', 'un tipo desconocido se rechaza');
select pg_temp.falla($$select public.adn_envio_reservar(null, null, null, null, 5)$$, 'ADN_TIPO_INVALIDO', 'un tipo nulo se rechaza');
select pg_temp.falla($$select public.adn_envio_reservar('baja', null, null, null, null)$$, 'ADN_TOPE_INVALIDO', 'sin tope global no se envía');
select pg_temp.falla($$select public.adn_envio_reservar('baja', null, null, null, -1)$$, 'ADN_TOPE_INVALIDO', 'un tope negativo se rechaza');
select pg_temp.falla($$set local role authenticated; select public.adn_envio_reservar('baja', null, 1, 1, 1)$$, 'permission denied', 'una cuenta de iglesia no reserva envíos');
reset role;
select pg_temp.falla($$set local role anon; select count(*) from public.adn_envios_dia$$, 'permission denied', 'sin sesión no se lee el contador');
reset role;
select pg_temp.falla($$set local role service_role; delete from public.adn_envios_dia$$, 'permission denied', 'ni el servidor borra contadores');
reset role;
rollback;
