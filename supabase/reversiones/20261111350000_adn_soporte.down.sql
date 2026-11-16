-- Reversión de 20261111350000_adn_soporte.sql (soporte dentro de la plataforma). No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh y tests/adn_soporte.sh demuestran que deja el esquema idéntico al anterior.
-- ATENCIÓN: borra las tablas nuevas y TODO lo que tengan (tickets, mensajes, novedades, avisos y sus entregas). Es lo único que se pierde; ninguna tabla anterior se toca.
\set ON_ERROR_STOP on
begin;
-- La lista de tablas exportables vuelve a su definición anterior (sin la exclusión de las entregas de avisos)
create or replace function public.adn_tablas_exportables()
returns table (nombre text, filtro text) language sql stable set search_path to '' as $$
  select 'iglesias'::text, 'id = $1'::text
  union all
  select c.relname::text, 'iglesia_id = $1'
  from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
    -- La auditoria de la plataforma son acciones internas y puede llevar notas de administracion: no sale en la exportacion de la iglesia
    and c.relname not in ('plataforma_auditoria', 'adn_bajas_enlaces', 'adn_confirmaciones')
    -- (adn_bajas_enlaces y adn_confirmaciones: secretos efimeros de un solo uso, sin valor fuera de la base)
    and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
  union all
  select 'rol_permisos', 'rol_id in (select id from public.roles where iglesia_id = $1)'
$$;
drop function if exists public.adn_aviso_entregar(uuid);
drop policy if exists adn_avisos_ver on public.adn_avisos;
drop table if exists public.adn_avisos_entregas;
drop table if exists public.adn_avisos;
drop function if exists private.adn_destino_valido(jsonb);
drop function if exists public.adn_novedades_marcar_vistas();
drop table if exists public.adn_novedades_vistas;
drop table if exists public.adn_novedades;
drop function if exists public.adn_ticket_crear(text, text, text);
drop table if exists public.adn_ticket_mensajes;
drop table if exists public.adn_tickets;
drop function if exists private.adn_mensaje_iglesia();
drop function if exists private.adn_mensaje_estado();
drop function if exists private.adn_tickets_limite();
commit;
