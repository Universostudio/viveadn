-- Vive ADN, paquete de aplicación 02 de 07. Aplicar en orden y detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261025080000_endurecer_aislamiento_y_privilegios.sql (sha256 8701571635d1) =====
-- =====================================================================
-- Endurecimiento tras la revision independiente del 24-10-2026
-- Corrige los hallazgos S6 a S14 del documento de estado.
--   S6  propietario: nadie salvo el propietario puede crearlo, cambiarlo o
--       desactivarlo; la iglesia conserva siempre un propietario activo.
--   S7  referencias entre iglesias: claves foraneas compuestas por iglesia
--       y funciones de ayuda filtradas por iglesia.
--   S9  usuarios desactivados sin acceso.
--   S10 crm_id lo fija el servidor; la secuencia no es accesible.
--   S11 el consolidador solo edita contactos, resultado, notas y cierre.
--   S12 indices para las politicas y las claves foraneas.
--   S14 privilegios sobrantes y roles del sistema inmutables.
-- =====================================================================

-- ---------------------------------------------------------------------
-- S9. Un perfil desactivado deja de pertenecer a efectos de acceso
-- ---------------------------------------------------------------------
create or replace function private.get_iglesia_id()
 returns uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  select iglesia_id from public.perfiles where id = (select auth.uid()) and activo
$function$;

-- ---------------------------------------------------------------------
-- S7. Funciones de ayuda limitadas a la iglesia de quien consulta
-- ---------------------------------------------------------------------
create or replace function private.es_consolidador_de(p_miembro uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.consolidaciones c
    where c.miembro_id = p_miembro
      and c.consolidador_id = (select auth.uid())
      and c.iglesia_id = (select private.get_iglesia_id())
  )
$function$;

create or replace function private.es_lider_de_casa(p_casa uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.casas_oracion c
    where c.id = p_casa
      and c.lider_id = (select auth.uid())
      and c.iglesia_id = (select private.get_iglesia_id())
  )
$function$;

-- S7. Claves foraneas compuestas: toda referencia apunta a la misma iglesia
alter table public.miembros add constraint miembros_iglesia_id_id_key unique (iglesia_id, id);
alter table public.casas_oracion add constraint casas_oracion_iglesia_id_id_key unique (iglesia_id, id);
alter table public.perfiles add constraint perfiles_iglesia_id_id_key unique (iglesia_id, id);
alter table public.zonas add constraint zonas_iglesia_id_id_key unique (iglesia_id, id);

alter table public.asistencias drop constraint asistencias_casa_oracion_id_fkey,
  add constraint asistencias_casa_oracion_fk foreign key (iglesia_id, casa_oracion_id) references public.casas_oracion (iglesia_id, id);
alter table public.asistencias drop constraint asistencias_miembro_id_fkey,
  add constraint asistencias_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id);

alter table public.casas_oracion drop constraint casas_oracion_lider_id_fkey,
  add constraint casas_oracion_lider_fk foreign key (iglesia_id, lider_id) references public.perfiles (iglesia_id, id);
alter table public.casas_oracion drop constraint casas_oracion_zona_id_fkey,
  add constraint casas_oracion_zona_fk foreign key (iglesia_id, zona_id) references public.zonas (iglesia_id, id);

alter table public.consolidaciones drop constraint consolidaciones_miembro_id_fkey,
  add constraint consolidaciones_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id);
alter table public.consolidaciones drop constraint consolidaciones_casa_oracion_id_fkey,
  add constraint consolidaciones_casa_oracion_fk foreign key (iglesia_id, casa_oracion_id) references public.casas_oracion (iglesia_id, id);
alter table public.consolidaciones drop constraint consolidaciones_consolidador_id_fkey,
  add constraint consolidaciones_consolidador_fk foreign key (iglesia_id, consolidador_id) references public.perfiles (iglesia_id, id);

alter table public.logros drop constraint logros_miembro_id_fkey,
  add constraint logros_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id);

alter table public.miembros drop constraint miembros_casa_oracion_id_fkey,
  add constraint miembros_casa_oracion_fk foreign key (iglesia_id, casa_oracion_id) references public.casas_oracion (iglesia_id, id);

alter table public.progreso_formacion drop constraint progreso_formacion_miembro_id_fkey,
  add constraint progreso_formacion_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id);
alter table public.progreso_formacion drop constraint progreso_formacion_actualizado_por_fkey,
  add constraint progreso_formacion_actualizado_por_fk foreign key (iglesia_id, actualizado_por) references public.perfiles (iglesia_id, id);

-- ---------------------------------------------------------------------
-- S6. Proteccion del propietario
-- ---------------------------------------------------------------------
-- Los perfiles los crea solo el servidor (invitaciones con service_role)
drop policy if exists perfiles_crear on public.perfiles;

-- Solo consulta la iglesia de quien llama, nunca otra
create or replace function private.hay_otro_propietario_activo(p_excluir uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.perfiles
    where iglesia_id = (select private.get_iglesia_id()) and rol = 'propietario' and activo and id <> p_excluir
  )
$function$;
revoke execute on function private.hay_otro_propietario_activo(uuid) from public, anon;
grant execute on function private.hay_otro_propietario_activo(uuid) to authenticated, service_role;

create or replace function private.guardar_perfil()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  -- Sin sesion (service_role, migraciones): sin restricciones
  if (select auth.uid()) is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.rol = 'propietario' and not private.es_propietario() then
      raise exception 'Solo el propietario puede crear otro propietario';
    end if;
    return new;
  end if;

  if new.id is distinct from old.id then
    raise exception 'No se puede cambiar el identificador de un usuario';
  end if;
  if new.iglesia_id is distinct from old.iglesia_id then
    raise exception 'No se puede cambiar la iglesia de un usuario';
  end if;
  if new.email is distinct from old.email then
    raise exception 'El correo se cambia desde la cuenta de acceso, no desde el perfil';
  end if;
  if (new.rol is distinct from old.rol or new.activo is distinct from old.activo)
     and not private.tiene_permiso('usuarios.gestionar') then
    raise exception 'Sin permiso para cambiar el rol o el estado de un usuario';
  end if;
  if new.id = (select auth.uid()) and new.activo is distinct from old.activo then
    raise exception 'No puedes cambiar tu propio estado';
  end if;
  -- Nadie se asigna a si mismo otro rol, salvo el propietario que cede el puesto
  if new.id = (select auth.uid()) and new.rol is distinct from old.rol and not private.es_propietario() then
    raise exception 'No puedes cambiar tu propio rol';
  end if;
  if (new.rol = 'propietario' or old.rol = 'propietario')
     and (new.rol is distinct from old.rol or new.activo is distinct from old.activo)
     and not private.es_propietario() then
    raise exception 'Solo el propietario puede asignar, retirar o desactivar el rol de propietario';
  end if;
  if old.rol = 'propietario' and old.activo
     and (new.rol is distinct from 'propietario' or not coalesce(new.activo, false))
     then
    -- Bloqueo por iglesia: dos propietarios no pueden degradarse a la vez
    perform pg_advisory_xact_lock(hashtext('propietarios:' || old.iglesia_id::text));
    if not private.hay_otro_propietario_activo(old.id) then
      raise exception 'La iglesia debe conservar al menos un propietario activo';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists perfiles_guardar on public.perfiles;
create trigger perfiles_guardar before insert or update on public.perfiles
  for each row execute function private.guardar_perfil();

-- ---------------------------------------------------------------------
-- S10. crm_id lo asigna siempre el servidor
-- ---------------------------------------------------------------------
create or replace function private.fijar_crm_id()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' then
    -- Con sesion se ignora cualquier valor enviado; sin sesion (importaciones) se respeta si viene
    if (select auth.uid()) is not null or new.crm_id is null then
      new.crm_id := public.generar_crm_id();
    end if;
  elsif (select auth.uid()) is not null then
    new.crm_id := old.crm_id;
  end if;
  return new;
end;
$function$;
revoke execute on function private.fijar_crm_id() from public, anon, authenticated, service_role;

alter table public.miembros alter column crm_id drop default;
create trigger miembros_crm_id before insert or update on public.miembros
  for each row execute function private.fijar_crm_id();

revoke all on sequence public.crm_id_seq from anon, authenticated;
revoke execute on function public.generar_crm_id() from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- S11. El consolidador sin permiso de edicion solo registra contactos
-- ---------------------------------------------------------------------
create or replace function private.guardar_consolidacion()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare
  v_libres text[] := array['primer_contacto_fecha','primer_contacto_notas',
    'segundo_contacto_fecha','segundo_contacto_notas','tercer_contacto_fecha',
    'tercer_contacto_notas','resultado','notas','completado','completado_at','updated_at'];
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.iglesia_id is distinct from old.iglesia_id or new.miembro_id is distinct from old.miembro_id then
    raise exception 'No se puede cambiar el miembro ni la iglesia de una consolidacion';
  end if;
  if new.consolidador_id is distinct from old.consolidador_id
     and not private.tiene_permiso('consolidacion.reasignar') then
    raise exception 'Sin permiso para reasignar el consolidador';
  end if;
  if not private.tiene_permiso('consolidacion.editar') then
    if private.tiene_permiso('consolidacion.reasignar') then
      v_libres := v_libres || 'consolidador_id';
    end if;
    if (to_jsonb(new) - v_libres) is distinct from (to_jsonb(old) - v_libres) then
      raise exception 'Solo puedes registrar contactos, resultado, notas y el cierre';
    end if;
  end if;
  return new;
end;
$function$;

-- Asistencias: el lider solo registra a miembros de las casas que lidera
create or replace function private.miembro_de_casa(p_miembro uuid, p_casa uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.miembros m
    where m.id = p_miembro and m.casa_oracion_id = p_casa
      and m.iglesia_id = (select private.get_iglesia_id())
  )
$function$;
revoke execute on function private.miembro_de_casa(uuid, uuid) from public, anon;
grant execute on function private.miembro_de_casa(uuid, uuid) to authenticated, service_role;

drop policy if exists asistencias_crear on public.asistencias;
create policy asistencias_crear on public.asistencias for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('asistencia.registrar')) or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(casa_oracion_id) and private.miembro_de_casa(miembro_id, casa_oracion_id))));

drop policy if exists asistencias_editar on public.asistencias;
create policy asistencias_editar on public.asistencias for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('asistencia.registrar')) or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(casa_oracion_id))))
  with check ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('asistencia.registrar')) or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(casa_oracion_id) and private.miembro_de_casa(miembro_id, casa_oracion_id))));

-- Formacion: el registro queda a nombre de quien lo hace
create or replace function private.fijar_actualizado_por()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is not null then
    new.actualizado_por := (select auth.uid());
  end if;
  return new;
end;
$function$;
revoke execute on function private.fijar_actualizado_por() from public, anon, authenticated, service_role;
create trigger progreso_formacion_autor before insert or update on public.progreso_formacion
  for each row execute function private.fijar_actualizado_por();

-- ---------------------------------------------------------------------
-- S14. Roles del sistema: clave, tipo e iglesia inmutables
-- ---------------------------------------------------------------------
create or replace function private.guardar_rol()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.iglesia_id is distinct from old.iglesia_id then
    raise exception 'No se puede cambiar la iglesia de un rol';
  end if;
  if new.es_sistema is distinct from old.es_sistema or new.es_propietario is distinct from old.es_propietario then
    raise exception 'No se puede cambiar el tipo de un rol';
  end if;
  if old.es_sistema and new.clave is distinct from old.clave then
    raise exception 'No se puede cambiar la clave de un rol del sistema';
  end if;
  return new;
end;
$function$;
create trigger roles_guardar before update on public.roles
  for each row execute function private.guardar_rol();

revoke execute on function private.guardar_perfil() from public, anon, authenticated, service_role;
revoke execute on function private.guardar_consolidacion() from public, anon, authenticated, service_role;
revoke execute on function private.guardar_rol() from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- Fallos de la web detectados en la segunda revision
-- ---------------------------------------------------------------------
-- Casas: el codigo ZONA-CODIGO (p. ej. ZN-849402) lo genera el servidor.
-- El cliente envia solo el prefijo de zona (2 o 3 letras); el codigo no cambia despues.
create or replace function private.asignar_codigo_casa()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_prefijo text;
  v_codigo text;
  v_intentos int := 0;
begin
  if tg_op = 'UPDATE' then
    if (select auth.uid()) is not null then
      new.codigo_zona := old.codigo_zona;
    end if;
    return new;
  end if;
  -- Importaciones sin sesion pueden traer el codigo completo
  if (select auth.uid()) is null and new.codigo_zona ~ '^[A-Z]{2,3}-[0-9]{6}$' then
    return new;
  end if;
  v_prefijo := upper(split_part(coalesce(new.codigo_zona, ''), '-', 1));
  if v_prefijo !~ '^[A-Z]{2,3}$' then
    raise exception 'Indica la zona con 2 o 3 letras (por ejemplo ZN, ZS, ZE, ZO o ZC)';
  end if;
  loop
    v_codigo := v_prefijo || '-' || lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (select 1 from public.casas_oracion where codigo_zona = v_codigo);
    v_intentos := v_intentos + 1;
    if v_intentos > 20 then
      raise exception 'No se pudo generar un codigo unico para la casa';
    end if;
  end loop;
  new.codigo_zona := v_codigo;
  return new;
end;
$function$;
revoke execute on function private.asignar_codigo_casa() from public, anon, authenticated, service_role;
create trigger casas_oracion_codigo before insert or update on public.casas_oracion
  for each row execute function private.asignar_codigo_casa();
alter table public.casas_oracion add constraint casas_oracion_codigo_zona_key unique (codigo_zona);

-- Formacion: un registro por miembro y nivel; niveles 1 a 5; porcentaje 0 a 100
alter table public.progreso_formacion add constraint progreso_formacion_miembro_nivel_key unique (miembro_id, nivel);
alter table public.progreso_formacion add constraint progreso_formacion_nivel_check check (nivel between 1 and 5);
alter table public.progreso_formacion add constraint progreso_formacion_porcentaje_check check (porcentaje between 0 and 100);

-- Roles: la iglesia se rellena sola al crear un rol
alter table public.roles alter column iglesia_id set default private.get_iglesia_id();

-- ---------------------------------------------------------------------
-- S12. Indices para politicas y claves foraneas
-- ---------------------------------------------------------------------
create index if not exists asistencias_casa_idx on public.asistencias (iglesia_id, casa_oracion_id);
create index if not exists asistencias_miembro_idx on public.asistencias (iglesia_id, miembro_id);
create index if not exists casas_oracion_lider_idx on public.casas_oracion (iglesia_id, lider_id);
create index if not exists casas_oracion_zona_idx on public.casas_oracion (iglesia_id, zona_id);
create index if not exists consolidaciones_miembro_idx on public.consolidaciones (iglesia_id, miembro_id);
create index if not exists consolidaciones_consolidador_idx on public.consolidaciones (iglesia_id, consolidador_id);
create index if not exists consolidaciones_casa_idx on public.consolidaciones (iglesia_id, casa_oracion_id);
create index if not exists logros_miembro_idx on public.logros (iglesia_id, miembro_id);
create index if not exists miembros_casa_idx on public.miembros (iglesia_id, casa_oracion_id);
create index if not exists progreso_formacion_miembro_idx on public.progreso_formacion (iglesia_id, miembro_id);
create index if not exists progreso_formacion_actualizado_idx on public.progreso_formacion (iglesia_id, actualizado_por);
create index if not exists perfiles_rol_idx on public.perfiles (iglesia_id, rol);
create index if not exists iglesias_plan_idx on public.iglesias (plan);
create index if not exists permisos_modulo_idx on public.permisos (modulo);
create index if not exists plan_modulos_modulo_idx on public.plan_modulos (modulo);
create index if not exists rol_permisos_permiso_idx on public.rol_permisos (permiso);
create index if not exists iglesia_modulos_modulo_idx on public.iglesia_modulos (modulo);
create index if not exists plataforma_auditoria_actor_idx on public.plataforma_auditoria (actor);

-- ---------------------------------------------------------------------
-- S14. Privilegios sobrantes
-- ---------------------------------------------------------------------
-- anon no necesita ninguna tabla ni secuencia: todo exige sesion
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
-- authenticated: sin TRUNCATE (se salta RLS), REFERENCES ni TRIGGER
revoke truncate, references, trigger on all tables in schema public from authenticated;
revoke all on sequence public.plataforma_auditoria_id_seq from authenticated;
do $$
begin
  if current_setting('server_version_num')::int >= 170000 then
    execute 'revoke maintain on all tables in schema public from anon, authenticated';
    execute 'alter default privileges for role postgres in schema public revoke maintain on tables from authenticated';
  end if;
end $$;

-- Lo mismo para tablas y funciones futuras
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke truncate, references, trigger on tables from authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
-- Consecuencia: toda funcion nueva necesita un GRANT EXECUTE explicito
-- para los roles que deban usarla (ver supabase/README.md).
alter default privileges for role postgres revoke execute on functions from public;

-- ===== migrations/20261027090000_permisos_explicitos.sql (sha256 fc0c035a0f20) =====
-- Permisos explícitos para todo objeto nuevo en el esquema public.
--
-- Supabase deja de conceder permisos automáticos a las tablas nuevas de public
-- el 30-10-2026 en todos los proyectos existentes:
-- https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically
-- Esta migración adelanta ese comportamiento y lo extiende a secuencias y funciones,
-- para que ningún objeto quede expuesto a la API por omisión.
--
-- Efecto: solo afecta a objetos creados a partir de ahora. Las tablas, secuencias y
-- funciones existentes conservan sus permisos actuales.
--
-- Regla desde esta migración: toda migración que cree una tabla incluye, en el mismo
-- archivo, (1) sus GRANT explícitos, (2) ENABLE ROW LEVEL SECURITY y (3) sus políticas.
-- Toda función nueva incluye su GRANT EXECUTE solo a los roles que la usen.
-- supabase/tests/permisos.sql falla si falta cualquiera de las tres piezas.

alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;

alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, service_role;

-- ===== migrations/20261030000000_roles_superadmin_zona_colaborador.sql (sha256 6fbbdd1be14a) =====
-- Roles nuevos: Superadministrador (antes Propietario, siempre dos), Co-administrador,
-- Líder de Zona y Colaborador. La clave interna 'propietario' no cambia: solo su nombre visible,
-- para no romper políticas, funciones ni datos existentes.

-- 1. Nombre visible
update public.roles set nombre = 'Superadministrador',
  descripcion = 'Acceso total. Siempre debe haber al menos dos. Unico que puede asignar o retirar este rol.'
where clave = 'propietario';

-- 2. Líder de zona y autoría de registros (para el Colaborador)
alter table public.zonas add column if not exists lider_id uuid references public.perfiles(id) on delete set null;
alter table public.miembros add column if not exists creado_por uuid default auth.uid();
alter table public.consolidaciones add column if not exists creado_por uuid default auth.uid();
alter table public.asistencias add column if not exists creado_por uuid default auth.uid();

create or replace function private.es_lider_de_zona(p_zona uuid)
 returns boolean language sql stable security definer set search_path to ''
as $$
  select p_zona is not null and exists (
    select 1 from public.zonas z
    where z.id = p_zona and z.lider_id = (select auth.uid())
      and z.iglesia_id = (select private.get_iglesia_id())
  )
$$;

create or replace function private.es_lider_de_zona_de_casa(p_casa uuid)
 returns boolean language sql stable security definer set search_path to ''
as $$
  select p_casa is not null and exists (
    select 1 from public.casas_oracion c join public.zonas z on z.id = c.zona_id
    where c.id = p_casa and z.lider_id = (select auth.uid())
      and c.iglesia_id = (select private.get_iglesia_id())
  )
$$;
revoke execute on function private.es_lider_de_zona(uuid), private.es_lider_de_zona_de_casa(uuid) from public, anon;
grant execute on function private.es_lider_de_zona(uuid), private.es_lider_de_zona_de_casa(uuid) to authenticated, service_role;

-- 3. Permisos nuevos
insert into public.permisos (clave, modulo, descripcion, sensible) values
('casas.ver_zona', 'casas', 'Ver las casas de oracion de la zona que lidera', false),
('miembros.ver_zona', 'miembros', 'Ver los miembros de las casas de la zona que lidera', false),
('consolidacion.ver_zona', 'consolidacion', 'Ver la consolidacion de las casas de la zona que lidera', false),
('asistencia.ver_zona', 'asistencia', 'Ver la asistencia de las casas de la zona que lidera', false),
('miembros.ver_propios', 'miembros', 'Ver solo los miembros que el mismo registro', false),
('consolidacion.ver_propios', 'consolidacion', 'Ver solo los procesos que el mismo abrio', false),
('asistencia.ver_propia', 'asistencia', 'Ver solo la asistencia que el mismo registro', false)
on conflict (clave) do nothing;

-- 4. Políticas de lectura: se añade el alcance de zona y el de autoría
drop policy casas_ver on public.casas_oracion;
create policy casas_ver on public.casas_oracion for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (
    (select private.tiene_permiso('casas.ver'))
    or ((select private.tiene_permiso('casas.ver_propia')) and lider_id = (select auth.uid()))
    or ((select private.tiene_permiso('casas.ver_zona')) and private.es_lider_de_zona(zona_id))));

drop policy miembros_ver on public.miembros;
create policy miembros_ver on public.miembros for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (
    (select private.tiene_permiso('miembros.ver'))
    or ((select private.tiene_permiso('miembros.ver_asignados')) and (private.es_consolidador_de(id) or private.es_lider_de_casa(casa_oracion_id)))
    or ((select private.tiene_permiso('miembros.ver_zona')) and private.es_lider_de_zona_de_casa(casa_oracion_id))
    or ((select private.tiene_permiso('miembros.ver_propios')) and creado_por = (select auth.uid()))));

drop policy consolidaciones_ver on public.consolidaciones;
create policy consolidaciones_ver on public.consolidaciones for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (
    (select private.tiene_permiso('consolidacion.ver'))
    or ((select private.tiene_permiso('consolidacion.ver_asignados')) and consolidador_id = (select auth.uid()))
    or ((select private.tiene_permiso('consolidacion.ver_casa')) and private.es_lider_de_casa(casa_oracion_id))
    or ((select private.tiene_permiso('consolidacion.ver_zona')) and private.es_lider_de_zona_de_casa(casa_oracion_id))
    or ((select private.tiene_permiso('consolidacion.ver_propios')) and creado_por = (select auth.uid()))));

drop policy asistencias_ver on public.asistencias;
create policy asistencias_ver on public.asistencias for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (
    (select private.tiene_permiso('asistencia.ver'))
    or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(casa_oracion_id))
    or ((select private.tiene_permiso('asistencia.ver_zona')) and private.es_lider_de_zona_de_casa(casa_oracion_id))
    or ((select private.tiene_permiso('asistencia.ver_propia')) and creado_por = (select auth.uid()))));

-- 5. Roles nuevos y su siembra (también para las iglesias que ya existen)
create or replace function private.sembrar_roles_nuevos(p_iglesia uuid)
 returns void language plpgsql security definer set search_path to ''
as $$
declare v_id uuid;
begin
  insert into public.roles (iglesia_id, clave, nombre, descripcion, es_sistema, es_propietario) values
    (p_iglesia,'coadministrador','Co-administrador','Opera miembros, casas, consolidacion, formacion y reportes. No gestiona usuarios, roles ni configuracion.',true,false),
    (p_iglesia,'lider_zona','Lider de Zona','Ve las casas de su zona, sus miembros, consolidacion y asistencia.',true,false),
    (p_iglesia,'colaborador','Colaborador','Registra asistencia y nuevos convertidos y ve solo lo que registra.',true,false)
  on conflict (iglesia_id, clave) do nothing;

  select id into v_id from public.roles where iglesia_id = p_iglesia and clave = 'coadministrador';
  insert into public.rol_permisos (rol_id, permiso)
    select v_id, clave from public.permisos
    where clave not in ('iglesia.configurar','roles.gestionar','usuarios.gestionar')
      and clave not like '%.ver_zona' and clave not like '%.ver_propi%' and clave not like '%.ver_asignados'
      and clave not in ('casas.ver_propia','asistencia.registrar_propia','consolidacion.ver_casa','consolidacion.registrar_contacto')
  on conflict do nothing;

  select id into v_id from public.roles where iglesia_id = p_iglesia and clave = 'lider_zona';
  insert into public.rol_permisos (rol_id, permiso)
    select v_id, unnest(array['casas.ver_zona','miembros.ver_zona','consolidacion.ver_zona','asistencia.ver_zona',
                              'zonas.ver','usuarios.ver','reportes.ver','gamificacion.ver'])
  on conflict do nothing;

  select id into v_id from public.roles where iglesia_id = p_iglesia and clave = 'colaborador';
  insert into public.rol_permisos (rol_id, permiso)
    select v_id, unnest(array['asistencia.registrar','asistencia.ver_propia','miembros.crear','miembros.ver_propios',
                              'consolidacion.crear','consolidacion.ver_propios','casas.ver','zonas.ver'])
  on conflict do nothing;
end;
$$;
revoke execute on function private.sembrar_roles_nuevos(uuid) from public, anon, authenticated;
grant execute on function private.sembrar_roles_nuevos(uuid) to service_role;

create or replace function private.trg_sembrar_roles()
 returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  return new;
end;
$$;

select private.sembrar_roles_nuevos(id) from public.iglesias;

-- 6. Siempre dos superadministradores: no se puede bajar de dos, ni dejar a la iglesia sin ninguno.
create or replace function private.trg_minimo_superadmins()
 returns trigger language plpgsql security definer set search_path to ''
as $$
declare v_antes int; v_baja boolean;
begin
  if tg_op = 'DELETE' then
    v_baja := old.rol = 'propietario' and coalesce(old.activo, true);
  else
    v_baja := old.rol = 'propietario' and coalesce(old.activo, true)
              and (new.rol is distinct from 'propietario' or not coalesce(new.activo, true));
  end if;
  if not v_baja then return coalesce(new, old); end if;
  -- si la iglesia se borra entera no hay nada que proteger
  if not exists (select 1 from public.iglesias where id = old.iglesia_id) then return coalesce(new, old); end if;
  select count(*) into v_antes from public.perfiles
    where iglesia_id = old.iglesia_id and rol = 'propietario' and coalesce(activo, true);
  if v_antes <= 2 then
    raise exception 'Debe haber al menos dos superadministradores activos';
  end if;
  return coalesce(new, old);
end;
$$;
drop trigger if exists minimo_superadmins on public.perfiles;
create trigger minimo_superadmins before update or delete on public.perfiles
  for each row execute function private.trg_minimo_superadmins();

-- ===== migrations/20261030010000_invitaciones.sql (sha256 d22441c30a03) =====
-- Invitaciones propias de un solo uso que caducan a los 15 dias.
-- Supabase solo permite enlaces de correo de hasta 24 horas, asi que las invitaciones de acceso
-- se gestionan aqui. En la tabla solo se guarda la huella SHA-256 del enlace, nunca el enlace.
-- Toda escritura la hace la funcion de servidor `invitaciones` con service_role.

create table public.invitaciones (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  email text not null check (email = lower(email) and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  nombre text not null check (length(nombre) between 1 and 60),
  apellido text not null check (length(apellido) between 1 and 60),
  rol text not null,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  creada_por uuid references public.perfiles(id) on delete set null,
  creada_en timestamptz not null default now(),
  caduca_en timestamptz not null default now() + interval '15 days',
  usada_en timestamptz,
  revocada_en timestamptz,
  foreign key (iglesia_id, rol) references public.roles(iglesia_id, clave)
);

-- Una sola invitacion pendiente por correo y por iglesia
create unique index invitaciones_pendiente_unica on public.invitaciones (iglesia_id, email)
  where usada_en is null and revocada_en is null;

alter table public.invitaciones enable row level security;

create policy invitaciones_ver on public.invitaciones for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('usuarios.gestionar')));

grant select on public.invitaciones to authenticated;
grant all on public.invitaciones to service_role;

-- Reclamar es atomico: solo una peticion puede gastar la invitacion, y solo si sigue vigente.
create or replace function public.reclamar_invitacion(p_hash text)
 returns table (id uuid, iglesia_id uuid, email text, nombre text, apellido text, rol text)
 language sql security invoker set search_path to ''
as $$
  update public.invitaciones i set usada_en = now()
  where i.token_hash = p_hash and i.usada_en is null and i.revocada_en is null and i.caduca_en > now()
  returning i.id, i.iglesia_id, i.email, i.nombre, i.apellido, i.rol
$$;

-- Si algo falla despues de reclamar, se devuelve a pendiente para que la persona pueda reintentar.
create or replace function public.liberar_invitacion(p_id uuid)
 returns void language sql security invoker set search_path to ''
as $$
  update public.invitaciones set usada_en = null where id = p_id and revocada_en is null
$$;

revoke execute on function public.reclamar_invitacion(text), public.liberar_invitacion(uuid) from public, anon, authenticated;
grant execute on function public.reclamar_invitacion(text), public.liberar_invitacion(uuid) to service_role;

-- ===== migrations/20261104133745_enlaces_dar.sql (sha256 4b440df221dc) =====
-- Enlaces para dar: cada iglesia guarda la direccion web de sus propios sitios de recaudo
-- (diezmo, ofrenda, donacion). La app solo muestra un boton que lleva a ese sitio externo;
-- no procesa ni guarda pagos ni datos bancarios.

create table public.enlaces_dar (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  tipo text not null check (tipo in ('diezmo', 'ofrenda', 'donacion')),
  url text not null check (length(url) <= 500 and url ~ '^https://[^[:space:]]+$'),
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (iglesia_id, tipo)
);

alter table public.enlaces_dar enable row level security;

-- Cualquier persona de la iglesia ve los enlaces para poder usar el boton
create policy enlaces_dar_ver on public.enlaces_dar for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()));

-- Solo quien configura la iglesia los crea, cambia o borra
create policy enlaces_dar_crear on public.enlaces_dar for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
create policy enlaces_dar_editar on public.enlaces_dar for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy enlaces_dar_borrar on public.enlaces_dar for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));

grant select, insert, update, delete on public.enlaces_dar to authenticated;
grant all on public.enlaces_dar to service_role;

-- ===== migrations/20261105021940_eventos_asistencia.sql (sha256 ebb35d4534f5) =====
-- Eventos y asistencia por evento.
-- Modulo nuevo "eventos" (calendario) y permisos eventos.ver / eventos.gestionar. La asistencia de
-- cada evento reutiliza los permisos del modulo asistencia (ver, registrar, registrar_propia).
-- Una serie semanal son varias filas de eventos con el mismo serie_id.

-- 1. Modulo, planes y permisos
insert into public.modulos (clave, nombre, descripcion, tipo, orden) values
  ('eventos', 'Eventos y calendario', 'Calendario de eventos, series semanales y asistencia por evento', 'incluido', 45)
on conflict (clave) do nothing;

insert into public.plan_modulos (plan, modulo) values
  ('semilla', 'eventos'), ('basico', 'eventos'), ('premium', 'eventos')
on conflict do nothing;

insert into public.permisos (clave, modulo, descripcion, sensible) values
  ('eventos.ver', 'eventos', 'Ver el calendario de eventos', false),
  ('eventos.gestionar', 'eventos', 'Crear, editar y cancelar eventos', false)
on conflict (clave) do nothing;

-- 2. Tablas
create table public.eventos (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  titulo text not null check (length(btrim(titulo)) between 1 and 150),
  descripcion text check (length(descripcion) <= 2000),
  tipo text not null default 'culto' check (tipo in ('culto', 'casa_oracion', 'formacion', 'especial', 'otro')),
  inicia_en timestamptz not null,
  termina_en timestamptz,
  lugar text check (length(lugar) <= 200),
  casa_oracion_id uuid,
  serie_id uuid,
  cancelado boolean not null default false,
  creado_por uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (termina_en is null or termina_en > inicia_en),
  unique (iglesia_id, id),
  constraint eventos_casa_fk foreign key (iglesia_id, casa_oracion_id) references public.casas_oracion (iglesia_id, id)
);
create index eventos_iglesia_inicio_idx on public.eventos (iglesia_id, inicia_en);
create index eventos_serie_idx on public.eventos (serie_id) where serie_id is not null;

create table public.asistencia_evento (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  evento_id uuid not null,
  miembro_id uuid not null,
  presente boolean not null default true,
  registrado_por uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (evento_id, miembro_id),
  constraint asistencia_evento_evento_fk foreign key (iglesia_id, evento_id) references public.eventos (iglesia_id, id) on delete cascade,
  constraint asistencia_evento_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade
);
create index asistencia_evento_miembro_idx on public.asistencia_evento (miembro_id);

-- 3. Ayuda para las politicas: la casa a la que pertenece un evento, limitada a la iglesia de quien consulta
create or replace function private.casa_del_evento(p_evento uuid)
 returns uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  select e.casa_oracion_id from public.eventos e
  where e.id = p_evento and e.iglesia_id = (select private.get_iglesia_id())
$function$;
revoke execute on function private.casa_del_evento(uuid) from public, anon;
grant execute on function private.casa_del_evento(uuid) to authenticated, service_role;

-- 4. Seguridad por filas
alter table public.eventos enable row level security;
alter table public.asistencia_evento enable row level security;

create policy eventos_ver on public.eventos for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.ver')));
create policy eventos_crear on public.eventos for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));
create policy eventos_editar on public.eventos for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy eventos_borrar on public.eventos for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));

-- Quien registra una casa solo ve y registra a los miembros de su casa en los eventos de esa casa
create policy asistencia_evento_ver on public.asistencia_evento for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.ver'))
      or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(private.casa_del_evento(evento_id)))));
create policy asistencia_evento_crear on public.asistencia_evento for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.registrar'))
      or ((select private.tiene_permiso('asistencia.registrar_propia'))
          and private.es_lider_de_casa(private.casa_del_evento(evento_id))
          and private.miembro_de_casa(miembro_id, private.casa_del_evento(evento_id)))));
create policy asistencia_evento_editar on public.asistencia_evento for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.registrar'))
      or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(private.casa_del_evento(evento_id)))))
  with check (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.registrar'))
      or ((select private.tiene_permiso('asistencia.registrar_propia'))
          and private.es_lider_de_casa(private.casa_del_evento(evento_id))
          and private.miembro_de_casa(miembro_id, private.casa_del_evento(evento_id)))));
create policy asistencia_evento_borrar on public.asistencia_evento for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('asistencia.registrar')));

grant select, insert, update, delete on public.eventos, public.asistencia_evento to authenticated;
grant all on public.eventos, public.asistencia_evento to service_role;

-- 5. Permisos de eventos para los roles de sistema, tambien en las iglesias que ya existen
create or replace function private.sembrar_eventos(p_iglesia uuid)
 returns void language plpgsql security definer set search_path to ''
as $$
begin
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, p.permiso
    from public.roles r
    cross join (values ('eventos.ver'), ('eventos.gestionar')) as p(permiso)
    where r.iglesia_id = p_iglesia and r.clave in ('administrador', 'coadministrador')
  on conflict do nothing;
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, 'eventos.ver'
    from public.roles r
    where r.iglesia_id = p_iglesia
      and r.clave in ('lider_casa', 'lider_escuela', 'consolidador', 'miembro', 'lider_zona', 'colaborador')
  on conflict do nothing;
end;
$$;
revoke execute on function private.sembrar_eventos(uuid) from public, anon, authenticated;
grant execute on function private.sembrar_eventos(uuid) to service_role;

create or replace function private.trg_sembrar_roles()
 returns trigger language plpgsql security definer set search_path to ''
as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  return new;
end;
$$;

select private.sembrar_eventos(id) from public.iglesias;

-- ===== migrations/20261105022526_asistencia_evento_ver_propia.sql (sha256 6b9e4ac614e7) =====
-- Correccion de asistencia_evento_ver: el rol colaborador registra asistencia con asistencia.registrar
-- y solo ve lo que el mismo registra (asistencia.ver_propia), igual que en la asistencia de casas.
-- Sin esta rama, al insertar y pedir la fila de vuelta la politica de lectura la rechazaba y el
-- colaborador no podia marcar asistencia.
drop policy asistencia_evento_ver on public.asistencia_evento;
create policy asistencia_evento_ver on public.asistencia_evento for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
    and ((select private.tiene_permiso('asistencia.ver'))
      or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(private.casa_del_evento(evento_id)))
      or ((select private.tiene_permiso('asistencia.ver_propia')) and registrado_por = (select auth.uid()))));

-- ===== migrations/20261105025055_checkin_qr.sql (sha256 87e423fddc7f) =====
-- Registro de asistencia por QR. Cada evento puede tener un enlace secreto (evento_checkin) que abre
-- una pagina publica donde una persona se registra desde su movil. Los registros nuevos entran como
-- miembros con su seguimiento de 72 horas abierto; los que ya existen solo marcan asistencia.
-- Medidas: enlace de 256 bits que se pausa o regenera, ventana de tiempo, tope de registros por
-- evento, limite por dispositivo (solo huella de la IP), y respuesta identica para nuevos y existentes.
-- Las funciones solo las ejecuta el servidor (service_role), a traves de la funcion de borde checkin-evento.

create table public.evento_checkin (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  evento_id uuid not null,
  token text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
    check (token ~ '^[0-9a-f]{64}$'),
  activo boolean not null default true,
  abre_en timestamptz,
  cierra_en timestamptz,
  max_registros integer not null default 300 check (max_registros between 1 and 2000),
  created_at timestamptz not null default now(),
  unique (evento_id),
  check (abre_en is null or cierra_en is null or cierra_en > abre_en),
  constraint evento_checkin_evento_fk foreign key (iglesia_id, evento_id) references public.eventos (iglesia_id, id) on delete cascade
);

create table public.checkin_registros (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  evento_id uuid not null,
  miembro_id uuid,
  ip_hash text not null,
  creado boolean not null,
  created_at timestamptz not null default now(),
  constraint checkin_registros_evento_fk foreign key (iglesia_id, evento_id) references public.eventos (iglesia_id, id) on delete cascade,
  constraint checkin_registros_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete set null (miembro_id)
);
create index checkin_registros_evento_idx on public.checkin_registros (evento_id, created_at);
create index checkin_registros_ip_idx on public.checkin_registros (evento_id, ip_hash, created_at);

alter table public.evento_checkin enable row level security;
alter table public.checkin_registros enable row level security;

-- El enlace solo lo ven y lo cambian quienes gestionan eventos
create policy evento_checkin_ver on public.evento_checkin for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));
create policy evento_checkin_crear on public.evento_checkin for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));
create policy evento_checkin_editar on public.evento_checkin for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy evento_checkin_borrar on public.evento_checkin for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));

-- Los registros solo se leen (para las cifras); los escribe unicamente el servidor
create policy checkin_registros_ver on public.checkin_registros for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));

grant select, insert, update, delete on public.evento_checkin to authenticated;
grant select on public.checkin_registros to authenticated;
grant all on public.evento_checkin, public.checkin_registros to service_role;

-- Datos publicos de un enlace: null si no existe o esta pausado
create or replace function public.info_checkin(p_token text)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $$
declare c record; v_abre timestamptz; v_cierra timestamptz; v_n integer; v_estado text;
begin
  select ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.lugar, e.cancelado, i.nombre as iglesia, i.email_contacto
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token;
  if not found or not c.activo or c.cancelado then return null; end if;
  v_abre := coalesce(c.abre_en, c.inicia_en - interval '2 hours');
  v_cierra := coalesce(c.cierra_en, coalesce(c.termina_en, c.inicia_en + interval '6 hours') + interval '1 hour');
  select count(*) into v_n from public.checkin_registros where evento_id = c.evento_id;
  v_estado := case when now() < v_abre or now() > v_cierra then 'cerrado' when v_n >= c.max_registros then 'lleno' else 'abierto' end;
  -- Fuera de plazo solo se dice el estado y la iglesia: no se adelanta nada del evento
  if v_estado <> 'abierto' then return jsonb_build_object('estado', v_estado, 'iglesia', c.iglesia); end if;
  return jsonb_build_object('estado', v_estado, 'iglesia', c.iglesia, 'contacto', c.email_contacto,
    'evento', c.titulo, 'inicia_en', c.inicia_en, 'lugar', c.lugar);
end;
$$;

-- Registra una persona. Devuelve: ok_nuevo, ok_existente, cerrado, lleno, limite o no_valido.
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
begin
  select ec.iglesia_id, ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.casa_oracion_id, e.cancelado
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token;
  if not found or not c.activo or c.cancelado then return 'no_valido'; end if;

  v_abre := coalesce(c.abre_en, c.inicia_en - interval '2 hours');
  v_cierra := coalesce(c.cierra_en, coalesce(c.termina_en, c.inicia_en + interval '6 hours') + interval '1 hour');
  if now() < v_abre or now() > v_cierra then return 'cerrado'; end if;

  select count(*) into v_n from public.checkin_registros where evento_id = c.evento_id;
  if v_n >= c.max_registros then return 'lleno'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and ip_hash = p_ip_hash and created_at > now() - interval '10 minutes';
  if v_n >= 5 then return 'limite'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and created_at > now() - interval '1 minute';
  if v_n >= 40 then return 'limite'; end if;

  -- Ya existe si coincide el correo, o el telefono y el nombre completo juntos (un telefono de familia no fusiona personas)
  v_dig := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  select m.id into v_miembro from public.miembros m
   where m.iglesia_id = c.iglesia_id and m.activo
     and ((coalesce(p_email, '') <> '' and lower(m.email) = lower(p_email))
       or (length(v_dig) >= 7
           and right(regexp_replace(coalesce(m.telefono, ''), '\D', '', 'g'), 9) = right(v_dig, 9)
           and lower(btrim(m.nombre)) = lower(btrim(p_nombre))
           and lower(btrim(m.apellido)) = lower(btrim(p_apellido))))
   order by m.created_at
   limit 1;

  if v_miembro is null then
    insert into public.miembros (iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, activo, notas)
      values (c.iglesia_id, btrim(p_nombre), btrim(p_apellido), nullif(btrim(coalesce(p_email, '')), ''), btrim(p_telefono),
              c.casa_oracion_id, true, 'Registrado por QR en el evento: ' || c.titulo)
      returning id into v_miembro;
    v_nuevo := true;
    insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, notas)
      values (c.iglesia_id, v_miembro, now(), 'Registro por QR en el evento: ' || c.titulo);
  end if;

  insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente)
    values (c.iglesia_id, c.evento_id, v_miembro, true)
    on conflict (evento_id, miembro_id) do update set presente = true;
  insert into public.checkin_registros (iglesia_id, evento_id, miembro_id, ip_hash, creado)
    values (c.iglesia_id, c.evento_id, v_miembro, p_ip_hash, v_nuevo);

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.info_checkin(text), public.registrar_checkin(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.info_checkin(text), public.registrar_checkin(text, text, text, text, text, text) to service_role;

-- ===== migrations/20261105025422_checkin_serializar.sql (sha256 e9d949bb7ec8) =====
-- Correccion de registrar_checkin: serializa las peticiones de un mismo evento.
-- Reproducido con 30 peticiones simultaneas y un tope de 6: entraban 7. El bloqueo de la fila de
-- evento_checkin hace que las peticiones se atiendan una tras otra, de modo que los recuentos (tope,
-- limite por dispositivo) y la busqueda de duplicados siempre ven lo que dejo la anterior.

-- Registra una persona. Devuelve: ok_nuevo, ok_existente, cerrado, lleno, limite o no_valido.
-- El bloqueo de la fila del enlace (for update) serializa las peticiones del mismo evento: sin el, varias
-- peticiones simultaneas leian el mismo recuento antes de insertar y superaban el tope, el limite por
-- dispositivo y la deteccion de duplicados. Cada peticion espera a la anterior y ve su resultado.
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
begin
  select ec.iglesia_id, ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.casa_oracion_id, e.cancelado
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token
   for update of ec;
  if not found or not c.activo or c.cancelado then return 'no_valido'; end if;

  v_abre := coalesce(c.abre_en, c.inicia_en - interval '2 hours');
  v_cierra := coalesce(c.cierra_en, coalesce(c.termina_en, c.inicia_en + interval '6 hours') + interval '1 hour');
  if now() < v_abre or now() > v_cierra then return 'cerrado'; end if;

  select count(*) into v_n from public.checkin_registros where evento_id = c.evento_id;
  if v_n >= c.max_registros then return 'lleno'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and ip_hash = p_ip_hash and created_at > now() - interval '10 minutes';
  if v_n >= 5 then return 'limite'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and created_at > now() - interval '1 minute';
  if v_n >= 40 then return 'limite'; end if;

  -- Ya existe si coincide el correo, o el telefono y el nombre completo juntos (un telefono de familia no fusiona personas)
  v_dig := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  select m.id into v_miembro from public.miembros m
   where m.iglesia_id = c.iglesia_id and m.activo
     and ((coalesce(p_email, '') <> '' and lower(m.email) = lower(p_email))
       or (length(v_dig) >= 7
           and right(regexp_replace(coalesce(m.telefono, ''), '\D', '', 'g'), 9) = right(v_dig, 9)
           and lower(btrim(m.nombre)) = lower(btrim(p_nombre))
           and lower(btrim(m.apellido)) = lower(btrim(p_apellido))))
   order by m.created_at
   limit 1;

  if v_miembro is null then
    insert into public.miembros (iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, activo, notas)
      values (c.iglesia_id, btrim(p_nombre), btrim(p_apellido), nullif(btrim(coalesce(p_email, '')), ''), btrim(p_telefono),
              c.casa_oracion_id, true, 'Registrado por QR en el evento: ' || c.titulo)
      returning id into v_miembro;
    v_nuevo := true;
    insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, notas)
      values (c.iglesia_id, v_miembro, now(), 'Registro por QR en el evento: ' || c.titulo);
  end if;

  insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente)
    values (c.iglesia_id, c.evento_id, v_miembro, true)
    on conflict (evento_id, miembro_id) do update set presente = true;
  insert into public.checkin_registros (iglesia_id, evento_id, miembro_id, ip_hash, creado)
    values (c.iglesia_id, c.evento_id, v_miembro, p_ip_hash, v_nuevo);

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text) to service_role;
