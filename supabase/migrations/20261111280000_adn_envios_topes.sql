-- Topes de envío de correo (docs/COSTE-ENVIO.md, aprobados por Gerencia). Un contador por día en la base: antes de enviar, la función
-- de borde reserva un envío; si algún tope está alcanzado, no se envía y se anota. Los topes los pasa quien llama (variables de la
-- función, con valores por defecto del plan gratuito), la base solo cuenta y decide de forma atómica.
--  * adn_envios_dia: una fila por día (UTC), tipo de correo e iglesia (la iglesia vacía usa un identificador de ceros). Solo números.
--  * adn_envio_reservar(tipo, iglesia, tope_iglesia, tope_tipo, tope_global): devuelve 'ok' y suma uno, o el primer tope alcanzado:
--    'tope_global', 'tope_tipo' o 'tope_iglesia'. Se comprueba en ese orden para que, con el plan gratuito, el fallo sea limpio y no a medias.
--  * adn_envio_liberar(tipo, iglesia): devuelve la reserva si el proveedor no aceptó el correo (no gasta cupo).
--  * Solo las ejecuta el servidor.
-- Reversión: supabase/reversiones/20261111280000_adn_envios_topes.down.sql
create table public.adn_envios_dia (
  dia date not null,
  tipo text not null check (tipo in ('purga', 'baja', 'confirmacion')),
  iglesia_ref uuid not null default '00000000-0000-0000-0000-000000000000',
  n integer not null check (n >= 0),
  primary key (dia, tipo, iglesia_ref)
);
alter table public.adn_envios_dia enable row level security;  -- sin políticas: solo service_role
revoke all on public.adn_envios_dia from public, anon, authenticated;
grant select, insert, update on public.adn_envios_dia to service_role;

create or replace function public.adn_envio_reservar(p_tipo text, p_iglesia uuid, p_tope_iglesia integer, p_tope_tipo integer, p_tope_global integer)
returns text language plpgsql set search_path to '' as $$
declare
  hoy date := (now() at time zone 'utc')::date;
  clave uuid := coalesce(p_iglesia, '00000000-0000-0000-0000-000000000000');
  global_n integer;
  tipo_n integer;
  iglesia_n integer;
begin
  if p_tipo is null or p_tipo not in ('purga', 'baja', 'confirmacion') then raise exception 'ADN_TIPO_INVALIDO'; end if;
  if p_tope_global is null or p_tope_global < 0 or p_tope_tipo < 0 or p_tope_iglesia < 0 then raise exception 'ADN_TOPE_INVALIDO'; end if;
  perform pg_advisory_xact_lock(hashtextextended('adn_envios_dia', 0));
  select coalesce(sum(n), 0) into global_n from public.adn_envios_dia where dia = hoy;
  if global_n >= p_tope_global then return 'tope_global'; end if;
  select coalesce(sum(n), 0) into tipo_n from public.adn_envios_dia where dia = hoy and tipo = p_tipo;
  if p_tope_tipo is not null and tipo_n >= p_tope_tipo then return 'tope_tipo'; end if;
  select coalesce(n, 0) into iglesia_n from public.adn_envios_dia where dia = hoy and tipo = p_tipo and iglesia_ref = clave;
  iglesia_n := coalesce(iglesia_n, 0);
  if p_tope_iglesia is not null and p_iglesia is not null and iglesia_n >= p_tope_iglesia then return 'tope_iglesia'; end if;
  insert into public.adn_envios_dia (dia, tipo, iglesia_ref, n) values (hoy, p_tipo, clave, 1)
    on conflict (dia, tipo, iglesia_ref) do update set n = public.adn_envios_dia.n + 1;
  return 'ok';
end $$;

create or replace function public.adn_envio_liberar(p_tipo text, p_iglesia uuid)
returns void language sql set search_path to '' as $$
  update public.adn_envios_dia set n = n - 1
  where dia = (now() at time zone 'utc')::date and tipo = p_tipo
    and iglesia_ref = coalesce(p_iglesia, '00000000-0000-0000-0000-000000000000') and n > 0
$$;

revoke all on function public.adn_envio_reservar(text, uuid, integer, integer, integer), public.adn_envio_liberar(text, uuid) from public, anon, authenticated;
grant execute on function public.adn_envio_reservar(text, uuid, integer, integer, integer), public.adn_envio_liberar(text, uuid) to service_role;
