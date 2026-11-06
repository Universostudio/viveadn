-- Certificados de formacion con codigo de verificacion (QR).
-- Solo se emite un certificado para una inscripcion completada, y solo mediante emitir_certificado: nadie inserta filas
-- a mano, asi que el titular y el programa que se ven en la verificacion son los de la emision y no se pueden falsificar.
-- La verificacion publica muestra el nombre y la inicial del apellido (o solo el alias en una iglesia en modo alias),
-- nunca el nombre completo ni ningun otro dato de la persona.

-- 1. Permiso nuevo y su semilla en los roles de sistema, tambien en las iglesias que ya existen
insert into public.permisos (clave, modulo, descripcion, sensible) values
  ('formacion.certificar', 'formacion', 'Emitir y revocar certificados de formacion', false)
on conflict (clave) do nothing;

create or replace function private.sembrar_formacion(p_iglesia uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, p.permiso
    from public.roles r
    cross join (values ('formacion.programas'), ('formacion.certificar')) as p(permiso)
    where r.iglesia_id = p_iglesia and r.clave in ('administrador', 'coadministrador', 'lider_escuela')
  on conflict do nothing;
end $$;
revoke all on function private.sembrar_formacion(uuid) from public, anon, authenticated;
grant execute on function private.sembrar_formacion(uuid) to service_role;
select private.sembrar_formacion(id) from public.iglesias;

-- 2. Tabla. Una inscripcion tiene como mucho un certificado.
create table public.certificados (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  programa_id uuid not null,
  inscripcion_id uuid not null,
  miembro_id uuid not null,
  codigo text not null default replace(gen_random_uuid()::text, '-', '') check (codigo ~ '^[0-9a-f]{32}$'),
  titular text not null check (length(btrim(titular)) between 1 and 200),
  programa_nombre text not null check (length(btrim(programa_nombre)) between 1 and 120),
  emitido_en timestamptz not null default now(),
  emitido_por uuid default auth.uid(),
  revocado_en timestamptz,
  unique (codigo),
  unique (inscripcion_id),
  unique (iglesia_id, id),
  constraint certificados_inscripcion_fk foreign key (iglesia_id, programa_id, inscripcion_id)
    references public.inscripciones_formacion (iglesia_id, programa_id, id) on delete cascade,
  constraint certificados_miembro_fk foreign key (iglesia_id, miembro_id)
    references public.miembros (iglesia_id, id) on delete cascade
);
create index certificados_programa_idx on public.certificados (iglesia_id, programa_id);
create index certificados_miembro_idx on public.certificados (iglesia_id, miembro_id);

alter table public.certificados enable row level security;
-- Solo lectura directa: emitir y revocar pasan por las funciones de abajo
create policy certificados_ver on public.certificados for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.ver')));
grant select on public.certificados to authenticated;
grant all on public.certificados to service_role;

-- 3. Emitir: exige permiso, que la inscripcion sea de la iglesia de quien llama y que este completada. Es idempotente.
--    La logica privilegiada vive en private (SECURITY DEFINER); la API publica es un envoltorio sin privilegios.
create or replace function private.emitir_certificado(p_inscripcion uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $$
declare
  v record;
  v_titular text;
  v_id uuid;
begin
  if not (select private.tiene_permiso('formacion.certificar')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  select i.iglesia_id, i.programa_id, i.miembro_id, i.estado, p.nombre as programa, m.nombre, m.apellido, g.modo_alias
    into v
    from public.inscripciones_formacion i
    join public.programas_formacion p on p.iglesia_id = i.iglesia_id and p.id = i.programa_id
    join public.miembros m on m.iglesia_id = i.iglesia_id and m.id = i.miembro_id
    join public.iglesias g on g.id = i.iglesia_id
   where i.id = p_inscripcion and i.iglesia_id = (select private.get_iglesia_id());
  if not found then raise exception 'INSCRIPCION_NO_EXISTE' using errcode = 'P0002'; end if;
  if v.estado <> 'completado' then raise exception 'NO_COMPLETADO' using errcode = 'check_violation'; end if;
  v_titular := case when v.modo_alias or btrim(v.apellido) = '' then btrim(v.nombre)
                    else btrim(v.nombre) || ' ' || upper(left(btrim(v.apellido), 1)) || '.' end;
  insert into public.certificados (iglesia_id, programa_id, inscripcion_id, miembro_id, titular, programa_nombre)
    values (v.iglesia_id, v.programa_id, p_inscripcion, v.miembro_id, v_titular, v.programa)
    on conflict (inscripcion_id) do nothing
    returning id into v_id;
  if v_id is null then
    select c.id into v_id from public.certificados c where c.inscripcion_id = p_inscripcion;
  end if;
  return v_id;
end;
$$;

-- 4. Revocar o restaurar un certificado de la propia iglesia
create or replace function private.revocar_certificado(p_id uuid, p_revocar boolean)
returns void
language plpgsql
security definer
set search_path to ''
as $$
begin
  if not (select private.tiene_permiso('formacion.certificar')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  update public.certificados
     set revocado_en = case when p_revocar then coalesce(revocado_en, now()) else null end
   where id = p_id and iglesia_id = (select private.get_iglesia_id());
  if not found then raise exception 'CERTIFICADO_NO_EXISTE' using errcode = 'P0002'; end if;
end;
$$;
revoke all on function private.emitir_certificado(uuid), private.revocar_certificado(uuid, boolean) from public, anon;
grant execute on function private.emitir_certificado(uuid), private.revocar_certificado(uuid, boolean) to authenticated;

create or replace function public.emitir_certificado(p_inscripcion uuid)
returns uuid language sql set search_path to '' as $$ select private.emitir_certificado(p_inscripcion) $$;
create or replace function public.revocar_certificado(p_id uuid, p_revocar boolean default true)
returns void language sql set search_path to '' as $$ select private.revocar_certificado(p_id, p_revocar) $$;
revoke all on function public.emitir_certificado(uuid), public.revocar_certificado(uuid, boolean) from public, anon;
grant execute on function public.emitir_certificado(uuid), public.revocar_certificado(uuid, boolean) to authenticated;

-- 5. Verificacion publica. Solo la ejecuta el servidor (la funcion de borde): devuelve lo minimo.
--    Un certificado revocado no muestra al titular. Se sigue verificando aunque la iglesia este en receso.
create or replace function public.info_certificado(p_codigo text)
returns jsonb
language sql
stable
set search_path to ''
as $$
  select case when c.revocado_en is null
           then jsonb_build_object('estado', 'valido', 'iglesia', i.nombre, 'programa', c.programa_nombre, 'titular', c.titular, 'emitido_en', c.emitido_en)
           else jsonb_build_object('estado', 'revocado', 'iglesia', i.nombre, 'programa', c.programa_nombre, 'emitido_en', c.emitido_en, 'revocado_en', c.revocado_en)
         end
    from public.certificados c
    join public.iglesias i on i.id = c.iglesia_id
   where c.codigo = p_codigo
$$;
revoke all on function public.info_certificado(text) from public, anon, authenticated;
grant execute on function public.info_certificado(text) to service_role;
