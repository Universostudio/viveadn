-- Vive ADN, traspaso al proyecto real, archivo 6 de 19: tramo 5 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('private.adn_miembro_existente(text[],text[],text)') is not null then raise notice 'Tramo 5 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('public.adn_vista_previa_envio(text,text)') is not null) then raise exception 'Falta aplicar antes el tramo 4 de 15: no se sigue.'; end if;
  execute $cuerpo$

create or replace function public.adn_enviar_mensaje(p_clave uuid, p_canal text, p_segmento text, p_asunto text, p_texto text, p_dia text default '')
returns jsonb language sql set search_path to '' as $$ select private.adn_enviar_mensaje(p_clave, p_canal, p_segmento, p_asunto, p_texto, p_dia) $$;
revoke all on function public.adn_vista_previa_envio(text, text), public.adn_enviar_mensaje(uuid, text, text, text, text, text) from public, anon;
grant execute on function public.adn_vista_previa_envio(text, text), public.adn_enviar_mensaje(uuid, text, text, text, text, text) to authenticated;
-- ===== 20261111170000_adn_panel_inicio (origen sha256 0d6529e35f80, compilado sha256 e1e65dc3865a) =====
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
-- ===== 20261111180000_adn_descargas_informe (origen sha256 d8e23c6f0d26, compilado sha256 9bbdb69c6c44) =====
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
-- ===== 20261111190000_adn_consentimiento (origen sha256 72a42d362624, compilado sha256 0bc72903655b) =====
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
alter table public.adn_mensaje_destinatarios add constraint adn_mensaje_destinatarios_motivo_check
  check (motivo in ('sin_destino', 'baja', 'repetido', 'sin_consentimiento'));

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
$cuerpo$;
end $tramo$;
select 'ok: tramo 5 de 15 aplicado' as resultado, (to_regprocedure('private.adn_miembro_existente(text[],text[],text)') is not null) as comprobado;
