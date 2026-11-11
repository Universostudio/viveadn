-- =====================================================================
-- Vive ADN: esquema completo de la base de datos (proyecto viveadn-saas)
-- Extraido del catalogo de Postgres de produccion el 24 de octubre de 2026.
--
-- Recoge todo lo aplicado hasta esa fecha, incluido lo que se hizo a mano
-- en el editor SQL y las cuatro migraciones registradas en Supabase:
--   20261024013525 roles_y_permisos_por_iglesia
--   20261024015036 catalogo_modulos_y_planes
--   20261024015537 panel_plataforma_base
--   20261024015554 plataforma_auditoria
--
-- Sirve para reconstruir la base en un proyecto de Supabase nuevo y vacio.
-- NO se ejecuta contra produccion. Los datos de catalogo estan en seed.sql.
-- Desde ahora, todo cambio va como migracion en supabase/migrations.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Esquemas y extensiones
-- ---------------------------------------------------------------------
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. Secuencias
-- ---------------------------------------------------------------------
create sequence public.crm_id_seq start 1 increment 1 minvalue 1 cache 1;

-- ---------------------------------------------------------------------
-- 3. Funciones
-- ---------------------------------------------------------------------
create or replace function public.generar_crm_id()
 returns text
 language plpgsql
 set search_path to ''
as $function$
begin
  return 'CRM-' || extract(year from now())::text || '-' || lpad(nextval('public.crm_id_seq')::text, 5, '0');
end;
$function$;

create or replace function public.gestionar_consolidacion()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
DECLARE
  horas_transcurridas DECIMAL;
BEGIN
  -- Calcular fecha límite automáticamente al insertar
  IF TG_OP = 'INSERT' THEN
    NEW.fecha_limite := NEW.fecha_conversion + INTERVAL '72 hours';
  END IF;

  -- Actualizar estado de alerta si no está completado
  IF NEW.completado = false THEN
    horas_transcurridas := EXTRACT(EPOCH FROM (NOW() - NEW.fecha_conversion)) / 3600;
    IF horas_transcurridas <= 24 THEN
      NEW.estado_alerta := 'verde';
    ELSIF horas_transcurridas <= 48 THEN
      NEW.estado_alerta := 'amarillo';
    ELSIF horas_transcurridas <= 72 THEN
      NEW.estado_alerta := 'naranja';
    ELSE
      NEW.estado_alerta := 'rojo';
    END IF;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$function$;

create or replace function private.get_iglesia_id()
 returns uuid
 language sql
 stable security definer
 set search_path to ''
as $function$
  select iglesia_id from public.perfiles where id = (select auth.uid())
$function$;

create or replace function private.es_consolidador_de(p_miembro uuid)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.consolidaciones c
    where c.miembro_id = p_miembro and c.consolidador_id = (select auth.uid())
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
    where c.id = p_casa and c.lider_id = (select auth.uid())
  )
$function$;

create or replace function private.es_propietario()
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1
    from public.perfiles pf
    join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
    where pf.id = (select auth.uid()) and pf.activo and r.es_propietario
  )
$function$;

create or replace function private.tiene_modulo(p_modulo text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.iglesias i
    where i.id = (select private.get_iglesia_id()) and i.activa
      and (
        exists (select 1 from public.plan_modulos pm where pm.plan = i.plan and pm.modulo = p_modulo)
        or exists (
          select 1 from public.iglesia_modulos im
          where im.iglesia_id = i.id and im.modulo = p_modulo and im.activo
            and im.desde <= now() and (im.hasta is null or im.hasta > now())
        )
      )
  )
$function$;

create or replace function private.tiene_permiso(p_permiso text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.permisos pe
    where pe.clave = p_permiso and private.tiene_modulo(pe.modulo)
  ) and exists (
    select 1
    from public.perfiles pf
    join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
    where pf.id = (select auth.uid())
      and pf.activo
      and (r.es_propietario
           or exists (select 1 from public.rol_permisos rp where rp.rol_id = r.id and rp.permiso = p_permiso))
  )
$function$;

create or replace function private.guardar_consolidacion()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
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
  return new;
end;
$function$;

create or replace function private.guardar_iglesia()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.plan is distinct from old.plan or new.activa is distinct from old.activa
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo then
    raise exception 'El plan, el estado y la direccion de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$function$;

create or replace function private.guardar_perfil()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.iglesia_id is distinct from old.iglesia_id then
    raise exception 'No se puede cambiar la iglesia de un usuario';
  end if;
  if (new.rol is distinct from old.rol or new.activo is distinct from old.activo)
     and not private.tiene_permiso('usuarios.gestionar') then
    raise exception 'Sin permiso para cambiar el rol o el estado de un usuario';
  end if;
  if new.rol is distinct from old.rol
     and (new.rol = 'propietario' or old.rol = 'propietario')
     and not private.es_propietario() then
    raise exception 'Solo el propietario puede asignar o retirar el rol de propietario';
  end if;
  return new;
end;
$function$;

create or replace function private.sembrar_roles(p_iglesia uuid)
 returns void
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_id uuid;
begin
  insert into public.roles (iglesia_id, clave, nombre, descripcion, es_sistema, es_propietario) values
    (p_iglesia,'propietario','Propietario','Acceso total. Unico que puede cambiar al propietario.',true,true),
    (p_iglesia,'administrador','Administrador','Gestion operativa completa, sin configuracion critica.',true,false),
    (p_iglesia,'lider_casa','Lider de Casa de Oracion','Gestiona su casa y los miembros que le corresponden.',true,false),
    (p_iglesia,'lider_escuela','Lider de Escuela de Formacion','Actualiza el progreso de formacion.',true,false),
    (p_iglesia,'consolidador','Consolidador','Da seguimiento a los nuevos convertidos asignados.',true,false),
    (p_iglesia,'miembro','Miembro','Acceso basico.',true,false)
  on conflict (iglesia_id, clave) do nothing;

  select id into v_id from public.roles where iglesia_id = p_iglesia and clave = 'administrador';
  insert into public.rol_permisos (rol_id, permiso)
    select v_id, clave from public.permisos where clave not in ('iglesia.configurar','roles.gestionar')
  on conflict do nothing;

  select id into v_id from public.roles where iglesia_id = p_iglesia and clave = 'lider_casa';
  insert into public.rol_permisos (rol_id, permiso)
    select v_id, unnest(array['casas.ver_propia','miembros.ver_asignados','asistencia.registrar_propia',
                              'consolidacion.ver_casa','usuarios.ver','zonas.ver'])
  on conflict do nothing;

  select id into v_id from public.roles where iglesia_id = p_iglesia and clave = 'lider_escuela';
  insert into public.rol_permisos (rol_id, permiso)
    select v_id, unnest(array['formacion.ver','formacion.actualizar','miembros.ver','usuarios.ver',
                              'zonas.ver','gamificacion.ver'])
  on conflict do nothing;

  select id into v_id from public.roles where iglesia_id = p_iglesia and clave = 'consolidador';
  insert into public.rol_permisos (rol_id, permiso)
    select v_id, unnest(array['consolidacion.ver_asignados','consolidacion.registrar_contacto',
                              'miembros.ver_asignados','usuarios.ver','zonas.ver'])
  on conflict do nothing;
end;
$function$;

create or replace function private.trg_sembrar_roles()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  perform private.sembrar_roles(new.id);
  return new;
end;
$function$;

-- ---------------------------------------------------------------------
-- 4. Tablas
-- ---------------------------------------------------------------------
create table public.iglesias (
  id uuid default uuid_generate_v4() not null,
  nombre text not null,
  slug text not null,
  logo_url text,
  color_primario text default '#1a4d8f'::text,
  color_secundario text default '#d4af37'::text,
  pais text not null,
  ciudad text not null,
  email_contacto text,
  telefono text,
  plan text default 'semilla'::text,
  activa boolean default true,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  es_demo boolean default false not null
);

create table public.perfiles (
  id uuid not null,
  iglesia_id uuid,
  nombre text not null,
  apellido text not null,
  email text not null,
  telefono text,
  foto_url text,
  rol text default 'miembro'::text not null,
  activo boolean default true,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table public.zonas (
  id uuid default uuid_generate_v4() not null,
  iglesia_id uuid default private.get_iglesia_id() not null,
  codigo text not null,
  nombre text not null,
  descripcion text,
  activa boolean default true,
  created_at timestamp with time zone default now()
);

create table public.casas_oracion (
  id uuid default uuid_generate_v4() not null,
  iglesia_id uuid default private.get_iglesia_id() not null,
  zona_id uuid,
  codigo_zona text not null,
  nombre text,
  lider_id uuid,
  pais text not null,
  estado text,
  ciudad text not null,
  sector text,
  direccion text not null,
  coordenadas_lat numeric(10,8),
  coordenadas_lng numeric(11,8),
  dia_reunion text,
  hora_reunion time without time zone,
  capacidad integer default 20,
  etapa text default 'activa'::text,
  activa boolean default true,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table public.miembros (
  id uuid default uuid_generate_v4() not null,
  iglesia_id uuid default private.get_iglesia_id() not null,
  crm_id text default generar_crm_id() not null,
  casa_oracion_id uuid,
  nombre text not null,
  apellido text not null,
  email text,
  telefono text,
  fecha_nacimiento date,
  genero text,
  estado_civil text,
  profesion text,
  foto_url text,
  fecha_conversion date,
  bautizado boolean default false,
  fecha_bautismo date,
  iglesia_anterior text,
  nivel_formacion integer default 1,
  progreso_formacion integer default 0,
  puntos integer default 0,
  racha_dias integer default 0,
  nivel_compromiso text default 'nuevo'::text,
  tipo text default 'nuevo_convertido'::text,
  activo boolean default true,
  notas text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table public.consolidaciones (
  id uuid default uuid_generate_v4() not null,
  iglesia_id uuid default private.get_iglesia_id() not null,
  miembro_id uuid not null,
  consolidador_id uuid,
  casa_oracion_id uuid,
  fecha_conversion timestamp with time zone default now() not null,
  fecha_limite timestamp with time zone,
  estado_alerta text default 'verde'::text,
  primer_contacto_fecha timestamp with time zone,
  primer_contacto_notas text,
  segundo_contacto_fecha timestamp with time zone,
  segundo_contacto_notas text,
  tercer_contacto_fecha timestamp with time zone,
  tercer_contacto_notas text,
  resultado text,
  completado boolean default false,
  completado_at timestamp with time zone,
  notas text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table public.asistencias (
  id uuid default uuid_generate_v4() not null,
  iglesia_id uuid default private.get_iglesia_id() not null,
  casa_oracion_id uuid not null,
  miembro_id uuid not null,
  fecha date default CURRENT_DATE not null,
  presente boolean default true,
  notas text,
  created_at timestamp with time zone default now()
);

create table public.progreso_formacion (
  id uuid default uuid_generate_v4() not null,
  iglesia_id uuid default private.get_iglesia_id() not null,
  miembro_id uuid not null,
  nivel integer not null,
  nombre_nivel text not null,
  porcentaje integer default 0,
  fecha_inicio date,
  fecha_completado date,
  actualizado_por uuid,
  notas text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table public.logros (
  id uuid default uuid_generate_v4() not null,
  iglesia_id uuid default private.get_iglesia_id() not null,
  miembro_id uuid not null,
  tipo text not null,
  nombre text not null,
  descripcion text,
  puntos_otorgados integer default 0,
  fecha timestamp with time zone default now()
);

create table public.modulos (
  clave text not null,
  nombre text not null,
  descripcion text,
  tipo text not null,
  orden integer default 0 not null
);

create table public.planes (
  clave text not null,
  nombre text not null,
  descripcion text,
  max_miembros integer,
  max_usuarios integer,
  orden integer default 0 not null,
  activo boolean default true not null
);

create table public.plan_modulos (
  plan text not null,
  modulo text not null
);

create table public.iglesia_modulos (
  iglesia_id uuid not null,
  modulo text not null,
  origen text default 'addon'::text not null,
  activo boolean default true not null,
  desde timestamp with time zone default now() not null,
  hasta timestamp with time zone
);

create table public.permisos (
  clave text not null,
  modulo text not null,
  descripcion text not null,
  sensible boolean default false not null
);

create table public.roles (
  id uuid default gen_random_uuid() not null,
  iglesia_id uuid not null,
  clave text not null,
  nombre text not null,
  descripcion text,
  es_sistema boolean default false not null,
  es_propietario boolean default false not null,
  created_at timestamp with time zone default now() not null
);

create table public.rol_permisos (
  rol_id uuid not null,
  permiso text not null
);

create table public.plataforma_admins (
  user_id uuid not null,
  created_at timestamp with time zone default now() not null
);

create table public.plataforma_auditoria (
  id bigint generated always as identity not null,
  actor uuid,
  accion text not null,
  iglesia_id uuid,
  detalle jsonb default '{}'::jsonb not null,
  created_at timestamp with time zone default now() not null
);

-- ---------------------------------------------------------------------
-- 5. Claves primarias, unicas y comprobaciones
-- ---------------------------------------------------------------------
alter table public.asistencias add constraint asistencias_pkey PRIMARY KEY (id);
alter table public.casas_oracion add constraint casas_oracion_pkey PRIMARY KEY (id);
alter table public.consolidaciones add constraint consolidaciones_pkey PRIMARY KEY (id);
alter table public.iglesia_modulos add constraint iglesia_modulos_origen_check CHECK ((origen = ANY (ARRAY['addon'::text, 'cortesia'::text, 'manual'::text])));
alter table public.iglesia_modulos add constraint iglesia_modulos_pkey PRIMARY KEY (iglesia_id, modulo);
alter table public.iglesias add constraint iglesias_pkey PRIMARY KEY (id);
alter table public.iglesias add constraint iglesias_slug_key UNIQUE (slug);
alter table public.logros add constraint logros_pkey PRIMARY KEY (id);
alter table public.miembros add constraint miembros_crm_id_key UNIQUE (crm_id);
alter table public.miembros add constraint miembros_pkey PRIMARY KEY (id);
alter table public.modulos add constraint modulos_pkey PRIMARY KEY (clave);
alter table public.modulos add constraint modulos_tipo_check CHECK ((tipo = ANY (ARRAY['nucleo'::text, 'incluido'::text, 'especial'::text])));
alter table public.perfiles add constraint perfiles_pkey PRIMARY KEY (id);
alter table public.permisos add constraint permisos_pkey PRIMARY KEY (clave);
alter table public.plan_modulos add constraint plan_modulos_pkey PRIMARY KEY (plan, modulo);
alter table public.planes add constraint planes_pkey PRIMARY KEY (clave);
alter table public.plataforma_admins add constraint plataforma_admins_pkey PRIMARY KEY (user_id);
alter table public.plataforma_auditoria add constraint plataforma_auditoria_pkey PRIMARY KEY (id);
alter table public.progreso_formacion add constraint progreso_formacion_pkey PRIMARY KEY (id);
alter table public.rol_permisos add constraint rol_permisos_pkey PRIMARY KEY (rol_id, permiso);
alter table public.roles add constraint roles_iglesia_id_clave_key UNIQUE (iglesia_id, clave);
alter table public.roles add constraint roles_pkey PRIMARY KEY (id);
alter table public.zonas add constraint zonas_pkey PRIMARY KEY (id);

-- ---------------------------------------------------------------------
-- 6. Claves foraneas
-- ---------------------------------------------------------------------
alter table public.asistencias add constraint asistencias_casa_oracion_id_fkey FOREIGN KEY (casa_oracion_id) REFERENCES public.casas_oracion(id);
alter table public.asistencias add constraint asistencias_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.asistencias add constraint asistencias_miembro_id_fkey FOREIGN KEY (miembro_id) REFERENCES public.miembros(id);
alter table public.casas_oracion add constraint casas_oracion_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.casas_oracion add constraint casas_oracion_lider_id_fkey FOREIGN KEY (lider_id) REFERENCES public.perfiles(id);
alter table public.casas_oracion add constraint casas_oracion_zona_id_fkey FOREIGN KEY (zona_id) REFERENCES public.zonas(id);
alter table public.consolidaciones add constraint consolidaciones_casa_oracion_id_fkey FOREIGN KEY (casa_oracion_id) REFERENCES public.casas_oracion(id);
alter table public.consolidaciones add constraint consolidaciones_consolidador_id_fkey FOREIGN KEY (consolidador_id) REFERENCES public.perfiles(id);
alter table public.consolidaciones add constraint consolidaciones_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.consolidaciones add constraint consolidaciones_miembro_id_fkey FOREIGN KEY (miembro_id) REFERENCES public.miembros(id);
alter table public.iglesia_modulos add constraint iglesia_modulos_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.iglesia_modulos add constraint iglesia_modulos_modulo_fkey FOREIGN KEY (modulo) REFERENCES public.modulos(clave) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.iglesias add constraint iglesias_plan_fk FOREIGN KEY (plan) REFERENCES public.planes(clave) ON UPDATE CASCADE;
alter table public.logros add constraint logros_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.logros add constraint logros_miembro_id_fkey FOREIGN KEY (miembro_id) REFERENCES public.miembros(id);
alter table public.miembros add constraint miembros_casa_oracion_id_fkey FOREIGN KEY (casa_oracion_id) REFERENCES public.casas_oracion(id);
alter table public.miembros add constraint miembros_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.perfiles add constraint perfiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.perfiles add constraint perfiles_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.perfiles add constraint perfiles_rol_fk FOREIGN KEY (iglesia_id, rol) REFERENCES public.roles(iglesia_id, clave) ON UPDATE CASCADE;
alter table public.permisos add constraint permisos_modulo_fk FOREIGN KEY (modulo) REFERENCES public.modulos(clave) ON UPDATE CASCADE;
alter table public.plan_modulos add constraint plan_modulos_modulo_fkey FOREIGN KEY (modulo) REFERENCES public.modulos(clave) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.plan_modulos add constraint plan_modulos_plan_fkey FOREIGN KEY (plan) REFERENCES public.planes(clave) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.plataforma_admins add constraint plataforma_admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.plataforma_auditoria add constraint plataforma_auditoria_actor_fkey FOREIGN KEY (actor) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.plataforma_auditoria add constraint plataforma_auditoria_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE SET NULL;
alter table public.progreso_formacion add constraint progreso_formacion_actualizado_por_fkey FOREIGN KEY (actualizado_por) REFERENCES public.perfiles(id);
alter table public.progreso_formacion add constraint progreso_formacion_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.progreso_formacion add constraint progreso_formacion_miembro_id_fkey FOREIGN KEY (miembro_id) REFERENCES public.miembros(id);
alter table public.rol_permisos add constraint rol_permisos_permiso_fkey FOREIGN KEY (permiso) REFERENCES public.permisos(clave) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.rol_permisos add constraint rol_permisos_rol_id_fkey FOREIGN KEY (rol_id) REFERENCES public.roles(id) ON DELETE CASCADE;
alter table public.roles add constraint roles_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;
alter table public.zonas add constraint zonas_iglesia_id_fkey FOREIGN KEY (iglesia_id) REFERENCES public.iglesias(id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------
-- 7. Indices
-- ---------------------------------------------------------------------
create index plataforma_auditoria_iglesia_idx on public.plataforma_auditoria using btree (iglesia_id, created_at desc);

-- ---------------------------------------------------------------------
-- 8. Triggers
-- ---------------------------------------------------------------------
create trigger consolidaciones_guardar before update on public.consolidaciones for each row execute function private.guardar_consolidacion();
create trigger iglesias_guardar before update on public.iglesias for each row execute function private.guardar_iglesia();
create trigger iglesias_sembrar_roles after insert on public.iglesias for each row execute function private.trg_sembrar_roles();
create trigger perfiles_guardar before update on public.perfiles for each row execute function private.guardar_perfil();
create trigger trigger_consolidacion before insert or update on public.consolidaciones for each row execute function public.gestionar_consolidacion();

-- ---------------------------------------------------------------------
-- 9. Seguridad por filas
-- ---------------------------------------------------------------------
alter table public.asistencias enable row level security;
alter table public.casas_oracion enable row level security;
alter table public.consolidaciones enable row level security;
alter table public.iglesia_modulos enable row level security;
alter table public.iglesias enable row level security;
alter table public.logros enable row level security;
alter table public.miembros enable row level security;
alter table public.modulos enable row level security;
alter table public.perfiles enable row level security;
alter table public.permisos enable row level security;
alter table public.plan_modulos enable row level security;
alter table public.planes enable row level security;
alter table public.plataforma_admins enable row level security;
alter table public.plataforma_auditoria enable row level security;  -- sin politicas: solo service_role
alter table public.progreso_formacion enable row level security;
alter table public.rol_permisos enable row level security;
alter table public.roles enable row level security;
alter table public.zonas enable row level security;

-- asistencias
create policy asistencias_ver on public.asistencias for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('asistencia.ver')) or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(casa_oracion_id))));
create policy asistencias_crear on public.asistencias for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('asistencia.registrar')) or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(casa_oracion_id))));
create policy asistencias_editar on public.asistencias for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('asistencia.registrar')) or ((select private.tiene_permiso('asistencia.registrar_propia')) and private.es_lider_de_casa(casa_oracion_id))))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy asistencias_borrar on public.asistencias for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('asistencia.registrar')));

-- casas_oracion
create policy casas_ver on public.casas_oracion for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('casas.ver')) or ((select private.tiene_permiso('casas.ver_propia')) and (lider_id = (select auth.uid())))));
create policy casas_crear on public.casas_oracion for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('casas.crear')));
create policy casas_editar on public.casas_oracion for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('casas.editar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy casas_borrar on public.casas_oracion for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('casas.eliminar')));

-- consolidaciones
create policy consolidaciones_ver on public.consolidaciones for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('consolidacion.ver')) or ((select private.tiene_permiso('consolidacion.ver_asignados')) and (consolidador_id = (select auth.uid()))) or ((select private.tiene_permiso('consolidacion.ver_casa')) and private.es_lider_de_casa(casa_oracion_id))));
create policy consolidaciones_crear on public.consolidaciones for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('consolidacion.crear')));
create policy consolidaciones_editar on public.consolidaciones for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('consolidacion.editar')) or ((select private.tiene_permiso('consolidacion.registrar_contacto')) and (consolidador_id = (select auth.uid())))))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy consolidaciones_borrar on public.consolidaciones for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('consolidacion.eliminar')));

-- progreso_formacion
create policy formacion_ver on public.progreso_formacion for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('formacion.ver')));
create policy formacion_crear on public.progreso_formacion for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('formacion.actualizar')));
create policy formacion_editar on public.progreso_formacion for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('formacion.actualizar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy formacion_borrar on public.progreso_formacion for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('formacion.actualizar')));

-- iglesia_modulos, iglesias
create policy iglesia_modulos_ver on public.iglesia_modulos for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()));
create policy iglesias_ver on public.iglesias for select to authenticated
  using (id = (select private.get_iglesia_id()));
create policy iglesias_editar on public.iglesias for update to authenticated
  using ((id = (select private.get_iglesia_id())) and (select private.tiene_permiso('iglesia.configurar')))
  with check (id = (select private.get_iglesia_id()));

-- logros
create policy logros_ver on public.logros for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('gamificacion.ver')));
create policy logros_crear on public.logros for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('gamificacion.gestionar')));
create policy logros_editar on public.logros for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('gamificacion.gestionar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy logros_borrar on public.logros for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('gamificacion.gestionar')));

-- miembros
create policy miembros_ver on public.miembros for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((select private.tiene_permiso('miembros.ver')) or ((select private.tiene_permiso('miembros.ver_asignados')) and (private.es_consolidador_de(id) or private.es_lider_de_casa(casa_oracion_id)))));
create policy miembros_crear on public.miembros for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('miembros.crear')));
create policy miembros_editar on public.miembros for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('miembros.editar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy miembros_borrar on public.miembros for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('miembros.eliminar')));

-- catalogos de solo lectura
create policy modulos_ver on public.modulos for select to authenticated using (true);
create policy permisos_lectura on public.permisos for select to authenticated using (true);
create policy plan_modulos_ver on public.plan_modulos for select to authenticated using (true);
create policy planes_ver on public.planes for select to authenticated using (true);

-- perfiles
create policy perfiles_ver on public.perfiles for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((id = (select auth.uid())) or (select private.tiene_permiso('usuarios.ver'))));
create policy perfiles_crear on public.perfiles for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('usuarios.gestionar')));
create policy perfiles_editar on public.perfiles for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and ((id = (select auth.uid())) or (select private.tiene_permiso('usuarios.gestionar'))))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy perfiles_borrar on public.perfiles for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (rol <> 'propietario'::text) and (id <> (select auth.uid())) and (select private.tiene_permiso('usuarios.gestionar')));

-- plataforma
create policy plataforma_admin_propio on public.plataforma_admins for select to authenticated
  using (user_id = (select auth.uid()));

-- roles y rol_permisos
create policy roles_ver on public.roles for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()));
create policy roles_crear on public.roles for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (not es_sistema) and (not es_propietario) and (select private.tiene_permiso('roles.gestionar')));
create policy roles_editar on public.roles for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (not es_propietario) and (select private.tiene_permiso('roles.gestionar')))
  with check ((iglesia_id = (select private.get_iglesia_id())) and (not es_propietario));
create policy roles_borrar on public.roles for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (not es_sistema) and (select private.tiene_permiso('roles.gestionar')));

create policy rol_permisos_ver on public.rol_permisos for select to authenticated
  using (exists (select 1 from public.roles r where r.id = rol_permisos.rol_id));
create policy rol_permisos_crear on public.rol_permisos for insert to authenticated
  with check ((exists (select 1 from public.roles r where r.id = rol_permisos.rol_id and not r.es_propietario)) and (select private.tiene_permiso('roles.gestionar')));
create policy rol_permisos_borrar on public.rol_permisos for delete to authenticated
  using ((exists (select 1 from public.roles r where r.id = rol_permisos.rol_id and not r.es_propietario)) and (select private.tiene_permiso('roles.gestionar')));

-- zonas
create policy zonas_ver on public.zonas for select to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('zonas.ver')));
create policy zonas_crear on public.zonas for insert to authenticated
  with check ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('zonas.gestionar')));
create policy zonas_editar on public.zonas for update to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('zonas.gestionar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy zonas_borrar on public.zonas for delete to authenticated
  using ((iglesia_id = (select private.get_iglesia_id())) and (select private.tiene_permiso('zonas.gestionar')));

-- ---------------------------------------------------------------------
-- 10. Permisos de ejecucion y de tabla
-- Las tablas de datos de iglesia conservan los permisos por defecto de
-- Supabase para anon y authenticated; la proteccion real es RLS.
-- ---------------------------------------------------------------------
revoke execute on all functions in schema private from public, anon;
grant execute on function private.get_iglesia_id() to authenticated, service_role;
grant execute on function private.es_consolidador_de(uuid) to authenticated, service_role;
grant execute on function private.es_lider_de_casa(uuid) to authenticated, service_role;
grant execute on function private.es_propietario() to authenticated, service_role;
grant execute on function private.tiene_modulo(text) to authenticated, service_role;
grant execute on function private.tiene_permiso(text) to authenticated, service_role;
revoke execute on function private.sembrar_roles(uuid) from authenticated;
grant execute on function private.sembrar_roles(uuid) to service_role;
revoke execute on function private.trg_sembrar_roles() from authenticated, service_role;
-- Las funciones de trigger guardar_* no tienen EXECUTE para nadie en
-- produccion (lista de permisos vacia); los triggers no lo necesitan.
revoke execute on function private.guardar_consolidacion() from public, anon, authenticated, service_role;
revoke execute on function private.guardar_iglesia() from public, anon, authenticated, service_role;
revoke execute on function private.guardar_perfil() from public, anon, authenticated, service_role;

revoke execute on function public.generar_crm_id() from public, anon;
grant execute on function public.generar_crm_id() to authenticated, service_role;
revoke execute on function public.gestionar_consolidacion() from public, anon, authenticated;
grant execute on function public.gestionar_consolidacion() to service_role;

revoke usage, select, update on sequence public.crm_id_seq from anon;
grant usage, select, update on sequence public.crm_id_seq to authenticated, service_role;

-- Catalogos: authenticated solo lee (sin insert, update ni delete)
revoke insert, update, delete on public.modulos, public.planes, public.plan_modulos, public.permisos,
  public.iglesia_modulos, public.plataforma_admins from authenticated;
revoke all on public.modulos, public.planes, public.plan_modulos, public.permisos,
  public.iglesia_modulos, public.plataforma_admins, public.roles, public.rol_permisos from anon;

-- Auditoria: solo service_role
revoke all on public.plataforma_auditoria from anon, authenticated;
