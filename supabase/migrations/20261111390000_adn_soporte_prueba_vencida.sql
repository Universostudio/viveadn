-- Soporte con la prueba vencida: una iglesia en solo lectura (prueba vencida) debe poder pedir ayuda y leer las respuestas, justo cuando más lo necesita.
-- Antes, los tickets exigían tiene_permiso('iglesia.configurar') y con la prueba vencida ese permiso se cierra. Ahora basta ese permiso O ser propietario activo de una
-- iglesia que sigue activa (en receso o suspendida no hay acceso). Solo cambian las cuatro políticas de tickets y mensajes. Reversión: reversiones/20261111390000_adn_soporte_prueba_vencida.down.sql.
create or replace function private.adn_puede_pedir_ayuda() returns boolean language sql stable security definer set search_path to '' as $$
  select private.tiene_permiso('iglesia.configurar')
    or exists (
      select 1 from public.perfiles pf
      join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
      join public.iglesias i on i.id = pf.iglesia_id
      where pf.id = (select auth.uid()) and pf.activo and r.es_propietario and i.activa and i.adn_borrada_en is null
    )
$$;
revoke all on function private.adn_puede_pedir_ayuda() from public, anon, authenticated, service_role;
grant execute on function private.adn_puede_pedir_ayuda() to authenticated, service_role;

drop policy if exists adn_tickets_ver on public.adn_tickets;
create policy adn_tickets_ver on public.adn_tickets for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_tickets_crear on public.adn_tickets;
create policy adn_tickets_crear on public.adn_tickets for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and creado_por = (select auth.uid()) and estado = 'abierto' and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_ticket_mensajes_ver on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_ver on public.adn_ticket_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_ticket_mensajes_crear on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_crear on public.adn_ticket_mensajes for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and autor_tipo = 'iglesia' and autor = (select auth.uid()) and (select private.adn_puede_pedir_ayuda()));
