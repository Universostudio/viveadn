-- Reversión de 20261111280000_adn_envios_topes.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las dos funciones y la tabla de contadores
-- diarios de envío (con sus filas: solo son cuentas del día, sin datos de personas). Sin ella, el envío de correo no debe estar encendido.
\set ON_ERROR_STOP on
begin;
drop function public.adn_envio_liberar(text, uuid);
drop function public.adn_envio_reservar(text, uuid, integer, integer, integer);
drop table public.adn_envios_dia;
commit;
