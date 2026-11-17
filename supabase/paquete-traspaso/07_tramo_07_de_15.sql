-- Vive ADN, traspaso al proyecto real, archivo 8 de 19: tramo 7 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('private.adn_aplicar_consentimiento(uuid,jsonb,text,text,jsonb)') is not null then raise notice 'Tramo 7 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regclass('public.adn_consentimiento_auditoria') is not null) then raise exception 'Falta aplicar antes el tramo 6 de 15: no se sigue.'; end if;
  execute $cuerpo$

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
-- ===== 20261111210000_adn_consentimiento_evidencia (origen sha256 be34c9651a2d, compilado sha256 36a89db34852) =====
-- Evidencia del consentimiento: qué aceptó una persona, con qué texto y cuándo.
--  * Registro por QR: cada alta o reconocimiento deja una fila con la versión del texto aceptado (y su huella), el idioma,
--    el evento y la fecha. Los textos viven en adn_consentimiento_textos, versionados e inmutables: cambiar una palabra
--    obliga a crear una versión nueva.
--  * Importación: junto al estado que se aplica se guarda el valor original del archivo (por ejemplo, el de la columna
--    «Estado de suscriptor por email»), cuál fue el estado resultante y si cambió el consentimiento de la persona.
--  * Esto es solo evidencia. NO cambia a quién se le envía: eso lo siguen decidiendo adn_consentimientos y Comunicación.
--    Si el texto del registro por QR basta como consentimiento de algún canal es una decisión jurídica pendiente.
-- Reversión: supabase/reversiones/20261111210000_adn_consentimiento_evidencia.down.sql

-- Textos que se muestran al pedir el consentimiento. Una versión no se edita ni se borra: se crea otra.
create table public.adn_consentimiento_textos (
  finalidad text not null check (finalidad ~ '^[a-z0-9_]{1,30}$'),
  version text not null check (version ~ '^[a-z0-9._-]{1,20}$'),
  idioma text not null check (idioma in ('es', 'en', 'fr', 'pt-BR')),
  texto text not null check (char_length(texto) between 1 and 2000),
  texto_hash text not null check (texto_hash = encode(sha256(convert_to(texto, 'UTF8')), 'hex')),
  created_at timestamptz not null default now(),
  primary key (finalidad, version, idioma)
);
alter table public.adn_consentimiento_textos enable row level security;
create policy adn_consentimiento_textos_ver on public.adn_consentimiento_textos for select to authenticated using (true);
revoke all on public.adn_consentimiento_textos from public, anon, authenticated;
grant select on public.adn_consentimiento_textos to authenticated;
grant all on public.adn_consentimiento_textos to service_role;
create or replace function private.trg_consentimiento_inmutable() returns trigger language plpgsql set search_path to '' as $$
begin
  raise exception 'ADN_REGISTRO_INMUTABLE';
end $$;
create trigger adn_consentimiento_textos_inmutable before update or delete on public.adn_consentimiento_textos
  for each row execute function private.trg_consentimiento_inmutable();

-- El texto del registro por QR tal como está en la web (src/i18n/locales, clave checkin.consentimiento), versión v1.
-- scripts/comprobar-textos-consentimiento.mts falla si la web cambia el texto sin crear una versión nueva.
insert into public.adn_consentimiento_textos (finalidad, version, idioma, texto, texto_hash) values
  ('checkin', 'v1', 'es', 'Acepto que {iglesia} guarde estos datos para contactarme y acompañarme tras mi visita.', encode(sha256(convert_to('Acepto que {iglesia} guarde estos datos para contactarme y acompañarme tras mi visita.', 'UTF8')), 'hex')),
  ('checkin', 'v1', 'en', 'I agree that {iglesia} stores this information to contact me and follow up after my visit.', encode(sha256(convert_to('I agree that {iglesia} stores this information to contact me and follow up after my visit.', 'UTF8')), 'hex')),
  ('checkin', 'v1', 'fr', 'J''accepte que {iglesia} conserve ces données pour me contacter et m''accompagner après ma visite.', encode(sha256(convert_to('J''accepte que {iglesia} conserve ces données pour me contacter et m''accompagner après ma visite.', 'UTF8')), 'hex')),
  ('checkin', 'v1', 'pt-BR', 'Aceito que {iglesia} guarde estes dados para entrar em contato comigo e me acompanhar após a minha visita.', encode(sha256(convert_to('Aceito que {iglesia} guarde estes dados para entrar em contato comigo e me acompanhar após a minha visita.', 'UTF8')), 'hex'));

-- Evidencias: solo altas. Las escriben las funciones, nunca la web.
create table public.adn_consentimiento_evidencias (
  id bigint generated always as identity primary key,
  iglesia_id uuid not null references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  tipo text not null,
  canal text check (canal in ('email', 'sms', 'whatsapp')),
  finalidad text check (finalidad ~ '^[a-z0-9_]{1,30}$'),
  texto_version text check (texto_version ~ '^[a-z0-9._-]{1,20}$'),
  idioma text check (idioma in ('es', 'en', 'fr', 'pt-BR')),
  texto_hash text check (texto_hash ~ '^[0-9a-f]{64}$'),
  evento_id uuid,
  texto_original text check (char_length(texto_original) <= 60),
  estado_importado text check (estado_importado in ('suscrito', 'nunca', 'cancelado', 'sin_dato')),
  aplicado boolean,
  origen text not null check (origen ~ '^[a-z0-9_-]{1,30}$'),
  created_at timestamptz not null default now(),
  constraint adn_consentimiento_evidencias_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade
);
create index adn_consentimiento_evidencias_miembro_idx on public.adn_consentimiento_evidencias (iglesia_id, miembro_id, created_at desc);
alter table public.adn_consentimiento_evidencias enable row level security;
create policy adn_consentimiento_evidencias_ver on public.adn_consentimiento_evidencias for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and ((select private.tiene_permiso('comunicacion.ver')) or (select private.tiene_permiso('comunicacion.enviar'))));
revoke all on public.adn_consentimiento_evidencias from public, anon, authenticated;
grant select on public.adn_consentimiento_evidencias to authenticated;
grant all on public.adn_consentimiento_evidencias to service_role;
create trigger adn_consentimiento_evidencias_inmutable before update on public.adn_consentimiento_evidencias
  for each row execute function private.trg_consentimiento_inmutable();
create or replace function private.adn_aplicar_consentimiento(p_miembro uuid, p_consent jsonb, p_origen text, p_modo text, p_original jsonb default null)
returns void language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  v_canal text; v_nuevo text; v_actual text; v_despues text; v_orig text;
  rango constant jsonb := '{"suscrito": 0, "sin_dato": 1, "nunca": 2, "cancelado": 3}';
begin
  if ig is null or p_miembro is null then return; end if;
  if jsonb_typeof(p_consent) is distinct from 'object' and jsonb_typeof(p_original) is distinct from 'object' then return; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then return; end if;
  foreach v_canal in array array['email', 'sms', 'whatsapp'] loop
    v_nuevo := case when jsonb_typeof(p_consent) = 'object' then p_consent ->> v_canal end;
    if v_nuevo is not null and v_nuevo not in ('suscrito', 'nunca', 'cancelado') then v_nuevo := null; end if;
    select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = v_canal;
    if v_nuevo is not null then
      if v_actual is null then
        -- Sin registro: una persona nueva se guarda como venga; una existente solo si el estado restringe
        if p_modo = 'nuevo' or v_nuevo in ('nunca', 'cancelado') then
          perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
        end if;
      elsif (rango ->> v_nuevo)::int > (rango ->> v_actual)::int then
        perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
      end if;
    end if;
    -- Evidencia: el texto tal como venía en el archivo (sin saltos, caracteres de control ni espacios repetidos, hasta 60 caracteres)
    v_orig := case when jsonb_typeof(p_original) = 'object' then left(btrim(regexp_replace(coalesce(p_original ->> v_canal, ''), '[[:cntrl:][:space:]]+', ' ', 'g')), 60) end;
    if v_orig is not null and v_orig <> '' then
      select k.estado into v_despues from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = v_canal;
      insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, texto_original, estado_importado, aplicado, origen)
      values (ig, p_miembro, 'importacion', v_canal, v_orig, v_nuevo, v_despues is distinct from v_actual, p_origen);
    end if;
  end loop;
end $$;
$cuerpo$;
end $tramo$;
select 'ok: tramo 7 de 15 aplicado' as resultado, (to_regprocedure('private.adn_aplicar_consentimiento(uuid,jsonb,text,text,jsonb)') is not null) as comprobado;
