-- Motor de formacion: programas configurables por iglesia, con lecciones, inscripcion de miembros y avance.
-- La finalizacion de un programa se calcula siempre desde sus lecciones y nadie puede fijarla a mano:
-- los certificados (siguiente cambio) dependen de que "completado" no se pueda falsificar.
-- Convive con progreso_formacion, el seguimiento fijo por niveles que ya existia.

-- 1. Permiso nuevo (el modulo formacion ya existe y ya tiene formacion.ver y formacion.actualizar)
insert into public.permisos (clave, modulo, descripcion, sensible) values
  ('formacion.programas', 'formacion', 'Crear y editar programas de formacion y sus lecciones', false)
on conflict (clave) do nothing;

-- 2. Tablas. Las claves foraneas llevan iglesia_id y el avance lleva tambien programa_id, de modo que
--    la propia base impide mezclar iglesias o apuntar a una leccion de otro programa.
create table public.programas_formacion (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  nombre text not null check (length(btrim(nombre)) between 1 and 120),
  descripcion text check (length(descripcion) <= 1000),
  activo boolean not null default true,
  orden integer not null default 0,
  created_at timestamptz not null default now(),
  unique (iglesia_id, id)
);

create table public.programa_lecciones (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  programa_id uuid not null,
  orden integer not null default 0,
  titulo text not null check (length(btrim(titulo)) between 1 and 150),
  descripcion text check (length(descripcion) <= 1000),
  unique (iglesia_id, programa_id, id),
  constraint programa_lecciones_programa_fk foreign key (iglesia_id, programa_id)
    references public.programas_formacion (iglesia_id, id) on delete cascade
);
create index programa_lecciones_programa_idx on public.programa_lecciones (iglesia_id, programa_id, orden);

create table public.inscripciones_formacion (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  programa_id uuid not null,
  miembro_id uuid not null,
  estado text not null default 'en_curso' check (estado in ('en_curso', 'completado', 'abandonado')),
  inscrito_en timestamptz not null default now(),
  completado_en timestamptz,
  unique (programa_id, miembro_id),
  unique (iglesia_id, programa_id, id),
  constraint inscripciones_formacion_programa_fk foreign key (iglesia_id, programa_id)
    references public.programas_formacion (iglesia_id, id) on delete cascade,
  constraint inscripciones_formacion_miembro_fk foreign key (iglesia_id, miembro_id)
    references public.miembros (iglesia_id, id) on delete cascade
);
create index inscripciones_formacion_miembro_idx on public.inscripciones_formacion (iglesia_id, miembro_id);

create table public.avance_formacion (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  programa_id uuid not null,
  inscripcion_id uuid not null,
  leccion_id uuid not null,
  completada_en timestamptz not null default now(),
  registrado_por uuid default auth.uid(),
  unique (inscripcion_id, leccion_id),
  constraint avance_formacion_inscripcion_fk foreign key (iglesia_id, programa_id, inscripcion_id)
    references public.inscripciones_formacion (iglesia_id, programa_id, id) on delete cascade,
  constraint avance_formacion_leccion_fk foreign key (iglesia_id, programa_id, leccion_id)
    references public.programa_lecciones (iglesia_id, programa_id, id) on delete cascade
);
create index avance_formacion_inscripcion_idx on public.avance_formacion (iglesia_id, inscripcion_id);
create index avance_formacion_leccion_idx on public.avance_formacion (iglesia_id, programa_id, leccion_id);

-- 3. Finalizacion calculada. Un programa sin lecciones nunca se completa.
create or replace function private.recalcular_inscripcion(p_inscripcion uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v record; n_total integer; n_hechas integer;
begin
  select i.iglesia_id, i.programa_id, i.estado into v from public.inscripciones_formacion i where i.id = p_inscripcion;
  if not found then return; end if;
  select count(*) into n_total from public.programa_lecciones l where l.iglesia_id = v.iglesia_id and l.programa_id = v.programa_id;
  select count(*) into n_hechas from public.avance_formacion a where a.inscripcion_id = p_inscripcion;
  if n_total > 0 and n_hechas >= n_total then
    update public.inscripciones_formacion set estado = 'completado', completado_en = coalesce(completado_en, now())
      where id = p_inscripcion and estado <> 'completado';
  elsif v.estado = 'completado' then
    update public.inscripciones_formacion set estado = 'en_curso', completado_en = null where id = p_inscripcion;
  end if;
end $$;
revoke all on function private.recalcular_inscripcion(uuid) from public, anon, authenticated, service_role;

create or replace function private.trg_avance_recalcula()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.recalcular_inscripcion(coalesce(new.inscripcion_id, old.inscripcion_id));
  return null;
end $$;
revoke all on function private.trg_avance_recalcula() from public, anon, authenticated, service_role;
create trigger avance_formacion_recalcula after insert or delete on public.avance_formacion
  for each row execute function private.trg_avance_recalcula();

-- Añadir o quitar una leccion cambia el total: se recalculan las inscripciones del programa
create or replace function private.trg_leccion_recalcula()
returns trigger language plpgsql security definer set search_path to '' as $$
declare r record;
begin
  for r in select i.id from public.inscripciones_formacion i
           where i.iglesia_id = coalesce(new.iglesia_id, old.iglesia_id) and i.programa_id = coalesce(new.programa_id, old.programa_id)
  loop
    perform private.recalcular_inscripcion(r.id);
  end loop;
  return null;
end $$;
revoke all on function private.trg_leccion_recalcula() from public, anon, authenticated, service_role;
create trigger programa_lecciones_recalcula after insert or delete on public.programa_lecciones
  for each row execute function private.trg_leccion_recalcula();

-- Nadie fija a mano estado completado ni su fecha: solo lo hace el recalculo (que corre dentro de otro disparador).
create or replace function private.guardar_inscripcion()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null or pg_trigger_depth() > 1 then return new; end if;
  if tg_op = 'INSERT' then
    new.estado := 'en_curso';
    new.completado_en := null;
  elsif new.completado_en is distinct from old.completado_en or (new.estado = 'completado') is distinct from (old.estado = 'completado') then
    raise exception 'La finalizacion de un programa se calcula con sus lecciones';
  end if;
  return new;
end $$;
revoke all on function private.guardar_inscripcion() from public, anon, authenticated, service_role;
create trigger inscripciones_formacion_guardar before insert or update on public.inscripciones_formacion
  for each row execute function private.guardar_inscripcion();

-- 4. Seguridad por filas: leer exige formacion.ver; editar programas, formacion.programas; inscribir y avanzar, formacion.actualizar
alter table public.programas_formacion enable row level security;
alter table public.programa_lecciones enable row level security;
alter table public.inscripciones_formacion enable row level security;
alter table public.avance_formacion enable row level security;

create policy programas_formacion_ver on public.programas_formacion for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.ver')));
create policy programas_formacion_crear on public.programas_formacion for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.programas')));
create policy programas_formacion_editar on public.programas_formacion for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.programas')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy programas_formacion_borrar on public.programas_formacion for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.programas')));

create policy programa_lecciones_ver on public.programa_lecciones for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.ver')));
create policy programa_lecciones_crear on public.programa_lecciones for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.programas')));
create policy programa_lecciones_editar on public.programa_lecciones for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.programas')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy programa_lecciones_borrar on public.programa_lecciones for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.programas')));

create policy inscripciones_formacion_ver on public.inscripciones_formacion for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.ver')));
create policy inscripciones_formacion_crear on public.inscripciones_formacion for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.actualizar')));
create policy inscripciones_formacion_editar on public.inscripciones_formacion for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.actualizar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy inscripciones_formacion_borrar on public.inscripciones_formacion for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.actualizar')));

create policy avance_formacion_ver on public.avance_formacion for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.ver')));
create policy avance_formacion_crear on public.avance_formacion for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.actualizar')));
create policy avance_formacion_borrar on public.avance_formacion for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('formacion.actualizar')));

grant select, insert, update, delete on public.programas_formacion, public.programa_lecciones, public.inscripciones_formacion to authenticated;
grant select, insert, delete on public.avance_formacion to authenticated;
grant all on public.programas_formacion, public.programa_lecciones, public.inscripciones_formacion, public.avance_formacion to service_role;

-- 5. Permiso para los roles de sistema, tambien en las iglesias que ya existen
create or replace function private.sembrar_formacion(p_iglesia uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, 'formacion.programas'
    from public.roles r
    where r.iglesia_id = p_iglesia and r.clave in ('administrador', 'coadministrador', 'lider_escuela')
  on conflict do nothing;
end $$;
revoke all on function private.sembrar_formacion(uuid) from public, anon, authenticated;
grant execute on function private.sembrar_formacion(uuid) to service_role;

create or replace function private.trg_sembrar_roles()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  perform private.sembrar_formacion(new.id);
  return new;
end $$;

select private.sembrar_formacion(id) from public.iglesias;
