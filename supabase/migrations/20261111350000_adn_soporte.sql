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
