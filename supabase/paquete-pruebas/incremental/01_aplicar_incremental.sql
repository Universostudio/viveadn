-- Vive ADN, incremental tras 20261111340000. Aplicar una vez, solo sobre un proyecto que ya tiene el paquete completo hasta esa migración. Detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261111350000_adn_soporte.sql (sha256 000cd3949bf1) =====
-- Soporte dentro de la plataforma, sin servicios externos de pago. Tres piezas independientes:
--  (a) Tickets: la iglesia (quien puede configurarla, iglesia.configurar) abre un ticket con asunto, texto y prioridad y sigue su conversación; la plataforma
--      lo ve, responde y cierra desde la función de borde (service_role). Una iglesia solo ve los suyos.
--  (b) Novedades de plataforma: registro de cambios publicado por la plataforma (versión, fecha, texto), que lee cualquier persona con sesión, con una marca
--      de «vistas» por persona para el aviso de «novedades».
--  (c) Avisos masivos dentro de la aplicación: la plataforma redacta un aviso (actualización, mantenimiento o alerta) y elige destinatarios (todas, por plan
--      o por estado). Al crearlo se reparte una entrega a cada iglesia destinataria; cada iglesia lo ve como banner descartable y queda registro de entrega,
--      lectura y descarte. El correo masivo NO se envía: solo se anota si se pidió y que el envío está apagado.
-- Todo con el prefijo adn_. Las tablas con iglesia_id caen con la iglesia al purgarla.
-- Reversión: supabase/reversiones/20261111350000_adn_soporte.down.sql (borra estas tablas y sus datos: es lo único que se pierde).
-- Escrito para poder repetirse sin error y sin reordenar permisos (if not exists, drop ... if exists, create or replace, revoke con todos los roles).

-- ---------------------------------------------------------------- (a) Tickets
create table if not exists public.adn_tickets (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  creado_por uuid not null default auth.uid(),
  asunto text not null check (length(btrim(asunto)) between 3 and 120),
  prioridad text not null default 'normal' check (prioridad in ('baja', 'normal', 'alta', 'urgente')),
  estado text not null default 'abierto' check (estado in ('abierto', 'respondido', 'cerrado')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cerrado_en timestamptz,
  constraint adn_tickets_cierre check ((estado = 'cerrado') = (cerrado_en is not null)),
  constraint adn_tickets_id_iglesia_uq unique (id, iglesia_id)
);
create index if not exists adn_tickets_iglesia_idx on public.adn_tickets (iglesia_id, created_at desc);
create index if not exists adn_tickets_estado_idx on public.adn_tickets (estado, updated_at desc);

create table if not exists public.adn_ticket_mensajes (
  id bigint generated always as identity primary key,
  ticket_id uuid not null,
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  -- Clave compuesta con la iglesia: un mensaje nunca puede apuntar al ticket de otra iglesia
  constraint adn_ticket_mensajes_ticket_fk foreign key (ticket_id, iglesia_id) references public.adn_tickets (id, iglesia_id) on delete cascade,
  autor_tipo text not null default 'iglesia' check (autor_tipo in ('iglesia', 'plataforma')),
  autor uuid default auth.uid(),
  texto text not null check (length(btrim(texto)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists adn_ticket_mensajes_ticket_idx on public.adn_ticket_mensajes (ticket_id, id);
create index if not exists adn_ticket_mensajes_iglesia_idx on public.adn_ticket_mensajes (iglesia_id);

alter table public.adn_tickets enable row level security;
alter table public.adn_ticket_mensajes enable row level security;

-- Cada mensaje hereda la iglesia de su ticket (con privilegios, para que el ticket de otra iglesia no se «vea» a medias y falle por no nulo)
create or replace function private.adn_mensaje_iglesia() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  select t.iglesia_id into new.iglesia_id from public.adn_tickets t where t.id = new.ticket_id;
  if new.iglesia_id is null then raise exception 'ADN_TICKET_INEXISTENTE' using errcode = 'foreign_key_violation'; end if;
  return new;
end $$;
revoke all on function private.adn_mensaje_iglesia() from public, anon, authenticated, service_role;
drop trigger if exists adn_ticket_mensajes_iglesia on public.adn_ticket_mensajes;
create trigger adn_ticket_mensajes_iglesia before insert on public.adn_ticket_mensajes for each row execute function private.adn_mensaje_iglesia();

-- Una conversación cerrada no admite mensajes, y un mensaje cambia el estado: la iglesia reabre (abierto), la plataforma responde (respondido)
create or replace function private.adn_mensaje_estado() returns trigger language plpgsql security definer set search_path to '' as $$
declare v_estado text;
begin
  select estado into v_estado from public.adn_tickets where id = new.ticket_id for update;
  if v_estado = 'cerrado' then raise exception 'ADN_TICKET_CERRADO' using errcode = 'check_violation'; end if;
  if (select count(*) from public.adn_ticket_mensajes m where m.ticket_id = new.ticket_id) > 200 then raise exception 'ADN_TICKET_LLENO' using errcode = 'check_violation'; end if;
  update public.adn_tickets set updated_at = now(),
    estado = case when new.autor_tipo = 'plataforma' then 'respondido' else 'abierto' end
   where id = new.ticket_id;
  return new;
end $$;
revoke all on function private.adn_mensaje_estado() from public, anon, authenticated, service_role;
drop trigger if exists adn_ticket_mensajes_estado on public.adn_ticket_mensajes;
create trigger adn_ticket_mensajes_estado after insert on public.adn_ticket_mensajes for each row execute function private.adn_mensaje_estado();

-- Como mucho diez tickets sin cerrar por iglesia
create or replace function private.adn_tickets_limite() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if (select count(*) from public.adn_tickets t where t.iglesia_id = new.iglesia_id and t.estado <> 'cerrado') >= 10 then
    raise exception 'ADN_DEMASIADOS_TICKETS' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_tickets_limite() from public, anon, authenticated, service_role;
drop trigger if exists adn_tickets_limite on public.adn_tickets;
create trigger adn_tickets_limite before insert on public.adn_tickets for each row execute function private.adn_tickets_limite();

-- La iglesia ve y escribe solo lo suyo y solo con iglesia.configurar. El estado, el cierre y las respuestas de la plataforma los pone el servidor.
revoke all on public.adn_tickets from public, anon, authenticated, service_role;
grant select on public.adn_tickets to authenticated;
grant insert (asunto, prioridad) on public.adn_tickets to authenticated;
grant all on public.adn_tickets to service_role;
revoke all on public.adn_ticket_mensajes from public, anon, authenticated, service_role;
grant select on public.adn_ticket_mensajes to authenticated;
grant insert (ticket_id, texto) on public.adn_ticket_mensajes to authenticated;
grant all on public.adn_ticket_mensajes to service_role;
revoke all on sequence public.adn_ticket_mensajes_id_seq from public, anon, authenticated, service_role;
grant usage, select on sequence public.adn_ticket_mensajes_id_seq to authenticated, service_role;

drop policy if exists adn_tickets_ver on public.adn_tickets;
create policy adn_tickets_ver on public.adn_tickets for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_tickets_crear on public.adn_tickets;
create policy adn_tickets_crear on public.adn_tickets for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and creado_por = (select auth.uid()) and estado = 'abierto' and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_ticket_mensajes_ver on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_ver on public.adn_ticket_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')));
drop policy if exists adn_ticket_mensajes_crear on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_crear on public.adn_ticket_mensajes for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and autor_tipo = 'iglesia' and autor = (select auth.uid()) and (select private.tiene_permiso('iglesia.configurar')));

-- Abrir un ticket con su primer mensaje de una vez. Con los permisos de quien llama (security invoker): si no puede, falla por la seguridad de filas.
create or replace function public.adn_ticket_crear(p_asunto text, p_prioridad text, p_texto text) returns uuid language plpgsql set search_path to '' as $$
declare v_id uuid;
begin
  insert into public.adn_tickets (asunto, prioridad) values (p_asunto, coalesce(p_prioridad, 'normal')) returning id into v_id;
  insert into public.adn_ticket_mensajes (ticket_id, texto) values (v_id, p_texto);
  return v_id;
end $$;
revoke all on function public.adn_ticket_crear(text, text, text) from public, anon, authenticated, service_role;
grant execute on function public.adn_ticket_crear(text, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------- (b) Novedades de plataforma
create table if not exists public.adn_novedades (
  id uuid primary key default gen_random_uuid(),
  version text not null check (length(btrim(version)) between 1 and 30),
  titulo text not null check (length(btrim(titulo)) between 3 and 120),
  texto text not null check (length(btrim(texto)) between 1 and 4000),
  publicada_en timestamptz not null default now(),
  publicada_por uuid,
  retirada_en timestamptz
);
create index if not exists adn_novedades_fecha_idx on public.adn_novedades (publicada_en desc);
alter table public.adn_novedades enable row level security;
revoke all on public.adn_novedades from public, anon, authenticated, service_role;
grant select on public.adn_novedades to authenticated;
grant all on public.adn_novedades to service_role;
drop policy if exists adn_novedades_ver on public.adn_novedades;
create policy adn_novedades_ver on public.adn_novedades for select to authenticated using (retirada_en is null);

-- Qué novedades ya vio cada persona: una fila por persona
create table if not exists public.adn_novedades_vistas (
  usuario uuid primary key default auth.uid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  vista_en timestamptz not null default now()
);
create index if not exists adn_novedades_vistas_iglesia_idx on public.adn_novedades_vistas (iglesia_id);
alter table public.adn_novedades_vistas enable row level security;
revoke all on public.adn_novedades_vistas from public, anon, authenticated, service_role;
grant select on public.adn_novedades_vistas to authenticated;
grant insert (vista_en) on public.adn_novedades_vistas to authenticated;
grant update (vista_en) on public.adn_novedades_vistas to authenticated;
grant all on public.adn_novedades_vistas to service_role;
drop policy if exists adn_novedades_vistas_ver on public.adn_novedades_vistas;
create policy adn_novedades_vistas_ver on public.adn_novedades_vistas for select to authenticated using (usuario = (select auth.uid()));
drop policy if exists adn_novedades_vistas_crear on public.adn_novedades_vistas;
create policy adn_novedades_vistas_crear on public.adn_novedades_vistas for insert to authenticated
  with check (usuario = (select auth.uid()) and iglesia_id = (select private.get_iglesia_id()));
drop policy if exists adn_novedades_vistas_cambiar on public.adn_novedades_vistas;
create policy adn_novedades_vistas_cambiar on public.adn_novedades_vistas for update to authenticated
  using (usuario = (select auth.uid())) with check (usuario = (select auth.uid()));

-- Marca las novedades como vistas ahora (con los permisos de quien llama)
create or replace function public.adn_novedades_marcar_vistas() returns void language sql set search_path to '' as $$
  insert into public.adn_novedades_vistas (vista_en) values (now())
  on conflict (usuario) do update set vista_en = excluded.vista_en
$$;
revoke all on function public.adn_novedades_marcar_vistas() from public, anon, authenticated, service_role;
grant execute on function public.adn_novedades_marcar_vistas() to authenticated, service_role;

-- ---------------------------------------------------------------- (c) Avisos masivos dentro de la aplicación
-- destino: {"todas": true} (las iglesias operativas) o {"planes": [...], "estados": [...]} (ambos opcionales; juntos, se piden los dos)
create or replace function private.adn_destino_valido(d jsonb) returns boolean language sql immutable set search_path to '' as $$
  select jsonb_typeof(d) = 'object'
     and not exists (select 1 from jsonb_object_keys(d) k where k not in ('todas', 'planes', 'estados'))
     and (not d ? 'todas' or jsonb_typeof(d -> 'todas') = 'boolean')
     and (not d ? 'planes' or (jsonb_typeof(d -> 'planes') = 'array' and jsonb_array_length(d -> 'planes') between 1 and 20 and not exists (select 1 from jsonb_array_elements(d -> 'planes') e where jsonb_typeof(e) <> 'string')))
     and (not d ? 'estados' or (jsonb_typeof(d -> 'estados') = 'array' and jsonb_array_length(d -> 'estados') between 1 and 5 and not exists (select 1 from jsonb_array_elements(d -> 'estados') e where jsonb_typeof(e) <> 'string' or (e #>> '{}') not in ('onboarding', 'prueba', 'activa', 'receso', 'suspendida'))))
     and (d ? 'todas' or d ? 'planes' or d ? 'estados')
$$;
revoke all on function private.adn_destino_valido(jsonb) from public, anon, authenticated, service_role;
grant execute on function private.adn_destino_valido(jsonb) to service_role;

create table if not exists public.adn_avisos (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('actualizacion', 'mantenimiento', 'alerta')),
  titulo text not null check (length(btrim(titulo)) between 3 and 120),
  texto text not null check (length(btrim(texto)) between 1 and 2000),
  destino jsonb not null default '{"todas": true}'::jsonb,
  incluir_demo boolean not null default false,
  desde timestamptz not null default now(),
  hasta timestamptz,
  creado_por uuid,
  created_at timestamptz not null default now(),
  retirado_en timestamptz,
  por_correo boolean not null default false,
  correo_estado text not null default 'no_pedido' check (correo_estado in ('no_pedido', 'apagado', 'pendiente')),
  constraint adn_avisos_destino check (private.adn_destino_valido(destino)),
  constraint adn_avisos_vigencia check (hasta is null or hasta > desde),
  constraint adn_avisos_correo check ((por_correo = false and correo_estado = 'no_pedido') or (por_correo and correo_estado <> 'no_pedido'))
);
create table if not exists public.adn_avisos_entregas (
  aviso_id uuid not null references public.adn_avisos(id) on delete cascade,
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  entregado_en timestamptz not null default now(),
  leido_en timestamptz,
  descartado_en timestamptz,
  primary key (aviso_id, iglesia_id)
);
create index if not exists adn_avisos_entregas_iglesia_idx on public.adn_avisos_entregas (iglesia_id);
alter table public.adn_avisos enable row level security;
alter table public.adn_avisos_entregas enable row level security;
revoke all on public.adn_avisos from public, anon, authenticated, service_role;
grant select on public.adn_avisos to authenticated;
grant all on public.adn_avisos to service_role;
revoke all on public.adn_avisos_entregas from public, anon, authenticated, service_role;
grant select on public.adn_avisos_entregas to authenticated;
grant update (leido_en, descartado_en) on public.adn_avisos_entregas to authenticated;
grant all on public.adn_avisos_entregas to service_role;

-- Cada iglesia lee y marca solo sus entregas; solo ve los avisos que le llegaron, vigentes y no retirados
drop policy if exists adn_avisos_entregas_ver on public.adn_avisos_entregas;
create policy adn_avisos_entregas_ver on public.adn_avisos_entregas for select to authenticated using (iglesia_id = (select private.get_iglesia_id()));
drop policy if exists adn_avisos_entregas_marcar on public.adn_avisos_entregas;
create policy adn_avisos_entregas_marcar on public.adn_avisos_entregas for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id())) with check (iglesia_id = (select private.get_iglesia_id()));
drop policy if exists adn_avisos_ver on public.adn_avisos;
create policy adn_avisos_ver on public.adn_avisos for select to authenticated
  using (retirado_en is null and desde <= now() and (hasta is null or hasta > now())
         and exists (select 1 from public.adn_avisos_entregas e where e.aviso_id = adn_avisos.id and e.iglesia_id = (select private.get_iglesia_id())));

-- Reparte un aviso a las iglesias destinatarias. Solo el servidor. Devuelve cuántas. Las demostraciones solo entran si el aviso lo pide;
-- las que están en baja (borrado suave) nunca. «todas» son las iglesias operativas (en alta, prueba y activa).
create or replace function public.adn_aviso_entregar(p_aviso uuid) returns integer language plpgsql set search_path to '' as $$
declare a record; n integer;
begin
  select * into a from public.adn_avisos where id = p_aviso;
  if not found then raise exception 'ADN_AVISO_INEXISTENTE'; end if;
  insert into public.adn_avisos_entregas (aviso_id, iglesia_id)
  select a.id, i.id from public.iglesias i
   where i.adn_borrada_en is null
     and (a.incluir_demo or not i.es_demo)
     and case
           when coalesce((a.destino ->> 'todas')::boolean, false) then i.etapa in ('onboarding', 'prueba', 'activa')
           else (not a.destino ? 'planes' or i.plan in (select jsonb_array_elements_text(a.destino -> 'planes')))
            and (case when a.destino ? 'estados' then i.etapa in (select jsonb_array_elements_text(a.destino -> 'estados')) else i.etapa in ('onboarding', 'prueba', 'activa') end)
         end
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.adn_aviso_entregar(uuid) from public, anon, authenticated, service_role;
grant execute on function public.adn_aviso_entregar(uuid) to service_role;

-- ---------------------------------------------------------------- Exportación
-- Las entregas de avisos son un registro operativo de la plataforma sobre avisos que son globales (no llevan iglesia_id y no se exportan): sin el aviso no se
-- pueden cargar, así que quedan fuera de la exportación de la iglesia, igual que los enlaces de baja y las confirmaciones. Los tickets, sus mensajes y la marca de
-- novedades vistas sí salen. Es la misma función de siempre con una exclusión más.
create or replace function public.adn_tablas_exportables()
returns table (nombre text, filtro text) language sql stable set search_path to '' as $$
  select 'iglesias'::text, 'id = $1'::text
  union all
  select c.relname::text, 'iglesia_id = $1'
  from pg_class c
  where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
    -- La auditoria de la plataforma son acciones internas y puede llevar notas de administracion: no sale en la exportacion de la iglesia
    and c.relname not in ('plataforma_auditoria', 'adn_bajas_enlaces', 'adn_confirmaciones', 'adn_avisos_entregas')
    -- (adn_bajas_enlaces y adn_confirmaciones: secretos efimeros de un solo uso, sin valor fuera de la base; adn_avisos_entregas: ver arriba)
    and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
  union all
  select 'rol_permisos', 'rol_id in (select id from public.roles where iglesia_id = $1)'
$$;

-- ===== migrations/20261111360000_adn_precios_plan.sql (sha256 06083fc9aa73) =====
-- Precios por plan (modo de prueba). Solo añade tres columnas opcionales a planes: precio mensual y anual en céntimos y la moneda.
-- Quedan VACÍAS: los valores los fija quien opera la plataforma cuando estén validados (hoy son una propuesta pendiente), y mientras estén vacías el panel
-- lo dice en vez de inventar un precio. No cobra nada ni conecta ninguna pasarela. Reversión: reversiones/20261111360000_adn_precios_plan.down.sql.
alter table public.planes add column if not exists precio_mensual_centimos integer;
alter table public.planes add column if not exists precio_anual_centimos integer;
alter table public.planes add column if not exists moneda text;
alter table public.planes drop constraint if exists adn_planes_precio_coherente;
alter table public.planes add constraint adn_planes_precio_coherente check (
  (precio_mensual_centimos is null or precio_mensual_centimos between 0 and 10000000)
  and (precio_anual_centimos is null or precio_anual_centimos between 0 and 100000000)
  and (moneda is null or moneda ~ '^[A-Z]{3}$')
  and ((precio_mensual_centimos is null and precio_anual_centimos is null) or moneda is not null));

-- ===== migrations/20261111370000_adn_prueba_vencida_lectura.sql (sha256 b86ac835b780) =====
-- Prueba vencida: el núcleo sigue disponible en SOLO LECTURA. Antes, una prueba vencida cortaba todos los módulos y la iglesia no podía ni ver sus datos.
-- Regla: con la prueba vencida (etapa 'prueba' y prueba_hasta pasada), tiene_permiso concede únicamente los permisos de LECTURA (ver, ver_asignados, ver_casa,
-- ver_propia y exportar) de los módulos del NÚCLEO que el plan incluye. Nada de escribir, nada de los módulos incluidos ni de pago. tiene_modulo no cambia.
-- Quien es propietario conserva además la descarga de su copia (función datos-iglesia). Reversión: reversiones/20261111370000_adn_prueba_vencida_lectura.down.sql.
create or replace function private.adn_nucleo_en_lectura(p_modulo text, p_permiso text)
returns boolean language sql stable security definer set search_path to '' as $$
  select p_permiso ~ '\.(ver|ver_asignados|ver_casa|ver_propia|exportar)$'
    and exists (
      select 1 from public.iglesias i join public.modulos m on m.clave = p_modulo and m.tipo = 'nucleo'
      where i.id = (select private.get_iglesia_id()) and i.activa
        and i.etapa = 'prueba' and i.prueba_hasta is not null and i.prueba_hasta <= now()
        and exists (select 1 from public.plan_modulos pm where pm.plan = i.plan and pm.modulo = p_modulo)
    )
$$;
revoke all on function private.adn_nucleo_en_lectura(text, text) from public, anon, authenticated, service_role;
grant execute on function private.adn_nucleo_en_lectura(text, text) to authenticated, service_role;

create or replace function private.tiene_permiso(p_permiso text)
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$
  select exists (
    select 1 from public.permisos pe
    where pe.clave = p_permiso and (private.tiene_modulo(pe.modulo) or private.adn_nucleo_en_lectura(pe.modulo, pe.clave))
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

-- ===== migrations/20261111380000_adn_purga_tarea_estado.sql (sha256 73fd429e1604) =====
-- Estado de la tarea programada de purga, para mostrarlo en «Sistema». Lee pg_cron si existe y, si no, dice «no disponible» (la base local no tiene la extensión).
-- Solo devuelve el nombre de la tarea, su horario, si está activa y cómo terminó su última pasada: nunca la orden completa, que lleva cabeceras con secretos.
-- Función de definidor en `private` y envoltorio de invocador en `public`, ejecutable solo por el servidor. Reversión: reversiones/20261111380000_adn_purga_tarea_estado.down.sql.
create or replace function private.adn_purga_tarea_estado() returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare r jsonb;
begin
  if to_regclass('cron.job') is null or to_regclass('cron.job_run_details') is null then
    return jsonb_build_object('disponible', false, 'tareas', '[]'::jsonb);
  end if;
  execute $q$
    select jsonb_build_object('disponible', true, 'tareas', coalesce(jsonb_agg(jsonb_build_object(
      'nombre', j.jobname, 'programacion', j.schedule, 'activa', j.active,
      'ultima_pasada', u.start_time, 'ultimo_resultado', u.status) order by j.jobname), '[]'::jsonb))
    from cron.job j
    left join lateral (select d.start_time, d.status from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1) u on true
    where j.jobname like 'adn-%'
  $q$ into r;
  return r;
end $$;
revoke all on function private.adn_purga_tarea_estado() from public, anon, authenticated, service_role;
grant execute on function private.adn_purga_tarea_estado() to service_role;

create or replace function public.adn_purga_tarea_estado() returns jsonb language sql stable set search_path to '' as $$
  select private.adn_purga_tarea_estado()
$$;
revoke all on function public.adn_purga_tarea_estado() from public, anon, authenticated, service_role;
grant execute on function public.adn_purga_tarea_estado() to service_role;

-- ===== migrations/20261111390000_adn_soporte_prueba_vencida.sql (sha256 2e391cdde5de) =====
-- Soporte con la prueba vencida: una iglesia en solo lectura (prueba vencida) debe poder pedir ayuda y leer las respuestas, justo cuando más lo necesita.
-- Antes, los tickets exigían tiene_permiso('iglesia.configurar') y con la prueba vencida ese permiso se cierra. Ahora basta ese permiso O ser propietario activo de una
-- iglesia que sigue activa (en receso o suspendida no hay acceso). Solo cambian las cuatro políticas de tickets y mensajes. Reversión: reversiones/20261111390000_adn_soporte_prueba_vencida.down.sql.
create or replace function private.adn_puede_pedir_ayuda() returns boolean language sql stable security definer set search_path to '' as $$
  select private.tiene_permiso('iglesia.configurar')
    or exists (
      select 1 from public.perfiles pf
      join public.roles r on r.iglesia_id = pf.iglesia_id and r.clave = pf.rol
      join public.iglesias i on i.id = pf.iglesia_id
      where pf.id = (select auth.uid()) and pf.activo and r.es_propietario and i.activa and i.adn_borrada_en is null
    )
$$;
revoke all on function private.adn_puede_pedir_ayuda() from public, anon, authenticated, service_role;
grant execute on function private.adn_puede_pedir_ayuda() to authenticated, service_role;

drop policy if exists adn_tickets_ver on public.adn_tickets;
create policy adn_tickets_ver on public.adn_tickets for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_tickets_crear on public.adn_tickets;
create policy adn_tickets_crear on public.adn_tickets for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and creado_por = (select auth.uid()) and estado = 'abierto' and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_ticket_mensajes_ver on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_ver on public.adn_ticket_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
drop policy if exists adn_ticket_mensajes_crear on public.adn_ticket_mensajes;
create policy adn_ticket_mensajes_crear on public.adn_ticket_mensajes for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and autor_tipo = 'iglesia' and autor = (select auth.uid()) and (select private.adn_puede_pedir_ayuda()));

-- ===== migrations/20261111400000_adn_agregados_plataforma.sql (sha256 4bbc3337c1c2) =====
-- Panel Maestro: agregados en SQL. La función de borde 'plataforma' leía filas enteras para contarlas (iglesias para la facturación, tickets y
-- entregas para el soporte, entregas para las estadísticas de avisos). El límite de filas por respuesta del servicio alojado (por defecto en
-- torno a 1.000, sin verificar aquí) las cortaba en silencio. Estas tres funciones devuelven solo números, ya agrupados:
--  * adn_plataforma_facturacion(): iglesias por plan, etapa, demo y borrado suave (sin nombres ni identificadores).
--  * adn_soporte_resumen(p_incluir_demo): cifras de tickets, avisos vigentes, entregas y novedades; con p_incluir_demo = false no cuentan
--    los tickets ni las entregas de iglesias de demostración (el mismo interruptor que el resto del panel).
--  * adn_avisos_estadisticas(p_ids): entregas, lecturas y descartes de cada aviso pedido.
-- Solo las ejecuta el servidor (la función 'plataforma', que antes comprueba que quien llama es administrador de plataforma).
-- Reversión: supabase/reversiones/20261111400000_adn_agregados_plataforma.down.sql
create or replace function public.adn_plataforma_facturacion()
returns table (plan text, activa boolean, etapa text, es_demo boolean, borrada boolean, n bigint) language sql stable set search_path to '' as $$
  select i.plan, i.activa, i.etapa, i.es_demo, (i.adn_borrada_en is not null), count(*)
  from public.iglesias i
  group by i.plan, i.activa, i.etapa, i.es_demo, (i.adn_borrada_en is not null)
$$;

create or replace function public.adn_soporte_resumen(p_incluir_demo boolean default true)
returns table (tickets_abiertos bigint, tickets_respondidos bigint, tickets_cerrados bigint, tickets_urgentes bigint,
               avisos_vigentes bigint, entregas bigint, leidos bigint, descartados bigint, novedades_total bigint, ultima_version text, ultima_publicada timestamptz)
language sql stable set search_path to '' as $$
  with t as (
    select x.estado, x.prioridad from public.adn_tickets x
    where coalesce(p_incluir_demo, true) or not exists (select 1 from public.iglesias i where i.id = x.iglesia_id and i.es_demo)
  ), v as (
    select a.id from public.adn_avisos a
    where a.retirado_en is null and a.desde <= now() and (a.hasta is null or a.hasta > now())
  ), e as (
    select x.leido_en, x.descartado_en from public.adn_avisos_entregas x
    where x.aviso_id in (select id from v)
      and (coalesce(p_incluir_demo, true) or not exists (select 1 from public.iglesias i where i.id = x.iglesia_id and i.es_demo))
  ), n as (
    select count(*) as total, (array_agg(version order by publicada_en desc))[1] as version, max(publicada_en) as publicada
    from public.adn_novedades where retirada_en is null
  )
  select (select count(*) from t where estado = 'abierto'), (select count(*) from t where estado = 'respondido'), (select count(*) from t where estado = 'cerrado'),
         (select count(*) from t where estado <> 'cerrado' and prioridad = 'urgente'),
         (select count(*) from v), (select count(*) from e), (select count(*) from e where leido_en is not null), (select count(*) from e where descartado_en is not null),
         n.total, n.version, n.publicada
  from n
$$;

create or replace function public.adn_avisos_estadisticas(p_ids uuid[])
returns table (aviso_id uuid, entregas bigint, leidos bigint, descartados bigint) language sql stable set search_path to '' as $$
  select e.aviso_id, count(*), count(e.leido_en), count(e.descartado_en)
  from public.adn_avisos_entregas e
  where e.aviso_id = any (coalesce(p_ids, '{}'::uuid[]))
  group by e.aviso_id
$$;

revoke all on function public.adn_plataforma_facturacion(), public.adn_soporte_resumen(boolean), public.adn_avisos_estadisticas(uuid[]) from public, anon, authenticated;
grant execute on function public.adn_plataforma_facturacion(), public.adn_soporte_resumen(boolean), public.adn_avisos_estadisticas(uuid[]) to service_role;
