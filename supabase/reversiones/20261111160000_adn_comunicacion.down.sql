-- Reversion de 20261111160000_adn_comunicacion.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borran adn_mensajes, adn_mensaje_destinatarios y adn_comunicacion_bajas: el historial del buzon de pruebas y
--    la lista de personas que pidieron no recibir mensajes se pierden. Las bajas son una obligacion legal en cuanto
--    exista un proveedor real: copiarlas antes con \copy public.adn_comunicacion_bajas to 'bajas.csv' csv header
--  * Se quitan los permisos comunicacion.ver y comunicacion.enviar de todos los roles.
--  * No toca ninguna otra fila de negocio.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_vista_previa_envio(text, text);
drop function if exists public.adn_enviar_mensaje(uuid, text, text, text, text, text);
drop function if exists private.adn_vista_previa_envio(text, text);
drop function if exists private.adn_enviar_mensaje(uuid, text, text, text, text, text);
drop function if exists private.adn_destinatarios(uuid, text, text);
drop table if exists public.adn_mensaje_destinatarios;
drop table if exists public.adn_mensajes;
drop table if exists public.adn_comunicacion_bajas;

-- Cadena de siembra de roles anterior (la de 20261105235306_motor_formacion.sql)
create or replace function private.trg_sembrar_roles()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  perform private.sembrar_formacion(new.id);
  return new;
end $$;
drop function if exists private.sembrar_comunicacion(uuid);

delete from public.rol_permisos where permiso in ('comunicacion.ver', 'comunicacion.enviar');
delete from public.permisos where clave in ('comunicacion.ver', 'comunicacion.enviar');
commit;
