-- Credencial personal con QR. Cada miembro puede tener una credencial; quien registra asistencia la escanea en un evento
-- y la base marca la asistencia. El QR lleva solo un codigo aleatorio (nunca el nombre ni ningun dato de la persona) y no
-- abre ninguna pagina publica: solo sirve dentro de la app, a quien tiene permiso para registrar asistencia en esa iglesia.
-- La columna se llama token para que la exportacion de la iglesia la excluya como el resto de secretos.

-- 1. Permiso nuevo y su semilla en los roles de sistema, tambien en las iglesias que ya existen.
--    Cuelga del modulo "credenciales" del catalogo (especial, incluido en Premium y contratable como complemento): sin el modulo
--    no se emite, no se lee y no se escanea, y la web lo muestra como complemento bloqueado.
insert into public.permisos (clave, modulo, descripcion, sensible) values
  ('credenciales.gestionar', 'credenciales', 'Emitir, renovar y retirar la credencial QR de un miembro', false)
on conflict (clave) do nothing;

create or replace function private.sembrar_credencial(p_iglesia uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, 'credenciales.gestionar'
    from public.roles r
    where r.iglesia_id = p_iglesia and r.clave in ('administrador', 'coadministrador')
  on conflict do nothing;
end $$;
revoke all on function private.sembrar_credencial(uuid) from public, anon, authenticated;
grant execute on function private.sembrar_credencial(uuid) to service_role;

create or replace function private.trg_sembrar_roles()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  perform private.sembrar_formacion(new.id);
  perform private.sembrar_credencial(new.id);
  return new;
end $$;
select private.sembrar_credencial(id) from public.iglesias;

-- 2. Tabla. Un miembro tiene como mucho una credencial; renovarla cambia el token y la anterior deja de valer.
create table public.credenciales_miembro (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  miembro_id uuid not null,
  token text not null default replace(gen_random_uuid()::text, '-', '') check (token ~ '^[0-9a-f]{32}$'),
  emitida_en timestamptz not null default now(),
  emitida_por uuid default auth.uid(),
  unique (token),
  unique (iglesia_id, miembro_id),
  constraint credenciales_miembro_fk foreign key (iglesia_id, miembro_id)
    references public.miembros (iglesia_id, id) on delete cascade
);

alter table public.credenciales_miembro enable row level security;
-- Solo lectura directa, y solo para quien gestiona credenciales: el token permite marcar asistencia
create policy credenciales_ver on public.credenciales_miembro for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('credenciales.gestionar')));
grant select on public.credenciales_miembro to authenticated;
grant all on public.credenciales_miembro to service_role;

-- 3. Emitir (o renovar). La logica privilegiada vive en private; la API publica es un envoltorio sin privilegios.
create or replace function private.emitir_credencial(p_miembro uuid, p_renovar boolean)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_iglesia uuid := (select private.get_iglesia_id());
  v_id uuid;
begin
  if not (select private.tiene_permiso('credenciales.gestionar')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = v_iglesia and m.activo) then
    raise exception 'MIEMBRO_NO_EXISTE' using errcode = 'P0002';
  end if;
  insert into public.credenciales_miembro (iglesia_id, miembro_id) values (v_iglesia, p_miembro)
    on conflict (iglesia_id, miembro_id) do nothing
    returning id into v_id;
  if v_id is null then
    if p_renovar then
      update public.credenciales_miembro
         set token = replace(gen_random_uuid()::text, '-', ''), emitida_en = now(), emitida_por = auth.uid()
       where iglesia_id = v_iglesia and miembro_id = p_miembro
       returning id into v_id;
    else
      select c.id into v_id from public.credenciales_miembro c where c.iglesia_id = v_iglesia and c.miembro_id = p_miembro;
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function private.retirar_credencial(p_miembro uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not (select private.tiene_permiso('credenciales.gestionar')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  delete from public.credenciales_miembro where miembro_id = p_miembro and iglesia_id = (select private.get_iglesia_id());
end;
$$;

-- 4. Escanear: marca la asistencia del miembro dueno de la credencial en un evento de la iglesia de quien escanea.
--    Exige el mismo permiso que marcar a mano: asistencia.registrar, o asistencia.registrar_propia para quien lidera la casa
--    del evento y solo con miembros de esa casa. Responde con el estado y el nombre, para que quien escanea lo confirme.
create or replace function private.registrar_asistencia_credencial(p_evento uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_iglesia uuid := (select private.get_iglesia_id());
  e record;
  m record;
  v_id uuid;
  v_todo boolean;
begin
  -- Sin el modulo de credenciales (o con la iglesia inactiva) no se escanea, aunque se tenga permiso de asistencia
  if not (select private.tiene_modulo('credenciales')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  select ev.id, ev.cancelado, ev.casa_oracion_id into e
    from public.eventos ev where ev.id = p_evento and ev.iglesia_id = v_iglesia;
  if not found then raise exception 'EVENTO_NO_EXISTE' using errcode = 'P0002'; end if;
  v_todo := (select private.tiene_permiso('asistencia.registrar'));
  if not v_todo and not ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(e.casa_oracion_id)) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  if e.cancelado then return jsonb_build_object('estado', 'cancelado'); end if;

  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then return jsonb_build_object('estado', 'desconocida'); end if;
  select mi.id, mi.nombre, mi.apellido, mi.activo, mi.casa_oracion_id into m
    from public.credenciales_miembro c
    join public.miembros mi on mi.iglesia_id = c.iglesia_id and mi.id = c.miembro_id
   where c.token = p_token and c.iglesia_id = v_iglesia;
  if not found then return jsonb_build_object('estado', 'desconocida'); end if;
  if not v_todo and m.casa_oracion_id is distinct from e.casa_oracion_id then
    return jsonb_build_object('estado', 'fuera_de_casa');
  end if;
  if not m.activo then return jsonb_build_object('estado', 'inactivo'); end if;

  insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente)
    values (v_iglesia, p_evento, m.id, true)
    on conflict (evento_id, miembro_id) do update set presente = true, registrado_por = auth.uid()
      where public.asistencia_evento.presente = false
    returning id into v_id;
  return jsonb_build_object('estado', case when v_id is null then 'ya_registrado' else 'registrado' end,
                            'nombre', btrim(m.nombre || ' ' || m.apellido));
end;
$$;

revoke all on function private.emitir_credencial(uuid, boolean), private.retirar_credencial(uuid),
  private.registrar_asistencia_credencial(uuid, text) from public, anon;
grant execute on function private.emitir_credencial(uuid, boolean), private.retirar_credencial(uuid),
  private.registrar_asistencia_credencial(uuid, text) to authenticated;

create or replace function public.emitir_credencial(p_miembro uuid, p_renovar boolean default false)
returns uuid language sql set search_path to '' as $$ select private.emitir_credencial(p_miembro, p_renovar) $$;
create or replace function public.retirar_credencial(p_miembro uuid)
returns void language sql set search_path to '' as $$ select private.retirar_credencial(p_miembro) $$;
create or replace function public.registrar_asistencia_credencial(p_evento uuid, p_token text)
returns jsonb language sql set search_path to '' as $$ select private.registrar_asistencia_credencial(p_evento, p_token) $$;
revoke all on function public.emitir_credencial(uuid, boolean), public.retirar_credencial(uuid),
  public.registrar_asistencia_credencial(uuid, text) from public, anon;
grant execute on function public.emitir_credencial(uuid, boolean), public.retirar_credencial(uuid),
  public.registrar_asistencia_credencial(uuid, text) to authenticated;
