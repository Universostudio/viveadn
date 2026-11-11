-- Reversion de 20261111200000_adn_consentimiento_auditoria.sql. No es una migracion: se ejecuta a mano, solo si Gerencia
-- lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Borra la auditoria de consentimientos y los enlaces de baja (tablas y filas) y devuelve las funciones de consentimiento
-- a su definicion anterior. NO borra adn_consentimientos: los consentimientos se conservan.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_registrar_consentimiento(uuid, text, text, text);
drop function if exists private.adn_registrar_consentimiento(uuid, text, text, text);
drop function if exists public.adn_baja_consumir(text);
drop function if exists public.adn_baja_crear_enlace(uuid, text, integer);
create or replace function private.adn_aplicar_consentimiento(p_miembro uuid, p_consent jsonb, p_origen text, p_modo text)
returns void language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  v_canal text; v_nuevo text; v_actual text;
  rango constant jsonb := '{"suscrito": 0, "sin_dato": 1, "nunca": 2, "cancelado": 3}';
begin
  if ig is null or p_miembro is null or jsonb_typeof(p_consent) is distinct from 'object' then return; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then return; end if;
  foreach v_canal in array array['email', 'sms', 'whatsapp'] loop
    v_nuevo := p_consent ->> v_canal;
    continue when v_nuevo is null or v_nuevo not in ('suscrito', 'nunca', 'cancelado');
    select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = v_canal;
    if v_actual is null then
      -- Sin registro: una persona nueva se guarda como venga; una existente solo si el estado restringe
      if p_modo = 'nuevo' or v_nuevo in ('nunca', 'cancelado') then
        insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values (ig, p_miembro, v_canal, v_nuevo, p_origen);
      end if;
    elsif (rango ->> v_nuevo)::int > (rango ->> v_actual)::int then
      update public.adn_consentimientos set estado = v_nuevo, origen = p_origen, actualizado_en = now()
       where miembro_id = p_miembro and canal = v_canal;
    end if;
  end loop;
end $$;

create or replace function private.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text)
returns void language plpgsql security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id();
begin
  if ig is null or not (select private.tiene_permiso('miembros.editar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_canal not in ('email', 'sms', 'whatsapp') or p_estado not in ('suscrito', 'nunca', 'cancelado', 'sin_dato') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values (ig, p_miembro, p_canal, p_estado, 'manual')
  on conflict (miembro_id, canal) do update set estado = excluded.estado, origen = 'manual', actualizado_en = now();
end $$;
revoke execute on function private.adn_registrar_consentimiento(uuid, text, text) from public, anon;
grant execute on function private.adn_registrar_consentimiento(uuid, text, text) to authenticated, service_role;
create or replace function public.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text)
returns void language sql set search_path to '' as $$ select private.adn_registrar_consentimiento(p_miembro, p_canal, p_estado) $$;
revoke all on function public.adn_registrar_consentimiento(uuid, text, text) from public, anon;
grant execute on function public.adn_registrar_consentimiento(uuid, text, text) to authenticated, service_role;
drop function if exists private.adn_escribir_consentimiento(uuid, uuid, text, text, text, uuid);
drop table if exists public.adn_bajas_enlaces;
drop table if exists public.adn_consentimiento_auditoria;
drop function if exists private.trg_consentimiento_auditoria_inmutable();
commit;
