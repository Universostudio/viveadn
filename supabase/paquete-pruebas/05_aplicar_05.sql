-- Vive ADN, paquete de aplicación 05 de 07. Aplicar en orden y detenerse en el primer error.
set search_path = public, extensions;

-- ===== migrations/20261111150000_adn_informes.sql (sha256 dd00ad653f32) =====
-- Datos de los informes en PDF y Excel (miembros, asistencia, crecimiento).
-- Reversion: supabase/reversiones/20261111150000_adn_informes.down.sql. Solo funciones de lectura.
--
-- Se ejecutan con los permisos de quien las llama: la seguridad por filas decide que filas cuentan, de modo que un
-- informe nunca incluye datos que esa persona no podria ver en pantalla. Ademas exigen el permiso del informe:
-- `miembros.exportar` (dato sensible) para el de miembros y `reportes.ver` para asistencia y crecimiento.

-- Crecimiento mes a mes de los ultimos p_meses meses (1 a 60), incluido el actual
create or replace function public.adn_informe_crecimiento(p_meses integer default 12)
returns table (mes date, nuevos_miembros bigint, miembros_acumulados bigint, conversiones bigint, bautizos bigint,
               consolidaciones_iniciadas bigint, consolidaciones_completadas bigint)
language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
begin
  if not (select private.tiene_permiso('reportes.ver')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_meses is null or p_meses < 1 or p_meses > 60 then raise exception 'ADN_PERIODO_INVALIDO'; end if;
  return query
  with meses as (
    select g::date as m
    from generate_series(date_trunc('month', now()) - make_interval(months => p_meses - 1), date_trunc('month', now()), interval '1 month') g
  )
  select ms.m,
    (select count(*) from public.miembros x where x.created_at >= ms.m and x.created_at < ms.m + interval '1 month'),
    (select count(*) from public.miembros x where x.created_at < ms.m + interval '1 month'),
    (select count(*) from public.miembros x where x.fecha_conversion >= ms.m and x.fecha_conversion < (ms.m + interval '1 month')::date),
    (select count(*) from public.miembros x where x.fecha_bautismo >= ms.m and x.fecha_bautismo < (ms.m + interval '1 month')::date),
    (select count(*) from public.consolidaciones c where c.fecha_conversion >= ms.m and c.fecha_conversion < ms.m + interval '1 month'),
    (select count(*) from public.consolidaciones c where c.completado_at >= ms.m and c.completado_at < ms.m + interval '1 month')
  from meses ms
  order by ms.m;
end $$;

-- Asistencia entre dos fechas (como maximo 366 dias): reuniones de casa por semana y por casa, y eventos
create or replace function public.adn_informe_asistencia(p_desde date, p_hasta date)
returns jsonb language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
declare
  semanal jsonb; por_casa jsonb; eventos jsonb;
  tot_casas record; tot_eventos record;
begin
  if not (select private.tiene_permiso('reportes.ver')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta or p_hasta - p_desde > 366 then raise exception 'ADN_PERIODO_INVALIDO'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'registros', s.registros, 'presentes', s.presentes) order by s.semana), '[]'::jsonb)
    into semanal
    from (select date_trunc('week', a.fecha)::date as semana, count(*) as registros, count(*) filter (where a.presente) as presentes
          from public.asistencias a where a.fecha between p_desde and p_hasta group by 1) s;

  select coalesce(jsonb_agg(jsonb_build_object('casa', c.nombre, 'registros', c.registros, 'presentes', c.presentes, 'personas', c.personas)
                            order by c.presentes desc, c.nombre), '[]'::jsonb)
    into por_casa
    from (select coalesce(h.nombre, h.codigo_zona, '') as nombre, count(*) as registros, count(*) filter (where a.presente) as presentes,
                 count(distinct a.miembro_id) filter (where a.presente) as personas
          from public.asistencias a join public.casas_oracion h on h.id = a.casa_oracion_id
          where a.fecha between p_desde and p_hasta group by h.id, h.nombre, h.codigo_zona) c;

  select coalesce(jsonb_agg(jsonb_build_object('titulo', e.titulo, 'tipo', e.tipo, 'inicia_en', e.inicia_en, 'registros', e.registros, 'presentes', e.presentes)
                            order by e.inicia_en), '[]'::jsonb)
    into eventos
    from (select ev.titulo, ev.tipo, ev.inicia_en, count(*) as registros, count(*) filter (where ae.presente) as presentes
          from public.asistencia_evento ae join public.eventos ev on ev.id = ae.evento_id
          where ev.inicia_en >= p_desde and ev.inicia_en < p_hasta + 1 group by ev.id, ev.titulo, ev.tipo, ev.inicia_en) e;

  select count(*) as registros, count(*) filter (where a.presente) as presentes into tot_casas
    from public.asistencias a where a.fecha between p_desde and p_hasta;
  select count(*) as registros, count(*) filter (where ae.presente) as presentes into tot_eventos
    from public.asistencia_evento ae join public.eventos ev on ev.id = ae.evento_id where ev.inicia_en >= p_desde and ev.inicia_en < p_hasta + 1;

  return jsonb_build_object(
    'desde', p_desde, 'hasta', p_hasta,
    'casas', jsonb_build_object('registros', tot_casas.registros, 'presentes', tot_casas.presentes, 'semanal', semanal, 'por_casa', por_casa),
    'eventos', jsonb_build_object('registros', tot_eventos.registros, 'presentes', tot_eventos.presentes, 'lista', eventos));
end $$;

-- Cifras del conjunto de miembros
create or replace function public.adn_informe_miembros_resumen()
returns jsonb language plpgsql stable set search_path to '' as $$
declare r jsonb;
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  select jsonb_build_object(
    'total', count(*), 'activos', count(*) filter (where activo), 'inactivos', count(*) filter (where not activo),
    'bautizados', count(*) filter (where bautizado), 'con_correo', count(*) filter (where email is not null),
    'con_telefono', count(*) filter (where telefono is not null), 'sin_casa', count(*) filter (where casa_oracion_id is null),
    'por_nivel', coalesce((select jsonb_object_agg(x.nivel, x.n) from (select nivel_compromiso as nivel, count(*) as n from public.miembros group by 1) x), '{}'::jsonb))
  into r
  from public.miembros;
  return r;
end $$;

-- Lista de miembros para el informe, ordenada por codigo. Se pagina con .range() desde la web
create or replace function public.adn_informe_miembros()
returns table (crm_id text, nombre text, apellido text, email text, telefono text, fecha_nacimiento date, genero text, casa text,
               nivel_compromiso text, bautizado boolean, fecha_conversion date, activo boolean, registrado date)
language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  return query
  select m.crm_id, m.nombre, m.apellido, m.email, m.telefono, m.fecha_nacimiento, m.genero, h.nombre,
         m.nivel_compromiso, coalesce(m.bautizado, false), m.fecha_conversion, coalesce(m.activo, false), m.created_at::date
  from public.miembros m left join public.casas_oracion h on h.id = m.casa_oracion_id and h.iglesia_id = m.iglesia_id
  order by m.crm_id;
end $$;

revoke all on function public.adn_informe_crecimiento(integer), public.adn_informe_asistencia(date, date),
  public.adn_informe_miembros_resumen(), public.adn_informe_miembros() from public, anon;
grant execute on function public.adn_informe_crecimiento(integer), public.adn_informe_asistencia(date, date),
  public.adn_informe_miembros_resumen(), public.adn_informe_miembros() to authenticated, service_role;

-- ===== migrations/20261111160000_adn_comunicacion.sql (sha256 73b8fb6040cc) =====
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

-- ===== migrations/20261111170000_adn_panel_inicio.sql (sha256 0d6529e35f80) =====
-- Datos del panel de inicio, en una sola llamada. Reversion: supabase/reversiones/20261111170000_adn_panel_inicio.down.sql.
-- Solo lectura y con los permisos de quien llama: la seguridad por filas decide que cuenta, de modo que cada bloque
-- refleja lo que esa persona puede ver (un lider de casa ve a los miembros que le corresponden, no a toda la iglesia).
-- La web decide ademas que bloques mostrar segun los permisos del rol.
-- p_hoy fija el dia de referencia de las semanas y los cumpleaños; sirve para las pruebas (el 29 de febrero, el cambio de año).
create or replace function public.adn_panel_inicio(p_hoy date default null)
returns jsonb language plpgsql stable set search_path to '' set timezone to 'UTC' as $$
declare
  hoy date := coalesce(p_hoy, (now() at time zone 'UTC')::date);
  lunes date := date_trunc('week', coalesce(p_hoy, (now() at time zone 'UTC')::date)::timestamp)::date;
begin
  return jsonb_build_object(
    'miembros', (select jsonb_build_object(
        'activos', count(*) filter (where activo),
        'nuevos_30d', count(*) filter (where created_at >= now() - interval '30 days'),
        'nuevos_30d_previos', count(*) filter (where created_at >= now() - interval '60 days' and created_at < now() - interval '30 days'),
        'sin_casa', count(*) filter (where activo and casa_oracion_id is null),
        'bautizados', count(*) filter (where activo and bautizado))
      from public.miembros),
    'asistencia', jsonb_build_object(
      'semana_actual', (select jsonb_build_object('semana', lunes, 'registros', count(*), 'presentes', count(*) filter (where presente))
                        from public.asistencias where fecha >= lunes and fecha < lunes + 7),
      'semana_anterior', (select jsonb_build_object('semana', lunes - 7, 'registros', count(*), 'presentes', count(*) filter (where presente))
                          from public.asistencias where fecha >= lunes - 7 and fecha < lunes),
      'serie', (select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'presentes', s.presentes) order by s.semana), '[]'::jsonb)
                from (select w::date as semana,
                             (select count(*) from public.asistencias a where a.presente and a.fecha >= w::date and a.fecha < w::date + 7) as presentes
                      from generate_series((lunes - 49)::timestamp, lunes::timestamp, interval '7 days') w) s)),
    'eventos_proximos', (select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'tipo', e.tipo, 'inicia_en', e.inicia_en, 'lugar', e.lugar) order by e.inicia_en), '[]'::jsonb)
                         from (select id, titulo, tipo, inicia_en, lugar from public.eventos where not cancelado and inicia_en >= now() order by inicia_en limit 5) e),
    -- Cumpleaños de los proximos 14 dias. El 29 de febrero se celebra el ultimo dia de febrero en los años no bisiestos.
    'cumpleanos', (select coalesce(jsonb_agg(jsonb_build_object('nombre', c.nombre, 'apellido', c.apellido, 'fecha', c.prox, 'en_dias', c.prox - hoy) order by c.prox, c.nombre), '[]'::jsonb)
                   from (select m.nombre, m.apellido, f.prox
                         from public.miembros m
                         cross join lateral (
                           select min(x.d) as prox from (
                             select (make_date(y, extract(month from m.fecha_nacimiento)::int, 1)
                                     + (least(extract(day from m.fecha_nacimiento)::int,
                                              extract(day from (make_date(y, extract(month from m.fecha_nacimiento)::int, 1) + interval '1 month - 1 day'))::int) - 1))::date as d
                             from unnest(array[extract(year from hoy)::int, extract(year from hoy)::int + 1]) as t(y)
                           ) x where x.d >= hoy
                         ) f
                         where m.activo and m.fecha_nacimiento is not null and f.prox <= hoy + 14
                         order by f.prox, m.nombre limit 10) c),
    'formacion', jsonb_build_object(
      'en_curso', (select count(*) from public.inscripciones_formacion where estado = 'en_curso'),
      'completadas_mes', (select count(*) from public.inscripciones_formacion where completado_en >= date_trunc('month', now())),
      'certificados_mes', (select count(*) from public.certificados where emitido_en >= date_trunc('month', now()) and revocado_en is null)),
    'comunicacion', (select jsonb_build_object('mensajes_30d', count(*), 'enviados_30d', coalesce(sum(enviados), 0))
                     from public.adn_mensajes where created_at >= now() - interval '30 days'),
    'crecimiento', (select coalesce(jsonb_agg(jsonb_build_object('mes', g::date, 'nuevos',
                              (select count(*) from public.miembros where created_at >= g and created_at < g + interval '1 month')) order by g), '[]'::jsonb)
                    from generate_series(date_trunc('month', now()) - interval '5 months', date_trunc('month', now()), interval '1 month') g)
  );
end $$;
revoke all on function public.adn_panel_inicio(date) from public, anon;
grant execute on function public.adn_panel_inicio(date) to authenticated, service_role;

-- ===== migrations/20261111180000_adn_descargas_informe.sql (sha256 d8e23c6f0d26) =====
-- Registro de descargas del informe de miembros: quien, cuando, que informe y cuantas filas. Nunca guarda contenido.
-- Solo altas: ninguna persona autenticada puede insertar, modificar ni borrar; el registro lo escribe el servidor al
-- servir el informe, de modo que no depende de que el navegador lo avise.
-- Reversion: supabase/reversiones/20261111180000_adn_descargas_informe.down.sql

create table public.adn_informe_descargas (
  id bigint generated always as identity primary key,
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  usuario_id uuid not null,
  informe text not null check (informe in ('miembros', 'asistencia', 'crecimiento')),
  filas integer not null check (filas >= 0),
  created_at timestamptz not null default now()
);
create index adn_informe_descargas_iglesia_idx on public.adn_informe_descargas (iglesia_id, created_at desc);

alter table public.adn_informe_descargas enable row level security;
-- Lo lee quien gestiona usuarios en su propia iglesia. No hay politicas de escritura.
create policy adn_informe_descargas_ver on public.adn_informe_descargas for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('usuarios.gestionar')));
revoke all on public.adn_informe_descargas from public, anon, authenticated;
grant select on public.adn_informe_descargas to authenticated;
grant all on public.adn_informe_descargas to service_role;

-- Un registro es inmutable: no se modifica nunca (el borrado queda para la purga de la iglesia, que corre como servicio)
create or replace function private.trg_descarga_inmutable() returns trigger language plpgsql set search_path to '' as $$
begin
  raise exception 'ADN_REGISTRO_INMUTABLE';
end $$;
create trigger adn_informe_descargas_inmutable before update on public.adn_informe_descargas
  for each row execute function private.trg_descarga_inmutable();

-- El informe pagina con .range(): la funcion se ejecuta una vez por pagina. Para que una descarga deje una sola fila,
-- una descarga del mismo informe por la misma persona dentro de dos minutos no se registra otra vez.
create or replace function private.adn_registrar_descarga(p_informe text, p_filas integer)
returns void language plpgsql security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id(); u uuid := (select auth.uid());
begin
  if ig is null or u is null or p_informe not in ('miembros', 'asistencia', 'crecimiento') or p_filas is null or p_filas < 0 then return; end if;
  if exists (select 1 from public.adn_informe_descargas d
             where d.iglesia_id = ig and d.usuario_id = u and d.informe = p_informe and d.created_at > now() - interval '2 minutes') then
    return;
  end if;
  insert into public.adn_informe_descargas (iglesia_id, usuario_id, informe, filas) values (ig, u, p_informe, p_filas);
end $$;
revoke execute on function private.adn_registrar_descarga(text, integer) from public, anon;
grant execute on function private.adn_registrar_descarga(text, integer) to authenticated, service_role;

-- El informe de miembros pasa de stable a volatile porque ahora registra la descarga
create or replace function public.adn_informe_miembros()
returns table (crm_id text, nombre text, apellido text, email text, telefono text, fecha_nacimiento date, genero text, casa text,
               nivel_compromiso text, bautizado boolean, fecha_conversion date, activo boolean, registrado date)
language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare n integer;
begin
  if not (select private.tiene_permiso('miembros.exportar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  select count(*)::integer into n from public.miembros;
  perform private.adn_registrar_descarga('miembros', n);
  return query
  select m.crm_id, m.nombre, m.apellido, m.email, m.telefono, m.fecha_nacimiento, m.genero, h.nombre,
         m.nivel_compromiso, coalesce(m.bautizado, false), m.fecha_conversion, coalesce(m.activo, false), m.created_at::date
  from public.miembros m left join public.casas_oracion h on h.id = m.casa_oracion_id and h.iglesia_id = m.iglesia_id
  order by m.crm_id;
end $$;

-- ===== migrations/20261111190000_adn_consentimiento.sql (sha256 72a42d362624) =====
-- Consentimiento de comunicacion por persona y canal, y formato de contactos de Wix.
--  * Comunicacion solo envia a quien consta como 'suscrito' en ese canal. Quien no tiene registro, o consta como
--    'nunca', 'cancelado' o 'sin_dato', se omite con el motivo 'sin_consentimiento'. Una suscripcion cancelada tambien
--    protege a quien comparta esa direccion.
--  * La importacion nunca vuelve menos restrictivo un consentimiento: sobre una persona que ya existe solo puede
--    endurecerlo (de suscrito a nunca o cancelado, de nunca a cancelado). Reimportar un archivo no resucita una baja.
--  * 'sms' se guarda para el futuro: hoy Comunicacion no tiene canal SMS. WhatsApp tiene su propio consentimiento y
--    ningun archivo importado lo trae: no se envia por WhatsApp a nadie hasta que conste.
-- Reversion: supabase/reversiones/20261111190000_adn_consentimiento.down.sql

create table public.adn_consentimientos (
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  canal text not null check (canal in ('email', 'sms', 'whatsapp')),
  estado text not null check (estado in ('suscrito', 'nunca', 'cancelado', 'sin_dato')),
  origen text not null check (origen ~ '^[a-z0-9_-]{1,30}$'),
  actualizado_en timestamptz not null default now(),
  primary key (miembro_id, canal),
  constraint adn_consentimientos_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete cascade
);
create index adn_consentimientos_iglesia_idx on public.adn_consentimientos (iglesia_id, canal, estado);

-- Solo lo escriben las funciones de abajo: la web lo lee
alter table public.adn_consentimientos enable row level security;
create policy adn_consentimientos_ver on public.adn_consentimientos for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and ((select private.tiene_permiso('miembros.ver')) or (select private.tiene_permiso('comunicacion.ver'))));
revoke all on public.adn_consentimientos from public, anon, authenticated;
grant select on public.adn_consentimientos to authenticated;
grant all on public.adn_consentimientos to service_role;

-- Un envio omitido por falta de consentimiento
alter table public.adn_mensaje_destinatarios drop constraint adn_mensaje_destinatarios_motivo_check;
alter table public.adn_mensaje_destinatarios add constraint adn_mensaje_destinatarios_motivo_check
  check (motivo in ('sin_destino', 'baja', 'repetido', 'sin_consentimiento'));

-- Aplica el consentimiento que trae una fila importada. 'nuevo': persona recien creada, se guarda tal cual.
-- 'endurecer': persona que ya existia, solo se guarda si es mas restrictivo que lo que consta.
-- Orden de restriccion: suscrito < sin_dato < nunca < cancelado.
create or replace function private.adn_aplicar_consentimiento(p_miembro uuid, p_consent jsonb, p_origen text, p_modo text)
returns void language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  v_canal text; v_nuevo text; v_actual text;
  rango constant jsonb := '{"suscrito": 0, "sin_dato": 1, "nunca": 2, "cancelado": 3}';
begin
  if ig is null or p_miembro is null or jsonb_typeof(p_consent) is distinct from 'object' then return; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then return; end if;
  foreach v_canal in array array['email', 'sms', 'whatsapp'] loop
    v_nuevo := p_consent ->> v_canal;
    continue when v_nuevo is null or v_nuevo not in ('suscrito', 'nunca', 'cancelado');
    select k.estado into v_actual from public.adn_consentimientos k where k.miembro_id = p_miembro and k.canal = v_canal;
    if v_actual is null then
      -- Sin registro: una persona nueva se guarda como venga; una existente solo si el estado restringe
      if p_modo = 'nuevo' or v_nuevo in ('nunca', 'cancelado') then
        insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values (ig, p_miembro, v_canal, v_nuevo, p_origen);
      end if;
    elsif (rango ->> v_nuevo)::int > (rango ->> v_actual)::int then
      update public.adn_consentimientos set estado = v_nuevo, origen = p_origen, actualizado_en = now()
       where miembro_id = p_miembro and canal = v_canal;
    end if;
  end loop;
end $$;
revoke execute on function private.adn_aplicar_consentimiento(uuid, jsonb, text, text) from public, anon;
grant execute on function private.adn_aplicar_consentimiento(uuid, jsonb, text, text) to authenticated, service_role;

-- La persona que ya existe y coincide con una fila importada: por correo; si no hay correo, por telefono; si no, por nombre
create or replace function private.adn_miembro_existente(p_correos text[], p_telefonos text[], p_clave_nombre text)
returns uuid language sql stable set search_path to '' as $$
  select coalesce(
    case when coalesce(array_length(p_correos, 1), 0) > 0 then
      coalesce((select m.id from public.miembros m where lower(m.email) = any (p_correos) order by m.created_at, m.id limit 1),
               (select x.miembro_id from public.adn_miembro_contactos x where x.tipo = 'correo' and lower(x.valor) = any (p_correos) order by x.miembro_id limit 1)) end,
    case when coalesce(array_length(p_telefonos, 1), 0) > 0 then
      coalesce((select m.id from public.miembros m where public.adn_telefono_canonico(m.telefono) = any (p_telefonos) order by m.created_at, m.id limit 1),
               (select x.miembro_id from public.adn_miembro_contactos x where x.tipo = 'telefono' and public.adn_telefono_canonico(x.valor) = any (p_telefonos) order by x.miembro_id limit 1)) end,
    case when p_clave_nombre is not null then
      (select m.id from public.miembros m where lower(regexp_replace(btrim(m.nombre || ' ' || m.apellido), '\s+', ' ', 'g')) = p_clave_nombre order by m.created_at, m.id limit 1) end)
$$;
revoke execute on function private.adn_miembro_existente(text[], text[], text) from public, anon;
grant execute on function private.adn_miembro_existente(text[], text[], text) to authenticated, service_role;

-- Registro manual de un consentimiento por quien edita miembros: es una decision humana y puede dejar cualquier estado
create or replace function private.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text)
returns void language plpgsql security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id();
begin
  if ig is null or not (select private.tiene_permiso('miembros.editar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_canal not in ('email', 'sms', 'whatsapp') or p_estado not in ('suscrito', 'nunca', 'cancelado', 'sin_dato') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  if not exists (select 1 from public.miembros m where m.id = p_miembro and m.iglesia_id = ig) then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) values (ig, p_miembro, p_canal, p_estado, 'manual')
  on conflict (miembro_id, canal) do update set estado = excluded.estado, origen = 'manual', actualizado_en = now();
end $$;
revoke execute on function private.adn_registrar_consentimiento(uuid, text, text) from public, anon;
grant execute on function private.adn_registrar_consentimiento(uuid, text, text) to authenticated, service_role;
create or replace function public.adn_registrar_consentimiento(p_miembro uuid, p_canal text, p_estado text)
returns void language sql set search_path to '' as $$ select private.adn_registrar_consentimiento(p_miembro, p_canal, p_estado) $$;
revoke all on function public.adn_registrar_consentimiento(uuid, text, text) from public, anon;
grant execute on function public.adn_registrar_consentimiento(uuid, text, text) to authenticated, service_role;

-- Destinatarios, vista previa, envio e importacion, con el consentimiento
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
  ), consent as (
    -- El consentimiento es por canal. WhatsApp no tiene el de correo ni el de SMS: necesita el suyo
    select k.miembro_id, k.estado from public.adn_consentimientos k
    where k.iglesia_id = p_iglesia and k.canal = case p_canal when 'email' then 'email' else 'whatsapp' end
  ), de_baja as (
    -- Una baja, o una suscripcion cancelada, vale para la persona y tambien para su direccion compartida
    select d.id, d.destino from dest d
    where exists (select 1 from public.adn_comunicacion_bajas x where x.iglesia_id = p_iglesia and x.miembro_id = d.id and x.canal = p_canal)
       or exists (select 1 from consent k where k.miembro_id = d.id and k.estado = 'cancelado')
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
                     when not exists (select 1 from consent k where k.miembro_id = b.id and k.estado = 'suscrito') then 'sin_consentimiento'
                end as motivo_a
    from base b
  ), numerado as (
    select p.*, case when p.motivo_a is null then row_number() over (partition by p.destino order by p.id) end as rn from previo p
  )
  select n.id, n.nombre, n.dia, n.destino, coalesce(n.motivo_a, case when n.rn > 1 then 'repetido' end) from numerado n
$$;

create or replace function private.adn_vista_previa_envio(p_canal text, p_segmento text)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare ig uuid := private.get_iglesia_id(); r jsonb;
begin
  if ig is null or not ((select private.tiene_permiso('comunicacion.enviar')) and (select private.tiene_permiso('miembros.ver'))) then raise exception 'ADN_SIN_PERMISO'; end if;
  if p_canal not in ('email', 'whatsapp') or p_segmento not in ('todos', 'nuevos', 'lideres', 'consolidacion') then raise exception 'ADN_DATOS_INVALIDOS'; end if;
  select jsonb_build_object('total', count(*), 'recibiran', count(*) filter (where motivo is null),
    'sin_destino', count(*) filter (where motivo = 'sin_destino'), 'baja', count(*) filter (where motivo = 'baja'), 'repetido', count(*) filter (where motivo = 'repetido'),
    'sin_consentimiento', count(*) filter (where motivo = 'sin_consentimiento'))
  into r from private.adn_destinatarios(ig, p_canal, p_segmento);
  return r;
end $$;


create or replace function private.adn_enviar_mensaje(p_clave uuid, p_canal text, p_segmento text, p_asunto text, p_texto text, p_dia text default '')
returns jsonb language plpgsql security definer set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  nombre_ig text;
  texto text := btrim(coalesce(p_texto, ''));
  asunto text := nullif(btrim(coalesce(p_asunto, '')), '');
  existente public.adn_mensajes;
  id_msg uuid;
  n_total int; n_env int; n_sin int; n_baja int; n_rep int; n_cons int;
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

  select count(*) filter (where estado = 'enviado'), count(*) filter (where motivo = 'sin_destino'), count(*) filter (where motivo = 'baja'), count(*) filter (where motivo = 'repetido'), count(*) filter (where motivo = 'sin_consentimiento')
    into n_env, n_sin, n_baja, n_rep, n_cons
    from public.adn_mensaje_destinatarios where iglesia_id = ig and mensaje_id = id_msg;
  update public.adn_mensajes set total = n_env + n_sin + n_baja + n_rep + n_cons, enviados = n_env, omitidos = n_sin + n_baja + n_rep + n_cons,
         estado = case when n_env > 0 then 'enviado' else 'sin_destinatarios' end
   where id = id_msg;
  return jsonb_build_object('mensaje_id', id_msg, 'total', n_env + n_sin + n_baja + n_rep + n_cons, 'enviados', n_env,
                            'omitidos', jsonb_build_object('sin_destino', n_sin, 'baja', n_baja, 'repetido', n_rep, 'sin_consentimiento', n_cons),
                            'proveedor', 'sumidero', 'repetido', false);
end $$;


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
        n_dup_correo := n_dup_correo + 1;
        perform private.adn_aplicar_consentimiento(private.adn_miembro_existente(correos, '{}', null), f -> 'consentimiento', p_origen, 'endurecer');
        continue;
      end if;
    elsif array_length(telefonos, 1) > 0 then
      if telefonos && vistos_tel
         or exists (select 1 from public.miembros m where public.adn_telefono_canonico(m.telefono) = any (telefonos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'telefono' and public.adn_telefono_canonico(x.valor) = any (telefonos)) then
        n_dup_tel := n_dup_tel + 1;
        perform private.adn_aplicar_consentimiento(private.adn_miembro_existente('{}', telefonos, null), f -> 'consentimiento', p_origen, 'endurecer');
        continue;
      end if;
    else
      clave_nombre := lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
      if clave_nombre = any (vistos_nombre)
         or exists (select 1 from public.miembros m where lower(regexp_replace(btrim(m.nombre || ' ' || m.apellido), '\s+', ' ', 'g')) = clave_nombre) then
        n_dup_nombre := n_dup_nombre + 1;
        perform private.adn_aplicar_consentimiento(private.adn_miembro_existente('{}', '{}', clave_nombre), f -> 'consentimiento', p_origen, 'endurecer');
        continue;
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
    -- Estado de suscripcion de cada canal que traiga el archivo (consentimiento): lo guarda la funcion privada
    perform private.adn_aplicar_consentimiento(nuevo, f -> 'consentimiento', p_origen, 'nuevo');

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

