-- Vive ADN, paquete de aplicación 04 de 07. Aplicar en orden y detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261105235306_motor_formacion.sql (sha256 261511bfbe04) =====
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

-- ===== migrations/20261106000222_motor_formacion_endurecer.sql (sha256 5abd859d9240) =====
-- Endurece el motor de formacion tras la revision:
--  1. Dos avances simultaneos que completan un programa dejaban la inscripcion en curso: cada transaccion veia solo el suyo.
--     El recalculo bloquea ahora la fila de la inscripcion, de modo que el segundo espera al primero y ve su avance.
--  2. Una inscripcion completada podia traspasarse a otro miembro cambiando miembro_id, con su avance y su fecha.
--     Quien inscribe, programa y miembro no se pueden cambiar: se borra la inscripcion y se crea otra.
--  3. Mover una leccion a otro programa no recalculaba ninguno de los dos. La leccion ya no cambia de programa.

create or replace function private.recalcular_inscripcion(p_inscripcion uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v record; n_total integer; n_hechas integer;
begin
  -- El cerrojo serializa los recalculos de una misma inscripcion; despues de esperarlo, los conteos ven lo ya confirmado
  select i.iglesia_id, i.programa_id, i.estado into v from public.inscripciones_formacion i where i.id = p_inscripcion for update;
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

create or replace function private.guardar_inscripcion()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null or pg_trigger_depth() > 1 then return new; end if;
  if tg_op = 'INSERT' then
    new.estado := 'en_curso';
    new.completado_en := null;
  else
    if new.iglesia_id is distinct from old.iglesia_id or new.programa_id is distinct from old.programa_id or new.miembro_id is distinct from old.miembro_id then
      raise exception 'Una inscripcion no cambia de programa ni de miembro: se borra y se crea otra';
    end if;
    if new.completado_en is distinct from old.completado_en or (new.estado = 'completado') is distinct from (old.estado = 'completado') then
      raise exception 'La finalizacion de un programa se calcula con sus lecciones';
    end if;
  end if;
  return new;
end $$;
revoke all on function private.guardar_inscripcion() from public, anon, authenticated, service_role;

create or replace function private.guardar_leccion()
returns trigger language plpgsql set search_path to '' as $$
begin
  if new.iglesia_id is distinct from old.iglesia_id or new.programa_id is distinct from old.programa_id then
    raise exception 'Una leccion no cambia de programa: se borra y se crea en el otro';
  end if;
  return new;
end $$;
revoke all on function private.guardar_leccion() from public, anon, authenticated, service_role;
create trigger programa_lecciones_guardar before update on public.programa_lecciones
  for each row execute function private.guardar_leccion();

-- ===== migrations/20261106000439_motor_formacion_cerrojo.sql (sha256 a1235c1734fe) =====
-- El cerrojo del recalculo con FOR UPDATE provocaba un bloqueo mutuo (deadlock) entre dos avances simultaneos:
-- al insertar el avance, la clave foranea toma FOR KEY SHARE sobre la inscripcion, y despues las dos transacciones
-- pedian FOR UPDATE, que choca con el KEY SHARE de la otra. FOR NO KEY UPDATE se serializa con otro recalculo (choca
-- consigo mismo) pero es compatible con el KEY SHARE de la clave foranea, y basta porque nunca se cambia la clave.
create or replace function private.recalcular_inscripcion(p_inscripcion uuid)
returns void language plpgsql security definer set search_path to '' as $$
declare v record; n_total integer; n_hechas integer;
begin
  select i.iglesia_id, i.programa_id, i.estado into v from public.inscripciones_formacion i where i.id = p_inscripcion for no key update;
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

-- ===== migrations/20261106011008_certificados_formacion.sql (sha256 0b7abe645b29) =====
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

-- ===== migrations/20261111120000_adn_ciclo_vida.sql (sha256 f51290e88822) =====
-- Ciclo de vida de la iglesia, segunda parte: borrado suave con plazo de gracia fijo de 30 dias,
-- recuperacion, purga de lo vencido y registro de auditoria que sobrevive a la purga.
-- Se apoya en lo que ya existe (etapa, borrado_programado_en, borrar_iglesia) y no lo renombra.
-- Reversion: supabase/reversiones/20261111120000_adn_ciclo_vida.down.sql (probada por tests/adn_reversion.sh).
--
-- Un borrado suave deja la iglesia en `suspendida` (la base ya le corta el acceso a sus datos de negocio),
-- fija `borrado_programado_en` a 30 dias y guarda en `adn_estado_previo` la etapa y la prueba que tenia, para
-- poder devolverla tal cual. Pasado el plazo ya no se puede recuperar y la purga la borra por completo.

-- 1. Marcas del borrado suave en la iglesia
alter table public.iglesias
  add column adn_borrada_en timestamptz,
  add column adn_borrada_por uuid,
  add column adn_estado_previo jsonb,
  add constraint adn_iglesias_borrada_check
    check (adn_borrada_en is null or (etapa in ('receso', 'suspendida') and borrado_programado_en is not null));

-- Si la iglesia sale de receso o suspension por cualquier via, las marcas se limpian solas. El nombre empieza por zz
-- para que corra despues de iglesias_sincronizar_etapa, que es quien puede cambiar la etapa.
create or replace function private.adn_coherencia_borrado()
returns trigger language plpgsql set search_path to '' as $$
begin
  if new.etapa not in ('receso', 'suspendida') then
    new.adn_borrada_en := null;
    new.adn_borrada_por := null;
    new.adn_estado_previo := null;
  end if;
  return new;
end $$;
revoke all on function private.adn_coherencia_borrado() from public, anon, authenticated, service_role;

create trigger iglesias_zz_adn_coherencia
  before insert or update on public.iglesias
  for each row execute function private.adn_coherencia_borrado();

-- Las marcas solo las cambia la plataforma, igual que la etapa y el borrado programado
create or replace function private.guardar_iglesia()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.plan is distinct from old.plan or new.activa is distinct from old.activa
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo
     or new.iglesia_madre_id is distinct from old.iglesia_madre_id or new.red_acceso is distinct from old.red_acceso
     or new.etapa is distinct from old.etapa or new.etapa_desde is distinct from old.etapa_desde
     or new.prueba_hasta is distinct from old.prueba_hasta
     or new.borrado_programado_en is distinct from old.borrado_programado_en
     or new.adn_borrada_en is distinct from old.adn_borrada_en
     or new.adn_borrada_por is distinct from old.adn_borrada_por
     or new.adn_estado_previo is distinct from old.adn_estado_previo then
    raise exception 'El plan, el estado, la etapa, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$$;

-- 2. Auditoria del ciclo de vida. Sin clave foranea a iglesias a proposito: debe sobrevivir a la purga.
--    No guarda datos de personas: solo la referencia de la iglesia, quien actuo, la fecha y conteos.
--    El motivo es texto libre de quien opera la plataforma: se anula al purgar por si contuviera algo personal.
create table public.adn_ciclo_auditoria (
  id bigint generated always as identity primary key,
  iglesia_ref uuid not null,
  accion text not null check (accion in ('borrado_suave', 'recuperacion', 'purga', 'purga_externa')),
  actor uuid,
  motivo text check (motivo is null or length(motivo) <= 500),
  detalle jsonb not null default '{}'::jsonb,
  ocurrido_en timestamptz not null default now()
);
create index adn_ciclo_auditoria_iglesia_idx on public.adn_ciclo_auditoria (iglesia_ref, ocurrido_en desc);

alter table public.adn_ciclo_auditoria enable row level security;  -- sin politicas: solo service_role
revoke all on public.adn_ciclo_auditoria from public, anon, authenticated;
revoke all on sequence public.adn_ciclo_auditoria_id_seq from public, anon, authenticated;
-- Solo se agrega y solo se puede anular el motivo: nada se edita ni se borra
grant select, insert on public.adn_ciclo_auditoria to service_role;
grant update (motivo) on public.adn_ciclo_auditoria to service_role;
grant usage, select on sequence public.adn_ciclo_auditoria_id_seq to service_role;

-- 3. Funciones. Las ejecuta solo service_role, desde la funcion de borde `plataforma`, que valida a quien llama.
create or replace function public.adn_auditar_ciclo(p_iglesia uuid, p_accion text, p_actor uuid, p_motivo text default null, p_detalle jsonb default '{}'::jsonb)
returns void language sql set search_path to '' as $$
  insert into public.adn_ciclo_auditoria (iglesia_ref, accion, actor, motivo, detalle)
  values (p_iglesia, p_accion, p_actor, p_motivo, coalesce(p_detalle, '{}'::jsonb))
$$;

-- Borrado suave: suspende la iglesia y fija el plazo de gracia de 30 dias. Devuelve la fecha de la purga.
create or replace function public.adn_borrar_suave(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns timestamptz language plpgsql set search_path to '' as $$
declare
  v record;
  limite timestamptz := now() + interval '30 days';
begin
  select etapa, prueba_hasta, adn_borrada_en into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.adn_borrada_en is not null then raise exception 'ADN_YA_BORRADA'; end if;
  update public.iglesias set
    adn_borrada_en = now(), adn_borrada_por = p_actor,
    adn_estado_previo = jsonb_build_object('etapa', v.etapa, 'prueba_hasta', v.prueba_hasta),
    etapa = 'suspendida', borrado_programado_en = limite
  where id = p_iglesia;
  perform public.adn_auditar_ciclo(p_iglesia, 'borrado_suave', p_actor, p_motivo,
    jsonb_build_object('plazo_dias', 30, 'etapa_previa', v.etapa, 'purga_el', limite));
  return limite;
end $$;

-- Recuperacion: solo dentro del plazo. Devuelve la iglesia a la etapa que tenia, con su prueba, y cancela la purga.
create or replace function public.adn_recuperar_iglesia(p_iglesia uuid, p_actor uuid, p_motivo text default null)
returns text language plpgsql set search_path to '' as $$
declare
  v record;
  destino text;
  prueba timestamptz;
begin
  select adn_borrada_en, borrado_programado_en, adn_estado_previo into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.adn_borrada_en is null then raise exception 'ADN_NO_BORRADA'; end if;
  if v.borrado_programado_en <= now() then raise exception 'ADN_PLAZO_VENCIDO'; end if;
  destino := coalesce(v.adn_estado_previo ->> 'etapa', 'activa');
  prueba := nullif(v.adn_estado_previo ->> 'prueba_hasta', '')::timestamptz;
  update public.iglesias set
    etapa = destino,
    prueba_hasta = case when destino = 'prueba' then prueba else null end,
    borrado_programado_en = null, adn_borrada_en = null, adn_borrada_por = null, adn_estado_previo = null
  where id = p_iglesia;
  perform public.adn_auditar_ciclo(p_iglesia, 'recuperacion', p_actor, p_motivo, jsonb_build_object('etapa_restaurada', destino));
  return destino;
end $$;

-- Iglesias en borrado suave cuyo plazo ya vencio, las mas antiguas primero
create or replace function public.adn_iglesias_vencidas()
returns setof uuid language sql stable set search_path to '' as $$
  select id from public.iglesias
  where adn_borrada_en is not null and borrado_programado_en <= now()
  order by borrado_programado_en
$$;

-- Purga de una iglesia vencida: borra sus filas (en cascada) y devuelve los usuarios de acceso que la funcion de
-- borde debe retirar de Auth. Deja en la auditoria solo conteos, sin datos de personas, y anula los motivos.
create or replace function public.adn_purgar_iglesia(p_iglesia uuid, p_actor uuid)
returns uuid[] language plpgsql set search_path to '' as $$
declare
  v record;
  miembros bigint;
  usuarios uuid[];
begin
  select adn_borrada_en, borrado_programado_en into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.adn_borrada_en is null then raise exception 'ADN_NO_BORRADA'; end if;
  if v.borrado_programado_en > now() then raise exception 'BORRADO_NO_VENCIDO' using errcode = 'check_violation'; end if;
  select count(*) into miembros from public.miembros where iglesia_id = p_iglesia;
  usuarios := public.borrar_iglesia(p_iglesia);
  update public.adn_ciclo_auditoria set motivo = null where iglesia_ref = p_iglesia;
  perform public.adn_auditar_ciclo(p_iglesia, 'purga', p_actor, null,
    jsonb_build_object('miembros_borrados', miembros, 'usuarios_a_retirar', coalesce(array_length(usuarios, 1), 0)));
  return usuarios;
end $$;

revoke all on function
  public.adn_auditar_ciclo(uuid, text, uuid, text, jsonb), public.adn_borrar_suave(uuid, uuid, text),
  public.adn_recuperar_iglesia(uuid, uuid, text), public.adn_iglesias_vencidas(), public.adn_purgar_iglesia(uuid, uuid)
  from public, anon, authenticated;
grant execute on function
  public.adn_auditar_ciclo(uuid, text, uuid, text, jsonb), public.adn_borrar_suave(uuid, uuid, text),
  public.adn_recuperar_iglesia(uuid, uuid, text), public.adn_iglesias_vencidas(), public.adn_purgar_iglesia(uuid, uuid)
  to service_role;

-- ===== migrations/20261111130000_adn_exportacion.sql (sha256 b75eb4ca2ece) =====
-- Exportacion completa de una iglesia en formato universal: JSON y un CSV por tabla, con manifiesto de cifras.
-- Reversion: supabase/reversiones/20261111130000_adn_exportacion.down.sql. No modifica exportar_iglesia.
--
-- adn_exportar_paquete devuelve, para una iglesia:
--   formato, exportado_en, iglesia, tablas   -> igual que exportar_iglesia (superconjunto, mismas claves)
--   manifiesto                               -> por tabla: filas, columnas con tipo, columnas omitidas, orden de carga,
--                                               huella (md5 del contenido) y md5 del CSV
--   csv                                      -> un CSV por tabla (RFC 4180, UTF-8, CRLF; NULL = campo vacio sin comillas,
--                                               cadena vacia = "")
-- El CSV se genera aqui, no en el navegador, para conservar exactamente la escala de los numericos y los tipos.
-- Nunca salen los secretos (token, token_hash, ip_hash) ni las marcas internas de borrado suave (adn_*).
-- adn_verificar_carga recalcula esas cifras en la base donde se cargo la exportacion y las compara con el manifiesto.

-- Un campo CSV a partir de un valor JSON
create or replace function public.adn_csv_campo(p_valor jsonb)
returns text language sql immutable set search_path to '' as $$
  select case
    when p_valor is null or jsonb_typeof(p_valor) = 'null' then ''
    else (
      select case when t = '' or t ~ '["\r\n,]' or t ~ '^\s|\s$' then '"' || replace(t, '"', '""') || '"' else t end
      from (select case jsonb_typeof(p_valor) when 'string' then p_valor #>> '{}' else p_valor::text end as t) x
    )
  end
$$;

-- La fila tal como sale en la exportacion: sin las columnas omitidas y sin secretos anidados en `detalle`.
-- La usan la exportacion y la verificacion, para que las huellas se calculen igual.
create or replace function public.adn_fila_exportable(p_fila jsonb, p_omitidas text[])
returns jsonb language sql immutable set search_path to '' as $$
  select case
    when jsonb_typeof(p_fila -> 'detalle') = 'object'
      then jsonb_set(p_fila - p_omitidas, '{detalle}', (p_fila -> 'detalle') - array['token', 'token_hash', 'ip_hash'])
    else p_fila - p_omitidas
  end
$$;

-- Tablas que entran en la exportacion y como se filtran por iglesia ($1 es el id de la iglesia):
-- la propia iglesia, toda tabla con iglesia_id y rol_permisos (que cuelga de roles)
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

create or replace function public.adn_exportar_paquete(p_iglesia uuid)
returns jsonb language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  -- Columnas que nunca salen: secretos y marcas internas del borrado suave
  secretos constant text[] := array['token', 'token_hash', 'ip_hash', 'adn_borrada_en', 'adn_borrada_por', 'adn_estado_previo'];
  r record;
  cols jsonb;
  nombres text[];
  omitidas text[];
  filas jsonb;
  csv text;
  tablas jsonb := '{}'::jsonb;
  csvs jsonb := '{}'::jsonb;
  man jsonb := '[]'::jsonb;
  total bigint := 0;
  ig jsonb;
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;

  -- Orden de carga: una tabla va despues de las que referencia (las autorreferencias no cuentan)
  for r in
    with recursive tabla as (select x.nombre, x.filtro from public.adn_tablas_exportables() x),
    fk as (
      select co.relname::text collate "default" as origen, cd.relname::text collate "default" as destino
      from pg_constraint c
      join pg_class co on co.oid = c.conrelid join pg_class cd on cd.oid = c.confrelid
      where c.contype = 'f' and c.connamespace = 'public'::regnamespace and c.conrelid <> c.confrelid
    ),
    niv(nombre, n) as (
      select nombre, 0 from tabla
      union
      select fk.origen, niv.n + 1 from niv join fk on fk.destino = niv.nombre
      where fk.origen in (select nombre from tabla) and niv.n < 50
    )
    select t.nombre, t.filtro, max(niv.n) as nivel
    from tabla t join niv on niv.nombre = t.nombre
    group by t.nombre, t.filtro
    order by max(niv.n), t.nombre
  loop
    select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text <> all (secretos)), '{}'),
           coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text = any (secretos)), '{}'),
           coalesce(jsonb_agg(jsonb_build_object('nombre', a.attname, 'tipo', format_type(a.atttypid, a.atttypmod), 'obligatoria', a.attnotnull)
                              order by a.attnum) filter (where a.attname::text <> all (secretos)), '[]')
      into nombres, omitidas, cols
      from pg_attribute a
      where a.attrelid = ('public.' || quote_ident(r.nombre))::regclass and a.attnum > 0 and not a.attisdropped;

    -- Filas en un orden estable para que dos exportaciones iguales den el mismo resultado
    execute format(
      'select coalesce(jsonb_agg(public.adn_fila_exportable(to_jsonb(t), $2) order by to_jsonb(t)::text), ''[]''::jsonb) from public.%I t where %s',
      r.nombre, r.filtro) into filas using p_iglesia, omitidas;

    csv := (select string_agg(public.adn_csv_campo(to_jsonb(c.n)), ',' order by c.ord) from unnest(nombres) with ordinality c(n, ord))
           || E'\r\n'
           || coalesce((
                select string_agg(
                  (select string_agg(public.adn_csv_campo(e.f -> c.n), ',' order by c.ord) from unnest(nombres) with ordinality c(n, ord)),
                  E'\r\n' order by e.fo)
                from jsonb_array_elements(filas) with ordinality e(f, fo)
              ) || E'\r\n', '');

    if r.nombre = 'iglesias' then ig := filas -> 0; end if;
    csvs := csvs || jsonb_build_object(r.nombre, csv);
    -- La iglesia va en su propio campo, no dentro de `tablas`, igual que en exportar_iglesia
    if r.nombre <> 'iglesias' then tablas := tablas || jsonb_build_object(r.nombre, filas); end if;
    total := total + jsonb_array_length(filas);
    man := man || jsonb_build_array(jsonb_build_object(
      'nombre', r.nombre, 'orden_carga', r.nivel, 'archivo_csv', 'csv/' || r.nombre || '.csv',
      'filas', jsonb_array_length(filas), 'columnas', cols, 'omitidas', to_jsonb(omitidas),
      'huella', (select md5(coalesce(string_agg(md5(e.f::text), ',' order by md5(e.f::text)), '')) from jsonb_array_elements(filas) e(f)),
      'md5_csv', md5(csv)));
  end loop;

  return jsonb_build_object(
    'formato', 'viveadn-exportacion-2',
    'exportado_en', now(),
    'iglesia', ig,
    'tablas', tablas,
    'csv', csvs,
    'manifiesto', jsonb_build_object(
      'formato', 'viveadn-exportacion-2', 'iglesia_id', p_iglesia, 'exportado_en', now(),
      'codificacion', 'UTF-8 sin BOM', 'separador', ',', 'fin_de_linea', 'CRLF',
      'nulos', 'campo vacio sin comillas; la cadena vacia va entre comillas ("")',
      'total_filas', total, 'tablas', man));
end $$;

-- Recalcula en la base actual las cifras del manifiesto, tabla a tabla, para la iglesia del manifiesto.
-- Devuelve una fila por tabla: filas y huella esperadas frente a las cargadas.
create or replace function public.adn_verificar_carga(p_manifiesto jsonb)
returns table (tabla text, filas_esperadas bigint, filas_cargadas bigint, huella_ok boolean, ok boolean)
language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  t jsonb;
  f record;
  filas bigint;
  huella text;
  omitidas text[];
  iglesia uuid := (p_manifiesto ->> 'iglesia_id')::uuid;
begin
  for t in select * from jsonb_array_elements(p_manifiesto -> 'tablas') loop
    select * into f from public.adn_tablas_exportables() x where x.nombre = t ->> 'nombre';
    if not found then
      tabla := t ->> 'nombre'; filas_esperadas := (t ->> 'filas')::bigint; filas_cargadas := 0; huella_ok := false; ok := false;
      return next; continue;
    end if;
    select coalesce(array_agg(v), '{}') into omitidas from jsonb_array_elements_text(t -> 'omitidas') v;
    execute format(
      'select count(*), md5(coalesce(string_agg(md5(public.adn_fila_exportable(to_jsonb(x), $2)::text), '','' order by md5(public.adn_fila_exportable(to_jsonb(x), $2)::text)), '''')) from public.%I x where %s',
      f.nombre, f.filtro) into filas, huella using iglesia, omitidas;
    tabla := f.nombre;
    filas_esperadas := (t ->> 'filas')::bigint;
    filas_cargadas := filas;
    huella_ok := huella = (t ->> 'huella');
    ok := filas = filas_esperadas and huella_ok;
    return next;
  end loop;
end $$;

revoke all on function
  public.adn_csv_campo(jsonb), public.adn_fila_exportable(jsonb, text[]), public.adn_tablas_exportables(), public.adn_exportar_paquete(uuid), public.adn_verificar_carga(jsonb)
  from public, anon, authenticated;
grant execute on function
  public.adn_csv_campo(jsonb), public.adn_fila_exportable(jsonb, text[]), public.adn_tablas_exportables(), public.adn_exportar_paquete(uuid), public.adn_verificar_carga(jsonb)
  to service_role;

-- ===== migrations/20261111140000_adn_importar_contactos.sql (sha256 37b24f172370) =====
-- Importador de contactos (formato Google Contacts): tabla de datos de contacto adicionales y funcion de
-- importacion atomica, con deduplicacion por correo y filtros que no dependen del navegador.
-- Reversion: supabase/reversiones/20261111140000_adn_importar_contactos.down.sql.
--
-- `miembros` guarda un correo y un telefono. Un contacto de Google puede traer dos correos, tres telefonos,
-- direcciones y etiquetas: lo que no cabe en `miembros` va a `adn_miembro_contactos`, una fila por dato.
-- Nunca se importan contraseñas: la funcion solo acepta una lista cerrada de campos y descarta cualquier nota que
-- parezca contener una clave, aunque el archivo llegue de un cliente modificado.

create table public.adn_miembro_contactos (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  tipo text not null check (tipo in ('correo', 'telefono', 'direccion', 'etiqueta')),
  etiqueta text check (etiqueta is null or char_length(etiqueta) <= 60),
  valor text not null check (char_length(valor) between 1 and 500),
  orden smallint not null default 0,
  created_at timestamptz not null default now(),
  constraint adn_miembro_contactos_miembro_fk foreign key (iglesia_id, miembro_id)
    references public.miembros (iglesia_id, id) on delete cascade,
  constraint adn_miembro_contactos_unico unique (miembro_id, tipo, valor)
);
create index adn_miembro_contactos_miembro_idx on public.adn_miembro_contactos (iglesia_id, miembro_id);
create index adn_miembro_contactos_valor_idx on public.adn_miembro_contactos (iglesia_id, tipo, lower(valor));

grant select, insert, update, delete on public.adn_miembro_contactos to authenticated, service_role;
alter table public.adn_miembro_contactos enable row level security;

-- Se ve lo que se ve del miembro (la politica de miembros se aplica a la subconsulta); se escribe con los
-- permisos de miembros. Siempre dentro de la iglesia de quien pregunta.
create policy adn_miembro_contactos_ver on public.adn_miembro_contactos for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and exists (select 1 from public.miembros m where m.id = miembro_id and m.iglesia_id = iglesia_id));
create policy adn_miembro_contactos_crear on public.adn_miembro_contactos for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id())
              and ((select private.tiene_permiso('miembros.crear')) or (select private.tiene_permiso('miembros.editar'))));
create policy adn_miembro_contactos_editar on public.adn_miembro_contactos for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('miembros.editar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy adn_miembro_contactos_borrar on public.adn_miembro_contactos for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('miembros.editar')));

-- Telefono en forma canonica: solo digitos y un + inicial. Es la misma que calcula la web
create or replace function public.adn_telefono_canonico(p_valor text)
returns text language sql immutable set search_path to '' as $$
  select case when left(btrim(coalesce(p_valor, '')), 1) = '+'
              then '+' || regexp_replace(substr(btrim(p_valor), 2), '[^0-9]', '', 'g')
              else regexp_replace(coalesce(p_valor, ''), '[^0-9]', '', 'g') end
$$;
revoke all on function public.adn_telefono_canonico(text) from public, anon;
grant execute on function public.adn_telefono_canonico(text) to authenticated, service_role;

-- Importacion atomica de un lote de hasta 1000 contactos ya limpiados por la web. Cada elemento:
--   { nombre, apellido, email, telefono, fecha_nacimiento, notas,
--     contactos: [ { tipo: correo|telefono|direccion|etiqueta, etiqueta, valor } ] }
-- Se ejecuta con los permisos de quien llama (seguridad por filas, limites del plan y disparadores incluidos).
-- Duplicados, en este orden: un correo ya existente (principal o adicional) en la iglesia; si el contacto no tiene
-- correo, un telefono ya existente; si no tiene ni correo ni telefono, el mismo nombre. Tambien entre las filas del lote.
-- Devuelve conteos. Si algo falla (p. ej. el limite del plan), no se importa nada de ese lote.
create or replace function public.adn_importar_miembros(p_filas jsonb, p_origen text default 'google')
returns jsonb language plpgsql set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  hoy date := (now() at time zone 'UTC')::date;
  f jsonb;
  c jsonb;
  nuevo uuid;
  nombre text; apellido text; email text; tel text; nac date; notas text;
  correos text[]; telefonos text[];
  clave_nombre text;
  existe boolean;
  n_ok int := 0; n_dup_correo int := 0; n_dup_tel int := 0; n_dup_nombre int := 0; n_invalidas int := 0; n_notas int := 0;
  extra_tipo text; extra_valor text; extra_etiqueta text; extra_tel text;
  orden int;
  -- Una nota que parece guardar una clave no se importa
  clave_re constant text := '\m(contrase(ñ|n)a|password|passwd|passcode|clave|pin|secreto?|secret)\s*[:=]';
  -- En este lote, para detectar repetidos entre sus propias filas
  vistos_correos text[] := '{}'; vistos_tel text[] := '{}'; vistos_nombre text[] := '{}';
begin
  if ig is null then raise exception 'ADN_SIN_IGLESIA'; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if coalesce((select modo_alias from public.iglesias where id = ig), false) then raise exception 'ADN_MODO_ALIAS'; end if;
  if p_origen is null or p_origen !~ '^[a-z0-9_-]{1,30}$' then raise exception 'ADN_ORIGEN_INVALIDO'; end if;
  if jsonb_typeof(p_filas) is distinct from 'array' or jsonb_array_length(p_filas) > 1000 then raise exception 'ADN_LOTE_INVALIDO'; end if;

  for f in select value from jsonb_array_elements(p_filas) loop
    nombre := left(btrim(coalesce(f ->> 'nombre', '')), 100);
    apellido := left(btrim(coalesce(f ->> 'apellido', '')), 100);
    if nombre = '' then n_invalidas := n_invalidas + 1; continue; end if;

    -- Correo principal y adicionales, en minusculas y con forma de correo
    correos := '{}';
    email := lower(btrim(coalesce(f ->> 'email', '')));
    if email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(email) <= 254 then correos := array[email]; else email := null; end if;
    -- Telefono principal y adicionales, solo digitos y un + inicial, entre 7 y 15 digitos
    telefonos := '{}';
    tel := public.adn_telefono_canonico(f ->> 'telefono');
    if tel ~ '^\+?[0-9]{7,15}$' and tel !~ '^\+?(.)\1+$' then telefonos := array[tel]; else tel := null; end if;
    for c in select value from jsonb_array_elements(case when jsonb_typeof(f -> 'contactos') = 'array' then f -> 'contactos' else '[]'::jsonb end) loop
      if c ->> 'tipo' = 'correo' then
        extra_valor := lower(btrim(coalesce(c ->> 'valor', '')));
        if extra_valor ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(extra_valor) <= 254 and not extra_valor = any (correos) then correos := correos || extra_valor; end if;
      elsif c ->> 'tipo' = 'telefono' then
        extra_tel := public.adn_telefono_canonico(c ->> 'valor');
        if extra_tel ~ '^\+?[0-9]{7,15}$' and extra_tel !~ '^\+?(.)\1+$' and not extra_tel = any (telefonos) then telefonos := telefonos || extra_tel; end if;
      end if;
    end loop;

    -- Duplicados
    existe := false;
    if array_length(correos, 1) > 0 then
      if correos && vistos_correos
         or exists (select 1 from public.miembros m where lower(m.email) = any (correos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'correo' and lower(x.valor) = any (correos)) then
        n_dup_correo := n_dup_correo + 1; continue;
      end if;
    elsif array_length(telefonos, 1) > 0 then
      if telefonos && vistos_tel
         or exists (select 1 from public.miembros m where public.adn_telefono_canonico(m.telefono) = any (telefonos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'telefono' and public.adn_telefono_canonico(x.valor) = any (telefonos)) then
        n_dup_tel := n_dup_tel + 1; continue;
      end if;
    else
      clave_nombre := lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
      if clave_nombre = any (vistos_nombre)
         or exists (select 1 from public.miembros m where lower(regexp_replace(btrim(m.nombre || ' ' || m.apellido), '\s+', ' ', 'g')) = clave_nombre) then
        n_dup_nombre := n_dup_nombre + 1; continue;
      end if;
    end if;

    -- Fecha de nacimiento: solo una fecha real entre 1900 y hoy
    nac := null;
    begin
      nac := nullif(btrim(coalesce(f ->> 'fecha_nacimiento', '')), '')::date;
      if nac < date '1900-01-01' or nac > hoy then nac := null; end if;
    exception when others then nac := null;
    end;

    notas := nullif(left(btrim(coalesce(f ->> 'notas', '')), 1000), '');
    if notas ~* clave_re then notas := null; n_notas := n_notas + 1; end if;

    nuevo := gen_random_uuid();
    insert into public.miembros (id, nombre, apellido, email, telefono, fecha_nacimiento, notas, activo)
    values (nuevo, nombre, apellido, correos[1], telefonos[1], nac, notas, true);

    -- Datos adicionales: el segundo correo en adelante, el segundo telefono en adelante, direcciones y etiquetas
    orden := 0;
    foreach extra_valor in array coalesce(correos[2:array_length(correos, 1)], '{}') loop
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, valor, orden) values (nuevo, 'correo', extra_valor, orden) on conflict do nothing;
    end loop;
    foreach extra_valor in array coalesce(telefonos[2:array_length(telefonos, 1)], '{}') loop
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, valor, orden) values (nuevo, 'telefono', extra_valor, orden) on conflict do nothing;
    end loop;
    for c in select value from jsonb_array_elements(case when jsonb_typeof(f -> 'contactos') = 'array' then f -> 'contactos' else '[]'::jsonb end) loop
      extra_tipo := c ->> 'tipo';
      continue when extra_tipo not in ('direccion', 'etiqueta');
      extra_valor := left(btrim(coalesce(c ->> 'valor', '')), 500);
      continue when extra_valor = '';
      extra_etiqueta := nullif(left(btrim(coalesce(c ->> 'etiqueta', '')), 60), '');
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, etiqueta, valor, orden)
      values (nuevo, extra_tipo, extra_etiqueta, extra_valor, orden) on conflict do nothing;
    end loop;
    -- Marca de la importacion, para poder encontrar (y deshacer) lo que entro de una vez
    insert into public.adn_miembro_contactos (miembro_id, tipo, etiqueta, valor, orden)
    values (nuevo, 'etiqueta', 'importacion', 'Importado ' || hoy::text || ' (' || p_origen || ')', 999) on conflict do nothing;

    vistos_correos := vistos_correos || correos;
    vistos_tel := vistos_tel || telefonos;
    if array_length(correos, 1) is null and array_length(telefonos, 1) is null then
      vistos_nombre := vistos_nombre || lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
    end if;
    n_ok := n_ok + 1;
  end loop;

  return jsonb_build_object('importados', n_ok, 'duplicados_correo', n_dup_correo, 'duplicados_telefono', n_dup_tel,
                            'duplicados_nombre', n_dup_nombre, 'invalidas', n_invalidas, 'notas_descartadas', n_notas);
end $$;

revoke all on function public.adn_importar_miembros(jsonb, text) from public, anon;
grant execute on function public.adn_importar_miembros(jsonb, text) to authenticated, service_role;
