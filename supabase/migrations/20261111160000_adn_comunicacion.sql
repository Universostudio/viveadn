-- Comunicacion: envio de mensajes por correo o WhatsApp a un segmento de miembros, con historial y bajas.
-- Reversion: supabase/reversiones/20261111160000_adn_comunicacion.down.sql (probada por tests/adn_reversion.sh).
--
-- ESTO NO ENVIA NADA A NADIE. El unico proveedor es el "sumidero": registra cada mensaje personalizado en la base
-- y lo da por entregado, sin red, sin correo, sin SMS y sin WhatsApp. La restriccion `proveedor = 'sumidero'` lo
-- impide a nivel de la tabla: activar un proveedor real exige una migracion nueva, que solo puede aprobar el dueño.
--
-- El envio, el calculo de destinatarios y el registro ocurren en una sola funcion privilegiada (private), no en la web:
-- nadie escribe filas a mano en el historial, y no se envia a quien se dio de baja, a quien no tiene destino valido ni
-- dos veces a la misma direccion.

-- 1. Permisos nuevos y su semilla en los roles de sistema, tambien en las iglesias que ya existen
insert into public.permisos (clave, modulo, descripcion, sensible) values
  ('comunicacion.ver', 'comunicacion', 'Ver el historial de mensajes enviados', false),
  ('comunicacion.enviar', 'comunicacion', 'Enviar mensajes a los miembros', true)
on conflict (clave) do nothing;

create or replace function private.sembrar_comunicacion(p_iglesia uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  insert into public.rol_permisos (rol_id, permiso)
    select r.id, p.permiso
    from public.roles r
    cross join (values ('comunicacion.ver'), ('comunicacion.enviar')) as p(permiso)
    where r.iglesia_id = p_iglesia and r.clave in ('administrador', 'coadministrador')
  on conflict do nothing;
end $$;
revoke all on function private.sembrar_comunicacion(uuid) from public, anon, authenticated;
grant execute on function private.sembrar_comunicacion(uuid) to service_role;

create or replace function private.trg_sembrar_roles()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  perform private.sembrar_formacion(new.id);
  perform private.sembrar_comunicacion(new.id);
  return new;
end $$;
select private.sembrar_comunicacion(id) from public.iglesias;

-- 2. Tablas
create table public.adn_mensajes (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias (id) on delete cascade,
  clave uuid not null,
  canal text not null check (canal in ('email', 'whatsapp')),
  segmento text not null check (segmento in ('todos', 'nuevos', 'lideres', 'consolidacion')),
  asunto text check (asunto is null or char_length(btrim(asunto)) between 1 and 150),
  texto text not null check (char_length(texto) between 1 and 4096),
  proveedor text not null default 'sumidero' check (proveedor = 'sumidero'),
  estado text not null default 'enviado' check (estado in ('enviado', 'sin_destinatarios')),
  total integer not null check (total >= 0),
  enviados integer not null check (enviados >= 0),
  omitidos integer not null check (omitidos >= 0),
  creado_por uuid default auth.uid(),
  created_at timestamptz not null default now(),
  constraint adn_mensajes_iglesia_id_key unique (iglesia_id, id),
  constraint adn_mensajes_clave_key unique (iglesia_id, clave),
  check (enviados + omitidos = total),
  check (canal <> 'email' or asunto is not null)
);
create index adn_mensajes_iglesia_fecha_idx on public.adn_mensajes (iglesia_id, created_at desc);

create table public.adn_mensaje_destinatarios (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias (id) on delete cascade,
  mensaje_id uuid not null,
  miembro_id uuid not null,
  destino text,
  texto_final text,
  estado text not null check (estado in ('enviado', 'omitido')),
  motivo text check (motivo in ('sin_destino', 'baja', 'repetido')),
  referencia text,
  enviado_en timestamptz,
  constraint adn_destinatarios_mensaje_fk foreign key (iglesia_id, mensaje_id) references public.adn_mensajes (iglesia_id, id) on delete cascade,
  constraint adn_destinatarios_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade,
  check ((estado = 'enviado' and destino is not null and texto_final is not null and motivo is null)
      or (estado = 'omitido' and motivo is not null))
);
create index adn_destinatarios_mensaje_idx on public.adn_mensaje_destinatarios (iglesia_id, mensaje_id);
create index adn_destinatarios_miembro_idx on public.adn_mensaje_destinatarios (iglesia_id, miembro_id);

-- Quien pide no recibir mensajes por un canal. Se respeta siempre en el envio.
create table public.adn_comunicacion_bajas (
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  canal text not null check (canal in ('email', 'whatsapp')),
  created_at timestamptz not null default now(),
  primary key (miembro_id, canal),
  constraint adn_bajas_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade
);
create index adn_bajas_iglesia_idx on public.adn_comunicacion_bajas (iglesia_id, canal);

-- El historial solo lo escribe la funcion de envio: la web lo lee y las bajas las gestiona quien envia o edita miembros
grant select on public.adn_mensajes, public.adn_mensaje_destinatarios to authenticated;
grant select, insert, delete on public.adn_comunicacion_bajas to authenticated;
grant select, insert, update, delete on public.adn_mensajes, public.adn_mensaje_destinatarios, public.adn_comunicacion_bajas to service_role;
alter table public.adn_mensajes enable row level security;
alter table public.adn_mensaje_destinatarios enable row level security;
alter table public.adn_comunicacion_bajas enable row level security;

create policy adn_mensajes_ver on public.adn_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('comunicacion.ver')));
create policy adn_destinatarios_ver on public.adn_mensaje_destinatarios for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('comunicacion.ver')));
create policy adn_bajas_ver on public.adn_comunicacion_bajas for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and ((select private.tiene_permiso('comunicacion.ver')) or (select private.tiene_permiso('miembros.editar'))));
create policy adn_bajas_crear on public.adn_comunicacion_bajas for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id())
              and ((select private.tiene_permiso('comunicacion.enviar')) or (select private.tiene_permiso('miembros.editar'))));
create policy adn_bajas_borrar on public.adn_comunicacion_bajas for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and ((select private.tiene_permiso('comunicacion.enviar')) or (select private.tiene_permiso('miembros.editar'))));

-- 3. Calculo de destinatarios de un segmento. Solo la usan las funciones de abajo (no tiene EXECUTE para nadie).
--    Cada miembro activo sale una vez, con su destino o con el motivo por el que se omite. Una baja vale para la
--    persona y tambien para su direccion: si otro registro comparte el correo o el telefono de quien se dio de baja,
--    tampoco recibe nada en ese canal.
create or replace function private.adn_destinatarios(p_iglesia uuid, p_canal text, p_segmento text)
returns table (miembro_id uuid, nombre text, dia text, destino text, motivo text)
language sql stable security definer set search_path to '' as $$
  with dest as (
    select m.id, m.nombre, m.activo, m.created_at, m.nivel_compromiso, m.casa_oracion_id,
      case when p_canal = 'email'
             then case when lower(btrim(m.email)) ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(btrim(m.email)) <= 254 then lower(btrim(m.email)) end
           else case when public.adn_telefono_canonico(m.telefono) ~ '^\+?[0-9]{7,15}$' and public.adn_telefono_canonico(m.telefono) !~ '^\+?(.)\1+$'
                     then public.adn_telefono_canonico(m.telefono) end
      end as destino
    from public.miembros m where m.iglesia_id = p_iglesia
  ), de_baja as (
    select d.id, d.destino from dest d
    where exists (select 1 from public.adn_comunicacion_bajas x where x.iglesia_id = p_iglesia and x.miembro_id = d.id and x.canal = p_canal)
  ), base as (
    select d.id, d.nombre, nullif(btrim(coalesce(c.dia_reunion, '')), '') as dia, d.destino
    from dest d
    left join public.casas_oracion c on c.id = d.casa_oracion_id and c.iglesia_id = p_iglesia
    where d.activo
      and case p_segmento
            when 'todos' then true
            when 'nuevos' then d.created_at >= now() - interval '30 days'
            when 'lideres' then d.nivel_compromiso in ('lider', 'multiplicador')
            when 'consolidacion' then exists (select 1 from public.consolidaciones k where k.miembro_id = d.id and k.iglesia_id = p_iglesia and not k.completado)
            else false end
  ), previo as (
    select b.*, case when b.destino is null then 'sin_destino'
                     when exists (select 1 from de_baja x where x.id = b.id or x.destino = b.destino) then 'baja'
                end as motivo_a
    from base b
  ), numerado as (
    select p.*, case when p.motivo_a is null then row_number() over (partition by p.destino order by p.id) end as rn from previo p
  )
  select n.id, n.nombre, n.dia, n.destino, coalesce(n.motivo_a, case when n.rn > 1 then 'repetido' end) from numerado n
$$;
revoke all on function private.adn_destinatarios(uuid, text, text) from public, anon, authenticated, service_role;

-- 4. Vista previa: cuantas personas recibirian el mensaje y cuantas se omiten, sin crear nada
create or replace function private.adn_vista_previa_envio(p_canal text, p_segmento text)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id(); r jsonb;
begin
  if ig is null or not ((select private.tiene_permiso('comunicacion.enviar')) and (select private.tiene_permiso('miembros.ver'))) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_canal not in ('email', 'whatsapp') or p_segmento not in ('todos', 'nuevos', 'lideres', 'consolidacion') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  select jsonb_build_object('total', count(*), 'recibiran', count(*) filter (where motivo is null),
    'sin_destino', count(*) filter (where motivo = 'sin_destino'), 'baja', count(*) filter (where motivo = 'baja'), 'repetido', count(*) filter (where motivo = 'repetido'))
  into r from private.adn_destinatarios(ig, p_canal, p_segmento);
  return r;
end $$;

-- 5. Envio al sumidero. Valida, calcula destinatarios, personaliza y registra, todo en una transaccion.
--    Es idempotente por `clave`: repetir la peticion devuelve el mismo envio sin duplicarlo.
create or replace function private.adn_enviar_mensaje(p_clave uuid, p_canal text, p_segmento text, p_asunto text, p_texto text, p_dia text default '')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  nombre_ig text;
  texto text := btrim(coalesce(p_texto, ''));
  asunto text := nullif(btrim(coalesce(p_asunto, '')), '');
  existente public.adn_mensajes;
  id_msg uuid;
  n_total int; n_env int; n_sin int; n_baja int; n_rep int;
begin
  if ig is null or not ((select private.tiene_permiso('comunicacion.enviar')) and (select private.tiene_permiso('miembros.ver'))) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_clave is null or p_canal not in ('email', 'whatsapp') or p_segmento not in ('todos', 'nuevos', 'lideres', 'consolidacion') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if char_length(texto) not between 1 and 4096 then raise exception 'ADN_TEXTO_INVALIDO'; end if;
  if p_canal = 'email' and (asunto is null or char_length(asunto) > 150) then raise exception 'ADN_ASUNTO_INVALIDO'; end if;
  if p_canal <> 'email' then asunto := null; end if;

  -- Repetir la misma peticion devuelve el envio ya hecho
  select * into existente from public.adn_mensajes where iglesia_id = ig and clave = p_clave;
  if found then
    return jsonb_build_object('mensaje_id', existente.id, 'total', existente.total, 'enviados', existente.enviados, 'omitidos', existente.omitidos,
                              'proveedor', existente.proveedor, 'repetido', true);
  end if;
  -- Tope diario por iglesia, contra el abuso y los errores de pulsacion
  if (select count(*) from public.adn_mensajes where iglesia_id = ig and created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC') >= 20 then
    raise exception 'ADN_LIMITE_DIARIO';
  end if;
  select count(*) into n_total from private.adn_destinatarios(ig, p_canal, p_segmento);
  if n_total > 2000 then raise exception 'ADN_DEMASIADOS_DESTINATARIOS'; end if;
  select nombre into nombre_ig from public.iglesias where id = ig;

  insert into public.adn_mensajes (iglesia_id, clave, canal, segmento, asunto, texto, estado, total, enviados, omitidos)
  values (ig, p_clave, p_canal, p_segmento, asunto, texto, 'sin_destinatarios', 0, 0, 0)
  returning id into id_msg;

  -- Variables de la plantilla: {{nombre}}, {{iglesia}} y {{dia}} (el de su casa de oracion o, si no tiene, el que se pase)
  insert into public.adn_mensaje_destinatarios (iglesia_id, mensaje_id, miembro_id, destino, texto_final, estado, motivo, referencia, enviado_en)
  select ig, id_msg, d.miembro_id,
         case when d.motivo is null then d.destino end,
         case when d.motivo is null then replace(replace(replace(texto, '{{nombre}}', d.nombre), '{{iglesia}}', nombre_ig), '{{dia}}', coalesce(d.dia, nullif(btrim(coalesce(p_dia, '')), ''), '')) end,
         case when d.motivo is null then 'enviado' else 'omitido' end, d.motivo,
         case when d.motivo is null then 'sumidero:' || gen_random_uuid()::text end,
         case when d.motivo is null then now() end
  from private.adn_destinatarios(ig, p_canal, p_segmento) d;

  select count(*) filter (where estado = 'enviado'), count(*) filter (where motivo = 'sin_destino'), count(*) filter (where motivo = 'baja'), count(*) filter (where motivo = 'repetido')
    into n_env, n_sin, n_baja, n_rep
    from public.adn_mensaje_destinatarios where iglesia_id = ig and mensaje_id = id_msg;
  update public.adn_mensajes set total = n_env + n_sin + n_baja + n_rep, enviados = n_env, omitidos = n_sin + n_baja + n_rep,
         estado = case when n_env > 0 then 'enviado' else 'sin_destinatarios' end
   where id = id_msg;
  return jsonb_build_object('mensaje_id', id_msg, 'total', n_env + n_sin + n_baja + n_rep, 'enviados', n_env,
                            'omitidos', jsonb_build_object('sin_destino', n_sin, 'baja', n_baja, 'repetido', n_rep),
                            'proveedor', 'sumidero', 'repetido', false);
end $$;

revoke all on function private.adn_vista_previa_envio(text, text), private.adn_enviar_mensaje(uuid, text, text, text, text, text) from public, anon;
grant execute on function private.adn_vista_previa_envio(text, text), private.adn_enviar_mensaje(uuid, text, text, text, text, text) to authenticated;

create or replace function public.adn_vista_previa_envio(p_canal text, p_segmento text)
returns jsonb language sql set search_path to '' as $$ select private.adn_vista_previa_envio(p_canal, p_segmento) $$;
create or replace function public.adn_enviar_mensaje(p_clave uuid, p_canal text, p_segmento text, p_asunto text, p_texto text, p_dia text default '')
returns jsonb language sql set search_path to '' as $$ select private.adn_enviar_mensaje(p_clave, p_canal, p_segmento, p_asunto, p_texto, p_dia) $$;
revoke all on function public.adn_vista_previa_envio(text, text), public.adn_enviar_mensaje(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.adn_vista_previa_envio(text, text), public.adn_enviar_mensaje(uuid, text, text, text, text, text) to authenticated;
