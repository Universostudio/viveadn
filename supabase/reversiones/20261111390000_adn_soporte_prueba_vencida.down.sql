-- Reversión de 20261111390000_adn_soporte_prueba_vencida.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena.
-- Devuelve las cuatro políticas de tickets y mensajes a su forma de 350000 (solo iglesia.configurar) y quita la función nueva. No toca ningún dato.
\set ON_ERROR_STOP on
begin;
drop policy if exists adn_tickets_ver on public.adn_tickets;
create policy adn_tickets_ver on public.adn_tickets for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_tickets_crear on public.adn_tickets;
create policy adn_tickets_crear on public.adn_tickets for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and creado_por = (select auth.uid()) and estado = 'abierto' and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_ticket_mensajes_ver on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_ver on public.adn_ticket_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_ticket_mensajes_crear on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_crear on public.adn_ticket_mensajes for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and autor_tipo = 'iglesia' and autor = (select auth.uid()) and (select private.tiene_permiso('iglesia.configurar')));
drop function if exists private.adn_puede_pedir_ayuda();
commit;
