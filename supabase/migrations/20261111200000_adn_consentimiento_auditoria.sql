-- Auditoria de consentimientos, registro por quien tiene permiso de comunicacion, baja por canal y enlace publico de baja.
--  * Todo cambio de consentimiento deja una fila en adn_consentimiento_auditoria (solo altas: quien, cuando, canal,
--    estado anterior y nuevo, origen). La escriben las funciones, nunca la web; nadie la modifica.
--  * Registrar un consentimiento a mano exige comunicacion.enviar. Una baja se registra como estado 'cancelado'; la
--    importacion no puede deshacerla (solo endurece, ver 20261111190000). Quitarla es una decision humana y queda anotada.
--  * Enlace de baja de un solo uso: la base guarda solo el hash del secreto y lo consume el servicio (funcion de borde
--    publica), nunca una persona autenticada. NO se envia ningun correo: el envio real sigue sin existir.
-- Reversion: supabase/reversiones/20261111200000_adn_consentimiento_auditoria.down.sql

create table public.adn_consentimiento_auditoria (
  id bigint generated always as identity primary key,
  iglesia_id uuid not null references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  canal text not null check (canal in ('email', 'sms', 'whatsapp')),
  estado_anterior text check (estado_anterior in ('suscrito', 'nunca', 'cancelado', 'sin_dato')),
  estado_nuevo text not null check (estado_nuevo in ('suscrito', 'nunca', 'cancelado', 'sin_dato')),
  origen text not null check (origen ~ '^[a-z0-9_-]{1,30}$'),
  usuario_id uuid,
  created_at timestamptz not null default now()
);
create index adn_consentimiento_auditoria_idx on public.adn_consentimiento_auditoria (iglesia_id, created_at desc);
create index adn_consentimiento_auditoria_miembro_idx on public.adn_consentimiento_auditoria (iglesia_id, miembro_id);
alter table public.adn_consentimiento_auditoria enable row level security;
create policy adn_consentimiento_auditoria_ver on public.adn_consentimiento_auditoria for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and ((select private.tiene_permiso('comunicacion.ver')) or (select private.tiene_permiso('comunicacion.enviar'))));
revoke all on public.adn_consentimiento_auditoria from public, anon, authenticated;
grant select on public.adn_consentimiento_auditoria to authenticated;
grant all on public.adn_consentimiento_auditoria to service_role;
create or replace function private.trg_consentimiento_auditoria_inmutable() returns trigger language plpgsql set search_path to '' as $$
begin
  raise exception 'ADN_REGISTRO_INMUTABLE';
end $$;
create trigger adn_consentimiento_auditoria_inmutable before update on public.adn_consentimiento_auditoria
  for each row execute function private.trg_consentimiento_auditoria_inmutable();

-- Enlaces de baja: solo servidor. El secreto no se guarda, solo su huella.
create table public.adn_bajas_enlaces (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  canal text not null check (canal in ('email', 'sms', 'whatsapp')),
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  expira_en timestamptz not null,
  usado_en timestamptz,
  constraint adn_bajas_enlaces_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade
);
create index adn_bajas_enlaces_miembro_idx on public.adn_bajas_enlaces (iglesia_id, miembro_id);
alter table public.adn_bajas_enlaces enable row level security;
revoke all on public.adn_bajas_enlaces from public, anon, authenticated;
grant all on public.adn_bajas_enlaces to service_role;

-- Unico punto que escribe un consentimiento: compara, escribe y audita. Solo la usan otras funciones y el servicio.
create or replace function private.adn_escribir_consentimiento(p_iglesia uuid, p_miembro uuid, p_canal text, p_estado text, p_origen text, p_usuario uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v_actual text;
begin
  select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = p_canal;
  if v_actual is not distinct from p_estado then return; end if;
  insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values (p_iglesia, p_miembro, p_canal, p_estado, p_origen)
  on conflict (miembro_id, canal) do update set estado = excluded.estado, origen = excluded.origen, actualizado_en = now();
  insert into public.adn_consentimiento_auditoria (iglesia_id, miembro_id, canal, estado_anterior, estado_nuevo, origen, usuario_id)
  values (p_iglesia, p_miembro, p_canal, v_actual, p_estado, p_origen, p_usuario);
end $$;
revoke execute on function private.adn_escribir_consentimiento(uuid, uuid, text, text, text, uuid) from public, anon, authenticated;
grant execute on function private.adn_escribir_consentimiento(uuid, uuid, text, text, text, uuid) to service_role;

-- La importacion escribe a traves de la funcion comun, y por tanto deja auditoria
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
        perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
      end if;
    elsif (rango ->> v_nuevo)::int > (rango ->> v_actual)::int then
      perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
    end if;
  end loop;
end $$;

-- Registro manual: exige comunicacion.enviar y puede dejar cualquier estado. Una baja es 'cancelado'.
drop function if exists public.adn_registrar_consentimiento(uuid, text, text);
drop function if exists private.adn_registrar_consentimiento(uuid, text, text);
create or replace function private.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text, p_origen text default 'manual')
returns void language plpgsql security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id();
begin
  if ig is null or not (select private.tiene_permiso('comunicacion.enviar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_canal not in ('email', 'sms', 'whatsapp') or p_estado not in ('suscrito', 'nunca', 'cancelado', 'sin_dato')
     or p_origen is null or p_origen !~ '^[a-z0-9_-]{1,30}$' then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  perform private.adn_escribir_consentimiento(ig, p_miembro, p_canal, p_estado, p_origen, (select auth.uid()));
end $$;
revoke execute on function private.adn_registrar_consentimiento(uuid, text, text, text) from public, anon;
grant execute on function private.adn_registrar_consentimiento(uuid, text, text, text) to authenticated, service_role;
create or replace function public.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text, p_origen text default 'manual')
returns void language sql set search_path to '' as $$ select private.adn_registrar_consentimiento(p_miembro, p_canal, p_estado, p_origen) $$;
revoke all on function public.adn_registrar_consentimiento(uuid, text, text, text) from public, anon;
grant execute on function public.adn_registrar_consentimiento(uuid, text, text, text) to authenticated, service_role;

-- Enlace de baja de un solo uso. Solo el servicio los crea y los consume. Devuelve el secreto UNA vez; la base guarda su huella.
create or replace function public.adn_baja_crear_enlace(p_miembro uuid, p_canal text, p_dias integer default 30)
returns text language plpgsql set search_path to '' as $$
declare v_ig uuid; v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
begin
  if p_canal not in ('email', 'sms', 'whatsapp') or p_dias is null or p_dias not between 1 and 365 then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  select m.iglesia_id into v_ig from public.miembros m where m.id = p_miembro;
  if v_ig is null then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  insert into public.adn_bajas_enlaces (iglesia_id, miembro_id, canal, token_hash, expira_en)
  values (v_ig, p_miembro, p_canal, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), now() + make_interval(days => p_dias));
  return v_token;
end $$;
revoke all on function public.adn_baja_crear_enlace(uuid, text, integer) from public, anon, authenticated;
grant execute on function public.adn_baja_crear_enlace(uuid, text, integer) to service_role;

-- Consume el enlace: lo marca como usado y deja al miembro en 'cancelado' en ese canal. Respuesta sin datos de la persona.
create or replace function public.adn_baja_consumir(p_token text)
returns jsonb language plpgsql set search_path to '' as $$
declare e public.adn_bajas_enlaces;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false, 'motivo', 'invalido'); end if;
  select * into e from public.adn_bajas_enlaces where token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex') for update;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'invalido'); end if;
  if e.usado_en is not null then return jsonb_build_object('ok', false, 'motivo', 'usado'); end if;
  if e.expira_en < now() then return jsonb_build_object('ok', false, 'motivo', 'caducado'); end if;
  update public.adn_bajas_enlaces set usado_en = now() where id = e.id;
  perform private.adn_escribir_consentimiento(e.iglesia_id, e.miembro_id, e.canal, 'cancelado', 'enlace', null);
  return jsonb_build_object('ok', true, 'canal', e.canal);
end $$;
revoke all on function public.adn_baja_consumir(text) from public, anon, authenticated;
grant execute on function public.adn_baja_consumir(text) to service_role;
