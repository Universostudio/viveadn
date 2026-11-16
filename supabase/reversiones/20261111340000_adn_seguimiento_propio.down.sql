-- Reversión de 20261111340000_adn_seguimiento_propio.sql (fase 3 del método de seguimiento configurable). No es una migración: se ejecuta a mano,
-- solo si Gerencia lo ordena, y tests/adn_reversion.sh y tests/adn_seguimiento_propio.sh demuestran que deja el esquema idéntico al anterior.
-- NO borra ningún método propio, ninguna configuración ni ningún proceso: solo quita la posibilidad de escribir desde la web, el módulo y los disparadores.
-- Los métodos propios que existan siguen en la base y los procesos que los usan siguen calculando con ellos. Los procesos nuevos vuelven a tomar OP72.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_seguimiento_en_uso(uuid);
drop function if exists private.adn_seguimiento_en_uso(uuid);
drop trigger if exists consolidaciones_a_metodo on public.consolidaciones;
drop function if exists private.adn_consolidacion_metodo_activo();
drop trigger if exists adn_seguimiento_config_fecha on public.adn_seguimiento_config;
drop function if exists private.adn_config_tocar();
drop policy if exists adn_seguimiento_config_cambiar on public.adn_seguimiento_config;
drop policy if exists adn_seguimiento_config_elegir on public.adn_seguimiento_config;
revoke all on public.adn_seguimiento_config from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_config to authenticated;
grant all on public.adn_seguimiento_config to service_role;
drop trigger if exists adn_seguimiento_metodos_recalcular on public.adn_seguimiento_metodos;
drop function if exists private.adn_metodo_recalcular();
drop trigger if exists adn_seguimiento_metodos_archivo on public.adn_seguimiento_metodos;
drop function if exists private.adn_no_archivar_activo();
drop trigger if exists adn_seguimiento_metodos_limite on public.adn_seguimiento_metodos;
drop function if exists private.adn_limitar_metodos();
drop policy if exists adn_seguimiento_metodos_editar on public.adn_seguimiento_metodos;
drop policy if exists adn_seguimiento_metodos_crear on public.adn_seguimiento_metodos;
revoke all on public.adn_seguimiento_metodos from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_metodos to authenticated;
grant all on public.adn_seguimiento_metodos to service_role;
drop function if exists private.adn_metodo_usable(uuid);
-- La comprobación de plantilla vuelve a su definición de la fase 1 (con la seguridad de quien llama)
create or replace function private.adn_comprobar_plantilla() returns trigger language plpgsql set search_path to '' as $$
begin
  if new.plantilla_origen is not null and exists (select 1 from public.adn_seguimiento_metodos o where o.id = new.plantilla_origen and o.iglesia_id is not null and o.iglesia_id is distinct from new.iglesia_id) then
    raise exception 'ADN_PLANTILLA_DE_OTRA_IGLESIA' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_plantilla() from public, anon, authenticated, service_role;
create or replace function private.adn_comprobar_metodo() returns trigger language plpgsql set search_path to '' as $$
declare m record;
begin
  select iglesia_id, archivado_en into m from public.adn_seguimiento_metodos where id = new.metodo_id;
  if not found then raise exception 'ADN_METODO_INEXISTENTE' using errcode = 'foreign_key_violation'; end if;
  if m.iglesia_id is not null and m.iglesia_id <> new.iglesia_id then raise exception 'ADN_METODO_DE_OTRA_IGLESIA' using errcode = 'check_violation'; end if;
  if m.archivado_en is not null and (tg_op = 'INSERT' or new.metodo_id is distinct from old.metodo_id) then raise exception 'ADN_METODO_ARCHIVADO' using errcode = 'check_violation'; end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_metodo() from public, anon, authenticated, service_role;
-- El módulo: si alguna iglesia lo tenía contratado aparte, esa fila se quita con él
delete from public.iglesia_modulos where modulo = 'seguimiento_propio';
delete from public.plan_modulos where modulo = 'seguimiento_propio';
delete from public.modulos where clave = 'seguimiento_propio';
commit;
