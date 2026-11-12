-- Vive ADN, paquete de aplicación 03 de 07. Aplicar en orden y detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261105030433_dar_plantillas.sql (sha256 e1ed00e5fedb) =====
-- Plantillas de la pagina de dar. Cada iglesia elige un estilo, su apariencia y sus propios fondos
-- (no solo diezmo, ofrenda y donacion), cada uno con el enlace de su sitio de recaudo. La app no
-- procesa pagos: la pagina ayuda a calcular el aporte y lleva a la persona al sitio de la iglesia.

-- 1. Fondos propios: clave libre (minusculas, numeros y guion bajo), nombre, descripcion y orden.
--    Los tres tipos originales siguen valiendo y se traducen en la web si no tienen nombre.
alter table public.enlaces_dar drop constraint if exists enlaces_dar_tipo_check;
alter table public.enlaces_dar add constraint enlaces_dar_tipo_check check (tipo ~ '^[a-z0-9_]{1,40}$');
alter table public.enlaces_dar add column nombre text check (nombre is null or length(btrim(nombre)) between 1 and 80);
alter table public.enlaces_dar add column descripcion text check (descripcion is null or length(descripcion) <= 200);
alter table public.enlaces_dar add column orden integer not null default 0 check (orden between 0 and 1000);

-- Un maximo de 20 fondos por iglesia: la pagina publica los devuelve todos.
-- Un upsert que acaba siendo una actualizacion tambien pasa por este disparador (BEFORE INSERT se ejecuta
-- antes de resolver el conflicto), asi que solo se cuenta cuando el fondo todavia no existe.
create or replace function private.limitar_fondos_dar()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
begin
  if not exists (select 1 from public.enlaces_dar where iglesia_id = new.iglesia_id and tipo = new.tipo)
     and (select count(*) from public.enlaces_dar where iglesia_id = new.iglesia_id) >= 20 then
    raise exception 'Se admiten como maximo 20 fondos por iglesia' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke execute on function private.limitar_fondos_dar() from public, anon, authenticated, service_role;
create trigger enlaces_dar_limite before insert on public.enlaces_dar
  for each row execute function private.limitar_fondos_dar();

-- 2. Apariencia de la pagina publica de cada iglesia
create table public.dar_config (
  iglesia_id uuid primary key default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  plantilla text not null default 'clasica' check (plantilla in ('clasica', 'dia')),
  titulo text check (titulo is null or length(titulo) <= 100),
  subtitulo text check (subtitulo is null or length(subtitulo) <= 200),
  color_primario text not null default '#00523c' check (color_primario ~ '^#[0-9a-fA-F]{6}$'),
  color_acento text not null default '#f5a623' check (color_acento ~ '^#[0-9a-fA-F]{6}$'),
  logo_url text check (logo_url is null or (length(logo_url) <= 500 and logo_url ~ '^https://[^[:space:]]+$')),
  calculadora text not null default 'dia' check (calculadora in ('dia', 'diezmo', 'ninguna')),
  moneda text not null default 'EUR' check (moneda ~ '^[A-Z]{3}$'),
  updated_at timestamptz not null default now()
);

alter table public.dar_config enable row level security;

create policy dar_config_ver on public.dar_config for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()));
create policy dar_config_crear on public.dar_config for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
create policy dar_config_editar on public.dar_config for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy dar_config_borrar on public.dar_config for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));

grant select, insert, update, delete on public.dar_config to authenticated;
grant all on public.dar_config to service_role;

-- ===== migrations/20261105080527_red_iglesias.sql (sha256 c8720ac72c4c) =====
-- Red de iglesias: una iglesia madre puede tener sedes. Cada sede sigue siendo una iglesia con sus propios
-- datos y usuarios. La madre solo ve un resumen agregado, y solo si la plataforma lo permite para esa sede.
-- Niveles de acceso hoy: 'ninguno' (la madre no ve nada de la sede) y 'resumen' (cifras agregadas).
-- Los niveles se pueden ampliar con otra migracion sin tocar las iglesias ya configuradas.

alter table public.iglesias add column iglesia_madre_id uuid references public.iglesias(id) on delete set null;
alter table public.iglesias add column red_acceso text not null default 'resumen' check (red_acceso in ('ninguno', 'resumen'));
alter table public.iglesias add constraint iglesias_madre_distinta check (iglesia_madre_id is null or iglesia_madre_id <> id);
create index iglesias_madre_idx on public.iglesias (iglesia_madre_id) where iglesia_madre_id is not null;

-- La iglesia puede leer a quien es su madre y su nivel; solo la plataforma (service_role) los cambia.
-- Quien tiene sesion (authenticated) no puede cambiarlos: lo impide el disparador private.guardar_iglesia de abajo.
grant select (iglesia_madre_id, red_acceso) on public.iglesias to authenticated;

-- Un solo nivel: una madre no es sede de otra y una sede no tiene sedes. Se bloquea la fila de la madre
-- para que dos cambios a la vez no puedan formar una cadena.
create or replace function private.limitar_red_iglesias()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
begin
  if new.iglesia_madre_id is null then
    return new;
  end if;
  perform 1 from public.iglesias where id = new.iglesia_madre_id for update;
  if exists (select 1 from public.iglesias where id = new.iglesia_madre_id and iglesia_madre_id is not null) then
    raise exception 'Una iglesia que ya es sede no puede ser iglesia madre' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.iglesias where iglesia_madre_id = new.id) then
    raise exception 'Una iglesia que tiene sedes no puede ser sede de otra' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
revoke execute on function private.limitar_red_iglesias() from public, anon, authenticated, service_role;
create trigger iglesias_red before insert or update of iglesia_madre_id on public.iglesias
  for each row execute function private.limitar_red_iglesias();

-- Defensa en profundidad: quien no es la plataforma no cambia la red ni el acceso
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
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo
     or new.iglesia_madre_id is distinct from old.iglesia_madre_id or new.red_acceso is distinct from old.red_acceso then
    raise exception 'El plan, el estado, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$function$;
revoke execute on function private.guardar_iglesia() from public, anon, authenticated, service_role;

-- ===== migrations/20261105195348_registro_autoservicio.sql (sha256 b7374cdf88e1) =====
-- Registro de iglesias por su cuenta (alta autoservicio).
-- En la etapa de pruebas se exige un codigo de acceso a la beta para que no entre cualquiera, y cada
-- dispositivo tiene un limite de intentos. Al lanzar basta con desactivar la exigencia del codigo.
-- Todo es de uso exclusivo del servidor: ninguna de estas tablas ni funciones se abre a anon ni a authenticated.

create table public.plataforma_ajustes (
  clave text primary key check (clave ~ '^[a-z_]{1,60}$'),
  valor jsonb not null,
  updated_at timestamptz not null default now()
);
insert into public.plataforma_ajustes (clave, valor) values
  ('registro_abierto', 'true'::jsonb),
  ('registro_requiere_codigo', 'true'::jsonb);

create table public.registro_codigos (
  id uuid primary key default gen_random_uuid(),
  codigo_hash text not null unique check (codigo_hash ~ '^[0-9a-f]{64}$'),
  etiqueta text not null check (length(btrim(etiqueta)) between 1 and 80),
  usos_max integer not null default 1 check (usos_max between 1 and 1000),
  usos integer not null default 0 check (usos >= 0),
  vence_en timestamptz,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  check (usos <= usos_max)
);

create table public.registro_intentos (
  id bigint generated always as identity primary key,
  ip_hash text not null check (ip_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
create index registro_intentos_ip_idx on public.registro_intentos (ip_hash, created_at desc);

-- Solo el servidor (service_role) toca estas tablas
do $$
declare t text;
begin
  foreach t in array array['plataforma_ajustes', 'registro_codigos', 'registro_intentos'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('create policy solo_servicio on public.%I for all to anon, authenticated using (false) with check (false)', t);
  end loop;
end $$;
grant usage, select on sequence public.registro_intentos_id_seq to service_role;

-- Usa un codigo de forma atomica: devuelve su id, o nada si no existe, esta agotado, vencido o desactivado
create or replace function public.consumir_codigo_registro(p_hash text)
 returns uuid
 language sql
 set search_path to ''
as $$
  update public.registro_codigos set usos = usos + 1
   where codigo_hash = p_hash and activo and usos < usos_max and (vence_en is null or vence_en > now())
  returning id;
$$;

-- Devuelve un uso cuando el alta no llego a completarse
create or replace function public.devolver_codigo_registro(p_id uuid)
 returns void
 language sql
 set search_path to ''
as $$
  update public.registro_codigos set usos = greatest(usos - 1, 0) where id = p_id;
$$;

-- Cuenta el intento de un dispositivo y dice si aun esta dentro del limite. El cerrojo evita que dos
-- peticiones simultaneas se cuelen a la vez.
create or replace function public.registrar_intento_registro(p_ip_hash text, p_max integer, p_minutos integer)
 returns boolean
 language plpgsql
 set search_path to ''
as $$
declare n integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('registro:' || p_ip_hash, 0));
  delete from public.registro_intentos where created_at < now() - interval '2 days';
  select count(*) into n from public.registro_intentos
   where ip_hash = p_ip_hash and created_at > now() - make_interval(mins => p_minutos);
  if n >= p_max then
    return false;
  end if;
  insert into public.registro_intentos (ip_hash) values (p_ip_hash);
  return true;
end;
$$;

do $$
declare f text;
begin
  foreach f in array array['consumir_codigo_registro(text)', 'devolver_codigo_registro(uuid)', 'registrar_intento_registro(text, integer, integer)'] loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;

-- ===== migrations/20261105210545_limites_plan_e_indices.sql (sha256 a6c0f69cd4e0) =====
-- Corte duro de los limites del plan y indices de las tablas que mas crecen.
--
-- Hasta ahora planes.max_miembros y planes.max_usuarios solo se mostraban: nada los hacia cumplir.
-- Ahora la base rechaza el alta que supera el tope, con el mensaje "PLAN_LIMITE: miembros" o
-- "PLAN_LIMITE: usuarios". Un limite nulo significa sin tope. Cada iglesia se serializa con un cerrojo
-- propio, para que dos altas simultaneas no se cuelen a la vez.
--   * miembros: cuentan los activos; tambien se comprueba al reactivar uno
--   * usuarios: cuentan los perfiles activos; una invitacion pendiente reserva su plaza

create or replace function private.limitar_plan_miembros()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare v_max integer; v_n integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_miembros into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.miembros where iglesia_id = new.iglesia_id and activo;
  if v_n >= v_max then
    raise exception 'PLAN_LIMITE: miembros' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

create or replace function private.limitar_plan_usuarios()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare v_max integer; v_n integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  if v_n >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

-- Una invitacion pendiente reserva una plaza: perfiles activos mas invitaciones vigentes no superan el tope
create or replace function private.limitar_plan_invitaciones()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare v_max integer; v_n integer; v_i integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  select count(*) into v_i from public.invitaciones
   where iglesia_id = new.iglesia_id and usada_en is null and revocada_en is null and caduca_en > now();
  if v_n + v_i >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

revoke execute on function private.limitar_plan_miembros() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_usuarios() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_invitaciones() from public, anon, authenticated, service_role;

create trigger miembros_limite_plan before insert or update of activo on public.miembros
  for each row execute function private.limitar_plan_miembros();
create trigger perfiles_limite_plan before insert or update of activo on public.perfiles
  for each row execute function private.limitar_plan_usuarios();
create trigger invitaciones_limite_plan before insert on public.invitaciones
  for each row execute function private.limitar_plan_invitaciones();

-- El registro por QR no debe romperse cuando la iglesia no tiene plazas: a quien llega se le responde
-- como si el registro estuviera cerrado. Es la misma funcion de antes con un bloque de captura alrededor del alta.
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
    begin
      insert into public.miembros (iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, activo, notas)
        values (c.iglesia_id, btrim(p_nombre), btrim(p_apellido), nullif(btrim(coalesce(p_email, '')), ''), btrim(p_telefono),
                c.casa_oracion_id, true, 'Registrado por QR en el evento: ' || c.titulo)
        returning id into v_miembro;
    exception when check_violation then
      if sqlerrm like 'PLAN_LIMITE%' then return 'cerrado'; end if;
      raise;
    end;
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

-- Indices que empiezan por iglesia_id, que es por lo que filtra la seguridad por filas, y que cubren
-- las claves foraneas compuestas (iglesia_id, id) de las tablas que mas crecen
create index asistencia_evento_iglesia_evento_idx on public.asistencia_evento (iglesia_id, evento_id);
create index asistencia_evento_iglesia_miembro_idx on public.asistencia_evento (iglesia_id, miembro_id);
create index checkin_registros_iglesia_evento_idx on public.checkin_registros (iglesia_id, evento_id);
create index checkin_registros_iglesia_miembro_idx on public.checkin_registros (iglesia_id, miembro_id);
create index evento_checkin_iglesia_evento_idx on public.evento_checkin (iglesia_id, evento_id);
create index eventos_iglesia_casa_idx on public.eventos (iglesia_id, casa_oracion_id);
create index invitaciones_iglesia_rol_idx on public.invitaciones (iglesia_id, rol);
create index invitaciones_creada_por_idx on public.invitaciones (creada_por);
create index zonas_lider_idx on public.zonas (lider_id);

-- ===== migrations/20261105210912_referencias_compuestas.sql (sha256 fda5cb6d0e11) =====
-- Las dos ultimas claves foraneas simples entre tablas de iglesia pasan a compuestas (iglesia_id, id).
-- Con la clave simple, zonas.lider_id e invitaciones.creada_por podian apuntar a un perfil de otra iglesia.
-- Al borrar el perfil solo se anula la columna de la persona, nunca iglesia_id (ON DELETE SET NULL con lista de columnas).

alter table public.zonas drop constraint zonas_lider_id_fkey;
alter table public.zonas add constraint zonas_lider_fk
  foreign key (iglesia_id, lider_id) references public.perfiles (iglesia_id, id) on delete set null (lider_id);

alter table public.invitaciones drop constraint invitaciones_creada_por_fkey;
alter table public.invitaciones add constraint invitaciones_creada_por_fk
  foreign key (iglesia_id, creada_por) references public.perfiles (iglesia_id, id) on delete set null (creada_por);

-- ===== migrations/20261105211108_limites_plan_definer.sql (sha256 b1c0e087e042) =====
-- Correccion de los limites del plan, dos hallazgos reales de la revision:
--  1. Los disparadores corrian con los permisos de quien da de alta, asi que contaban solo las filas que su seguridad
--     por filas le deja ver. Un colaborador ve cero miembros ajenos: el tope no le afectaba. Ahora son SECURITY DEFINER
--     (en private, con search_path fijo) y cuentan todas las filas de la iglesia.
--  2. Reactivar o dar de alta un perfil ignoraba las plazas reservadas por invitaciones pendientes, y podia dejar sin
--     sitio a quien aceptaba una invitacion vigente. Ahora los usuarios cuentan perfiles activos mas invitaciones vigentes.
--     Quien acepta una invitacion no se cuenta dos veces: reclamar_invitacion la marca como usada antes de crear el perfil.

create or replace function private.limitar_plan_miembros()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_max integer; v_n integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_miembros into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.miembros where iglesia_id = new.iglesia_id and activo;
  if v_n >= v_max then
    raise exception 'PLAN_LIMITE: miembros' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

create or replace function private.limitar_plan_usuarios()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_max integer; v_n integer; v_i integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  select count(*) into v_i from public.invitaciones
   where iglesia_id = new.iglesia_id and usada_en is null and revocada_en is null and caduca_en > now();
  if v_n + v_i >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

create or replace function private.limitar_plan_invitaciones()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $$
declare v_max integer; v_n integer; v_i integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  select count(*) into v_i from public.invitaciones
   where iglesia_id = new.iglesia_id and usada_en is null and revocada_en is null and caduca_en > now();
  if v_n + v_i >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

revoke execute on function private.limitar_plan_miembros() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_usuarios() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_invitaciones() from public, anon, authenticated, service_role;

-- ===== migrations/20261105211929_ciclo_vida_iglesia.sql (sha256 10f247560f00) =====
-- Ciclo de vida de la iglesia: onboarding, prueba, activa, receso y suspendida.
-- `activa` sigue siendo la unica puerta que leen las politicas y las funciones de borde;
-- `etapa` la gobierna y la mantiene sincronizada un disparador, de modo que nada existente cambia.
--   onboarding, prueba, activa  -> activa = true
--   receso, suspendida          -> activa = false (los datos se conservan intactos)
-- Una prueba vencida corta los modulos de pago (tiene_modulo), sin tocar `activa`.

alter table public.iglesias
  add column etapa text not null default 'activa'
    constraint iglesias_etapa_check check (etapa in ('onboarding', 'prueba', 'activa', 'receso', 'suspendida')),
  add column etapa_desde timestamptz not null default now(),
  add column prueba_hasta timestamptz;

update public.iglesias set etapa = case when activa then 'activa' else 'suspendida' end;

create or replace function private.sincronizar_etapa()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if tg_op = 'INSERT' then
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
  elsif new.etapa is distinct from old.etapa then
    -- La etapa manda
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
    new.etapa_desde := now();
  elsif new.activa is distinct from old.activa then
    -- Compatibilidad con quien aun cambia solo `activa`
    new.etapa := case when new.activa then 'activa' else 'suspendida' end;
    new.etapa_desde := now();
  end if;
  if new.etapa = 'prueba' and new.prueba_hasta is null then
    new.prueba_hasta := now() + interval '30 days';
  elsif new.etapa <> 'prueba' then
    new.prueba_hasta := null;
  end if;
  return new;
end $$;
revoke all on function private.sincronizar_etapa() from public, anon, authenticated, service_role;

create trigger iglesias_sincronizar_etapa
  before insert or update on public.iglesias
  for each row execute function private.sincronizar_etapa();

-- Una prueba vencida deja de dar modulos
create or replace function private.tiene_modulo(p_modulo text)
returns boolean language sql stable security definer set search_path to '' as $$
  select exists (
    select 1 from public.iglesias i
    where i.id = (select private.get_iglesia_id()) and i.activa
      and (i.etapa <> 'prueba' or i.prueba_hasta is null or i.prueba_hasta > now())
      and (
        exists (select 1 from public.plan_modulos pm where pm.plan = i.plan and pm.modulo = p_modulo)
        or exists (
          select 1 from public.iglesia_modulos im
          where im.iglesia_id = i.id and im.modulo = p_modulo and im.activo
            and im.desde <= now() and (im.hasta is null or im.hasta > now())
        )
      )
  )
$$;

-- ===== migrations/20261105212425_ciclo_vida_guardia.sql (sha256 4c9318c19970) =====
-- La etapa y la fecha de prueba solo las cambia la plataforma, igual que el plan y el estado.
-- Sin esto, quien tiene iglesia.configurar podia prorrogar su prueba o salir del receso.
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
     or new.prueba_hasta is distinct from old.prueba_hasta then
    raise exception 'El plan, el estado, la etapa, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$$;

-- ===== migrations/20261105221251_exportar_borrar_iglesia.sql (sha256 7763c54aff15) =====
-- Exportacion y borrado completo de una iglesia (RGPD: portabilidad y supresion).
-- Las dos funciones solo las ejecuta service_role: las llama la funcion de borde `plataforma`,
-- que valida a quien pide la operacion.

-- 1. Borrado programado: solo desde receso o suspendida, y solo lo fija la plataforma.
alter table public.iglesias
  add column borrado_programado_en timestamptz,
  add constraint iglesias_borrado_check check (borrado_programado_en is null or etapa in ('receso', 'suspendida'));

-- Si la iglesia sale de receso o suspension, el borrado programado se cancela solo
create or replace function private.sincronizar_etapa()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if tg_op = 'INSERT' then
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
  elsif new.etapa is distinct from old.etapa then
    new.activa := new.etapa in ('onboarding', 'prueba', 'activa');
    new.etapa_desde := now();
  elsif new.activa is distinct from old.activa then
    new.etapa := case when new.activa then 'activa' else 'suspendida' end;
    new.etapa_desde := now();
  end if;
  if new.etapa = 'prueba' and new.prueba_hasta is null then
    new.prueba_hasta := now() + interval '30 days';
  elsif new.etapa <> 'prueba' then
    new.prueba_hasta := null;
  end if;
  -- Al cambiar de etapa fuera de receso o suspension se cancela; programarlo estando fuera lo rechaza la restriccion
  if new.etapa not in ('receso', 'suspendida') and (tg_op = 'INSERT' or new.etapa is distinct from old.etapa) then
    new.borrado_programado_en := null;
  end if;
  return new;
end $$;

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
     or new.borrado_programado_en is distinct from old.borrado_programado_en then
    raise exception 'El plan, el estado, la etapa, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$$;

-- 2. Exportacion: recorre todas las tablas con iglesia_id, de modo que una tabla nueva
--    entra sola. Se excluyen los secretos (tokens de QR e invitacion, huella de IP).
create or replace function public.exportar_iglesia(p_iglesia uuid)
returns jsonb language plpgsql set search_path to '' as $$
declare
  r record;
  filas jsonb;
  tablas jsonb := '{}'::jsonb;
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
      and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
    order by c.relname
  loop
    execute format('select coalesce(jsonb_agg(to_jsonb(t) - %L::text[]), ''[]''::jsonb) from public.%I t where t.iglesia_id = $1',
                   array['token', 'token_hash', 'ip_hash'], r.relname)
      into filas using p_iglesia;
    tablas := tablas || jsonb_build_object(r.relname, filas);
  end loop;
  -- La unica tabla de iglesia sin iglesia_id propio
  select coalesce(jsonb_agg(to_jsonb(rp)), '[]'::jsonb) into filas
    from public.rol_permisos rp join public.roles ro on ro.id = rp.rol_id where ro.iglesia_id = p_iglesia;
  tablas := tablas || jsonb_build_object('rol_permisos', filas);
  return jsonb_build_object(
    'formato', 'viveadn-exportacion-1',
    'exportado_en', now(),
    'iglesia', (select to_jsonb(i) from public.iglesias i where i.id = p_iglesia),
    'tablas', tablas
  );
end $$;

-- 3. Borrado: solo si el plazo programado ya vencio. Devuelve los usuarios de acceso que la
--    funcion de borde debe borrar de Auth (los administradores de plataforma se respetan).
--    La auditoria conserva la accion y la fecha, pero pierde el detalle y el enlace a la iglesia.
create or replace function public.borrar_iglesia(p_iglesia uuid)
returns uuid[] language plpgsql set search_path to '' as $$
declare
  v record;
  usuarios uuid[];
begin
  select etapa, borrado_programado_en into v from public.iglesias where id = p_iglesia for update;
  if not found then raise exception 'La iglesia no existe'; end if;
  if v.borrado_programado_en is null or v.borrado_programado_en > now() then
    raise exception 'BORRADO_NO_VENCIDO' using errcode = 'check_violation';
  end if;
  select coalesce(array_agg(p.id), '{}') into usuarios
    from public.perfiles p
    where p.iglesia_id = p_iglesia and not exists (select 1 from public.plataforma_admins a where a.user_id = p.id);
  update public.plataforma_auditoria set detalle = '{}'::jsonb where iglesia_id = p_iglesia;
  delete from public.iglesias where id = p_iglesia;
  return usuarios;
end $$;

revoke all on function public.exportar_iglesia(uuid), public.borrar_iglesia(uuid) from public, anon, authenticated;
grant execute on function public.exportar_iglesia(uuid), public.borrar_iglesia(uuid) to service_role;

-- ===== migrations/20261105221748_exportar_sin_secretos_anidados.sql (sha256 4704fa94b22e) =====
-- La exportacion tambien quita los secretos que viven dentro de `detalle` (p. ej. el ip_hash
-- que guarda el registro por autoservicio en la auditoria), no solo los del primer nivel.
create or replace function public.exportar_iglesia(p_iglesia uuid)
returns jsonb language plpgsql set search_path to '' as $$
declare
  r record;
  filas jsonb;
  tablas jsonb := '{}'::jsonb;
  secretos constant text[] := array['token', 'token_hash', 'ip_hash'];
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
      and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
    order by c.relname
  loop
    execute format(
      'select coalesce(jsonb_agg(case when jsonb_typeof(to_jsonb(t)->''detalle'') = ''object'' '
      || 'then jsonb_set(to_jsonb(t) - %1$L::text[], ''{detalle}'', (to_jsonb(t)->''detalle'') - %1$L::text[]) '
      || 'else to_jsonb(t) - %1$L::text[] end), ''[]''::jsonb) from public.%2$I t where t.iglesia_id = $1',
      secretos, r.relname)
      into filas using p_iglesia;
    tablas := tablas || jsonb_build_object(r.relname, filas);
  end loop;
  select coalesce(jsonb_agg(to_jsonb(rp)), '[]'::jsonb) into filas
    from public.rol_permisos rp join public.roles ro on ro.id = rp.rol_id where ro.iglesia_id = p_iglesia;
  tablas := tablas || jsonb_build_object('rol_permisos', filas);
  return jsonb_build_object(
    'formato', 'viveadn-exportacion-1',
    'exportado_en', now(),
    'iglesia', (select to_jsonb(i) from public.iglesias i where i.id = p_iglesia),
    'tablas', tablas
  );
end $$;

revoke all on function public.exportar_iglesia(uuid) from public, anon, authenticated;
grant execute on function public.exportar_iglesia(uuid) to service_role;

-- ===== migrations/20261105222115_archivos_por_iglesia.sql (sha256 d05b0fd24ec3) =====
-- Almacenamiento de archivos con aislamiento por iglesia.
-- Dos cubos; en ambos la primera carpeta de la ruta es el id de la iglesia: {iglesia_id}/...
--   iglesia-marca     publico para leer (logos que ven las paginas publicas). SVG excluido: puede llevar scripts.
--   iglesia-archivos  privado (documentos, certificados, fotos). Se lee con URL firmada.
-- Escribir exige el permiso iglesia.configurar. Leer en el cubo privado exige que la iglesia este operativa.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('iglesia-marca', 'iglesia-marca', true, 2097152, array['image/png', 'image/jpeg', 'image/webp']),
  ('iglesia-archivos', 'iglesia-archivos', false, 10485760, array['application/pdf', 'image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- La carpeta raiz de la ruta debe ser la iglesia de quien pregunta
create or replace function private.ruta_de_mi_iglesia(p_ruta text)
returns boolean language sql stable security definer set search_path to '' as $$
  select (storage.foldername(p_ruta))[1] = (select private.get_iglesia_id())::text
$$;
revoke all on function private.ruta_de_mi_iglesia(text) from public, anon, authenticated, service_role;
grant execute on function private.ruta_de_mi_iglesia(text) to authenticated;

create policy archivos_marca_leer on storage.objects for select to authenticated
  using (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)));
create policy archivos_marca_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_marca_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')))
  with check (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_marca_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'iglesia-marca' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));

create policy archivos_privado_leer on storage.objects for select to authenticated
  using (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_modulo('iglesia')));
create policy archivos_privado_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_privado_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')))
  with check (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));
create policy archivos_privado_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'iglesia-archivos' and (select private.ruta_de_mi_iglesia(name)) and (select private.tiene_permiso('iglesia.configurar')));

-- ===== migrations/20261105223418_modo_alias.sql (sha256 c2a34c599361) =====
-- Modo alias de la iglesia (OP72 v2): la persona se registra con un alias o ID interno, no con su identidad civil.
-- Si el dato no se guarda, no puede filtrarse ni hace falta enmascararlo. En este modo la base normaliza
-- cada miembro nuevo: el alias va en `nombre`, `apellido` queda vacio y no se guarda correo.
-- El telefono se conserva porque la llamada de las 72 horas lo necesita. Los miembros que ya existian no se tocan.

alter table public.iglesias add column modo_alias boolean not null default false;

create or replace function private.aplicar_modo_alias()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if exists (select 1 from public.iglesias i where i.id = new.iglesia_id and i.modo_alias) then
    -- En una edicion solo se toca lo que cambia, para no borrar lo que ya habia
    if tg_op = 'INSERT' or new.apellido is distinct from old.apellido then new.apellido := ''; end if;
    if tg_op = 'INSERT' or new.email is distinct from old.email then new.email := null; end if;
  end if;
  return new;
end $$;
revoke all on function private.aplicar_modo_alias() from public, anon, authenticated, service_role;

create trigger miembros_modo_alias
  before insert or update on public.miembros
  for each row execute function private.aplicar_modo_alias();

-- La pagina publica de registro necesita saber si pide alias o nombre y apellido
create or replace function public.info_checkin(p_token text)
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare c record; v_abre timestamptz; v_cierra timestamptz; v_n integer; v_estado text;
begin
  select ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.lugar, e.cancelado, i.nombre as iglesia, i.email_contacto, i.modo_alias
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
    'evento', c.titulo, 'inicia_en', c.inicia_en, 'lugar', c.lugar, 'alias', c.modo_alias);
end;
$$;

-- registrar_checkin: lee el modo de la iglesia y, fuera del modo alias, sigue exigiendo el apellido
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
begin
  select ec.iglesia_id, ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.casa_oracion_id, e.cancelado, i.modo_alias
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token
   for update of ec;
  if not found or not c.activo or c.cancelado then return 'no_valido'; end if;
  -- La pagina publica deja el apellido opcional porque no sabe el modo de la iglesia: aqui se exige si no es modo alias
  if not c.modo_alias and btrim(coalesce(p_apellido, '')) = '' then return 'datos'; end if;

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
    begin
      insert into public.miembros (iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, activo, notas)
        values (c.iglesia_id, btrim(p_nombre), btrim(p_apellido), nullif(btrim(coalesce(p_email, '')), ''), btrim(p_telefono),
                c.casa_oracion_id, true, 'Registrado por QR en el evento: ' || c.titulo)
        returning id into v_miembro;
    exception when check_violation then
      if sqlerrm like 'PLAN_LIMITE%' then return 'cerrado'; end if;
      raise;
    end;
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

-- ===== migrations/20261105231653_op72_avanzado.sql (sha256 bf28643c5ad8) =====
-- OP72 gratuito y de pago.
--   Gratuito (modulo consolidacion, en todos los planes): registro, asignacion, tres contactos, resultado y las 72 horas con su color.
--   De pago (modulo op72_avanzado, en Basico y Premium, o como complemento en Semilla): metricas avanzadas del seguimiento.
--   Las alertas automaticas por correo o WhatsApp quedan para cuando exista el canal de envio.
-- El modulo se activa con la maquinaria de planes y complementos que ya existe: no hay logica nueva de licencias.

insert into public.modulos (clave, nombre, descripcion, tipo, orden) values
  ('op72_avanzado', 'OP72 avanzado', 'Metricas avanzadas del seguimiento de 72 horas por consolidador y por casa', 'especial', 215)
on conflict (clave) do nothing;
insert into public.plan_modulos (plan, modulo) values ('basico', 'op72_avanzado'), ('premium', 'op72_avanzado')
on conflict do nothing;

-- Metricas del periodo. Exige ver toda la consolidacion de la iglesia (consolidacion.ver) y se ejecuta con los permisos de
-- quien llama, asi que solo cuenta las consolidaciones que su rol puede ver. Viven en Consolidacion y no en Reportes porque
-- Consolidacion esta en todos los planes y Reportes no.
create or replace function public.metricas_op72(p_desde timestamptz default (now() - interval '30 days'))
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare r jsonb;
begin
  if not (select private.tiene_modulo('op72_avanzado')) then
    raise exception 'MODULO_NO_CONTRATADO' using errcode = '42501';
  end if;
  if not (select private.tiene_permiso('consolidacion.ver')) then
    raise exception 'SIN_PERMISO' using errcode = '42501';
  end if;
  with c as (
    select co.consolidador_id, co.casa_oracion_id, co.completado, co.completado_at, co.fecha_conversion, co.primer_contacto_fecha,
           (co.completado is not true and now() - co.fecha_conversion > interval '72 hours') as vencido,
           extract(epoch from (co.primer_contacto_fecha - co.fecha_conversion)) / 3600 as h_primer
      from public.consolidaciones co
     where co.fecha_conversion >= p_desde
  )
  select jsonb_build_object(
    'desde', p_desde,
    'total', count(*),
    'completados', count(*) filter (where completado),
    'abiertos', count(*) filter (where completado is not true),
    'vencidos', count(*) filter (where vencido),
    'con_primer_contacto', count(*) filter (where primer_contacto_fecha is not null),
    'primer_contacto_24h', count(*) filter (where h_primer <= 24),
    'horas_primer_contacto', round((avg(h_primer) filter (where h_primer >= 0))::numeric, 1),
    'completados_72h', count(*) filter (where completado and completado_at <= fecha_conversion + interval '72 hours'),
    'por_consolidador', coalesce((
      select jsonb_agg(t order by t.total desc, t.nombre)
        from (select x.consolidador_id, coalesce(btrim(p.nombre || ' ' || p.apellido), '') as nombre, count(*) as total,
                     count(*) filter (where x.h_primer <= 24) as contacto_24h, count(*) filter (where x.vencido) as vencidos
                from c x left join public.perfiles p on p.id = x.consolidador_id
               group by x.consolidador_id, p.nombre, p.apellido
               order by count(*) desc limit 10) t), '[]'::jsonb),
    'por_casa', coalesce((
      select jsonb_agg(t order by t.total desc, t.nombre)
        from (select x.casa_oracion_id, coalesce(ca.nombre, '') as nombre, count(*) as total, count(*) filter (where x.vencido) as vencidos
                from c x left join public.casas_oracion ca on ca.id = x.casa_oracion_id
               group by x.casa_oracion_id, ca.nombre
               order by count(*) desc limit 10) t), '[]'::jsonb)
  ) into r from c;
  return r;
end;
$$;
revoke all on function public.metricas_op72(timestamptz) from public, anon;
grant execute on function public.metricas_op72(timestamptz) to authenticated;

-- ===== migrations/20261105232000_completado_at_automatico.sql (sha256 878a58056c50) =====
-- La fecha de cierre de una consolidacion la fija la base, no quien la cierra. Antes la pantalla solo guardaba
-- completado = true y dejaba completado_at vacio, con lo que esos casos no contaban como completados dentro de las 72 horas.
create or replace function public.gestionar_consolidacion()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
DECLARE
  horas_transcurridas DECIMAL;
BEGIN
  -- Calcular fecha limite automaticamente al insertar
  IF TG_OP = 'INSERT' THEN
    NEW.fecha_limite := NEW.fecha_conversion + INTERVAL '72 hours';
  END IF;

  -- La fecha de cierre se fija al completar y se limpia si se reabre
  IF NEW.completado IS TRUE THEN
    IF NEW.completado_at IS NULL THEN NEW.completado_at := NOW(); END IF;
  ELSE
    NEW.completado_at := NULL;
  END IF;

  -- Actualizar estado de alerta si no esta completado
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

-- Los casos ya cerrados sin fecha: la mejor aproximacion es su ultima actualizacion
update public.consolidaciones set completado_at = updated_at where completado is true and completado_at is null;
