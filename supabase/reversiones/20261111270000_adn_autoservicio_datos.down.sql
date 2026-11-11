-- Reversión de 20261111270000_adn_autoservicio_datos.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las funciones de autoservicio y la tabla de
-- auditoría que creó esa migración (con las filas que tuviera). Las iglesias que ya estuvieran en borrado suave por una baja pedida
-- por su propietario siguen su curso normal: el borrado suave y su auditoría (adn_ciclo_auditoria) no los toca esta reversión,
-- y la plataforma puede recuperarlas con `recuperar` como a cualquier otra.
\set ON_ERROR_STOP on
begin;
drop function public.adn_autoservicio_cancelar_baja(uuid, uuid, text);
drop function public.adn_autoservicio_baja(uuid, uuid, text);
drop function public.adn_autoservicio_exportar(uuid, uuid);
drop function public.adn_autoservicio_estado(uuid, uuid);
drop function public.adn_es_propietario(uuid, uuid);
drop table public.adn_datos_auditoria;
commit;
