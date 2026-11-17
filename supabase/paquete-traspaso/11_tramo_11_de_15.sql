-- Vive ADN, traspaso al proyecto real, archivo 12 de 19: tramo 11 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regclass('public.adn_asistencias_duplicadas') is not null then raise notice 'Tramo 11 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('public.adn_envio_liberar(text,uuid)') is not null) then raise exception 'Falta aplicar antes el tramo 10 de 15: no se sigue.'; end if;
  execute $cuerpo$

-- ===== 20261111290000_adn_plataforma_resumen (origen sha256 b29a88b874b4, compilado sha256 65a21dcd82f4) =====
-- Panel Maestro: lecturas agregadas para la administración de la plataforma, sin datos de personas. Hasta ahora la función de borde
-- contaba miembros y usuarios con 2 consultas por iglesia (con 500 iglesias, 1.000 consultas por carga). Estas funciones lo hacen en una
-- sola consulta y devuelven únicamente identificadores, nombres de iglesia, acciones, fechas y números.
--  * adn_plataforma_resumen(): una fila por iglesia con su número de miembros y de usuarios (perfiles). Nada más.
--  * adn_plataforma_actividad(p_limite): las últimas altas de iglesias y acciones de plataforma, de más reciente a más antigua, hasta
--    p_limite (entre 1 y 100). De la auditoría de plataforma solo sale la acción, la iglesia y la fecha: NUNCA el detalle, que puede
--    contener datos que no deben verse.
--  * adn_plataforma_historial(p_iglesia, p_limite): las acciones de plataforma de una iglesia (acción y fecha), hasta p_limite (1 a 200).
--  * Solo las ejecuta el servidor (la función 'plataforma', que antes comprueba que quien llama es administrador de plataforma).
-- Reversión: supabase/reversiones/20261111290000_adn_plataforma_resumen.down.sql
create or replace function public.adn_plataforma_resumen()
returns table (iglesia_id uuid, miembros bigint, usuarios bigint) language sql stable set search_path to '' as $$
  select i.id, coalesce(m.n, 0), coalesce(p.n, 0)
  from public.iglesias i
  left join (select iglesia_id, count(*) as n from public.miembros group by iglesia_id) m on m.iglesia_id = i.id
  left join (select iglesia_id, count(*) as n from public.perfiles group by iglesia_id) p on p.iglesia_id = i.id
$$;

create or replace function public.adn_plataforma_actividad(p_limite integer default 20)
returns table (tipo text, accion text, iglesia_id uuid, iglesia_nombre text, fecha timestamptz) language sql stable set search_path to '' as $$
  select e.tipo, e.accion, e.iglesia_id, e.iglesia_nombre, e.fecha
  from (
    select 'alta'::text as tipo, 'crear_iglesia'::text as accion, i.id as iglesia_id, i.nombre as iglesia_nombre, i.created_at as fecha
    from public.iglesias i
    union all
    select 'accion', a.accion, a.iglesia_id, i.nombre, a.created_at
    from public.plataforma_auditoria a
    left join public.iglesias i on i.id = a.iglesia_id
    -- La alta ya sale como «alta»: no se repite como acción
    where a.accion <> 'crear_iglesia'
  ) e
  order by e.fecha desc, e.tipo, e.accion
  limit greatest(1, least(coalesce(p_limite, 20), 100))
$$;

create or replace function public.adn_plataforma_historial(p_iglesia uuid, p_limite integer default 50)
returns table (accion text, fecha timestamptz) language sql stable set search_path to '' as $$
  select a.accion, a.created_at
  from public.plataforma_auditoria a
  where a.iglesia_id = p_iglesia
  order by a.created_at desc, a.id desc
  limit greatest(1, least(coalesce(p_limite, 50), 200))
$$;

revoke all on function public.adn_plataforma_resumen(), public.adn_plataforma_actividad(integer), public.adn_plataforma_historial(uuid, integer) from public, anon, authenticated;
grant execute on function public.adn_plataforma_resumen(), public.adn_plataforma_actividad(integer), public.adn_plataforma_historial(uuid, integer) to service_role;
-- ===== 20261111300000_adn_checkin_nuevo_creyente (origen sha256 73013778c78a, compilado sha256 47764695310a) =====

create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null, p_canales text[] default null, p_nuevo_creyente boolean default null)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
  v_ver text := nullif(btrim(coalesce(p_texto_version, '')), ''); v_hash text;
  v_canal text; v_hash_c text; v_doble boolean := private.adn_doble_confirmacion_activa(); v_aplica boolean;
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
    -- Seguimiento solo si quien se registra dice que es nuevo creyente. Sin respuesta (una pagina antigua que aun no
    -- hace la pregunta) se conserva el comportamiento anterior, para que nadie se quede sin acompañamiento por un cambio de version.
    -- A una persona que ya existia no se le abre seguimiento desde un formulario publico: no prueba su identidad.
    if coalesce(p_nuevo_creyente, true) then
      insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, notas)
        values (c.iglesia_id, v_miembro, now(), 'Registro por QR en el evento: ' || c.titulo || case when p_nuevo_creyente then '. Dijo ser nuevo creyente.' else '' end);
    end if;
  end if;

  insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente)
    values (c.iglesia_id, c.evento_id, v_miembro, true)
    on conflict (evento_id, miembro_id) do update set presente = true;
  insert into public.checkin_registros (iglesia_id, evento_id, miembro_id, ip_hash, creado)
    values (c.iglesia_id, c.evento_id, v_miembro, p_ip_hash, v_nuevo);

  -- Evidencia de lo que aceptó quien se registró: qué texto (versión y huella) y cuándo. Cada registro deja una fila.
  -- La versión la afirma la página: si no consta en la tabla de textos se anota 'sin_version' y no se inventa una huella.
  select t.texto_hash into v_hash from public.adn_consentimiento_textos t where t.finalidad = 'checkin' and t.version = v_ver and t.idioma = p_idioma;
  insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, finalidad, texto_version, idioma, texto_hash, evento_id, origen)
    values (c.iglesia_id, v_miembro, 'checkin', 'checkin', case when v_hash is null then 'sin_version' else v_ver end,
            case when v_hash is null then null else p_idioma end, v_hash, c.evento_id, 'qr');

  -- Casillas de canal (correo, WhatsApp, SMS): cada una marcada deja su evidencia con el texto que acompañaba a esa casilla.
  -- Solo una persona NUEVA queda suscrita: a quien ya existía no se le cambia el consentimiento, porque el correo o el
  -- teléfono que escribe alguien en un formulario público no prueban que sea la misma persona. Sin una versión de texto
  -- verificable en la tabla, la casilla queda anotada pero no concede nada.
  for v_canal in select distinct u from unnest(coalesce(p_canales, '{}')) u order by u loop
    continue when v_canal not in ('email', 'whatsapp', 'sms');
    continue when v_canal = 'email' and coalesce(btrim(p_email), '') = '';
    select t.texto_hash into v_hash_c from public.adn_consentimiento_textos t where t.finalidad = 'checkin_' || v_canal and t.version = v_ver and t.idioma = p_idioma;
    -- Con la doble confirmación activa, la casilla NO concede nada todavía: el consentimiento llega cuando la persona
    -- confirma desde el enlace que se le envía. Hoy solo el correo tiene ese mecanismo; WhatsApp y SMS quedan sin conceder.
    v_aplica := v_nuevo and v_hash_c is not null and not v_doble;
    insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, finalidad, texto_version, idioma, texto_hash, evento_id, aplicado, origen)
      values (c.iglesia_id, v_miembro, 'checkin', v_canal, 'checkin_' || v_canal, case when v_hash_c is null then 'sin_version' else v_ver end,
              case when v_hash_c is null then null else p_idioma end, v_hash_c, c.evento_id, v_aplica, 'qr');
    if v_aplica then
      perform private.adn_escribir_consentimiento(c.iglesia_id, v_miembro, v_canal, 'suscrito', 'qr', null);
    elsif v_nuevo and v_hash_c is not null and v_doble and v_canal = 'email'
          and lower(btrim(p_email)) ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(btrim(p_email)) <= 254 then
      insert into public.adn_confirmaciones (iglesia_id, miembro_id, canal, destino, idioma)
        values (c.iglesia_id, v_miembro, 'email', lower(btrim(p_email)), p_idioma) on conflict do nothing;
    end if;
  end loop;

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[], boolean) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[], boolean) to service_role;
-- ===== 20261111310000_adn_asistencias_unico (origen sha256 7a2b3835401e, compilado sha256 777a4f03ce9d) =====
-- Asistencia de casa de oración: una sola fila por casa, persona y fecha.
-- Hasta ahora nada lo impedía: la pantalla evita duplicar leyendo antes de guardar, pero dos personas que guardaran a la vez
-- la lista de la misma casa y fecha podían crear dos filas, y los informes contarían dos asistencias.
--  1. Limpieza de lo que ya exista: si hay filas repetidas para la misma casa, persona y fecha, se CONSERVA LA MÁS RECIENTE
--     (por fecha de creación y, en empate, por identificador) y las demás se copian a adn_asistencias_duplicadas antes de
--     borrarse. Si no hay repetidas, no se toca ninguna fila.
--  2. Índice único por casa, persona y fecha.
-- La reversión devuelve las filas archivadas: supabase/reversiones/20261111310000_adn_asistencias_unico.down.sql

-- «if not exists» en lo que crea: el incremental se puede repetir sin error ni cambios
create table if not exists public.adn_asistencias_duplicadas (
  id uuid primary key,
  iglesia_id uuid not null,
  casa_oracion_id uuid not null,
  miembro_id uuid not null,
  fecha date not null,
  presente boolean,
  notas text,
  created_at timestamptz,
  archivada_en timestamptz not null default now()
);
create index if not exists adn_asistencias_duplicadas_iglesia_idx on public.adn_asistencias_duplicadas (iglesia_id);
-- Solo para quien opera la base: ninguna persona con sesión la lee ni la escribe
alter table public.adn_asistencias_duplicadas enable row level security;
revoke all on public.adn_asistencias_duplicadas from public, anon, authenticated;
grant all on public.adn_asistencias_duplicadas to service_role;
-- Comprobación en lugar de la limpieza de asistencias duplicadas de la migración original: el real tiene 0 asistencias duplicadas, así que no hay nada que archivar.
-- Si algún día hubiera duplicados, esto falla y hay que archivarlos a mano antes de crear el índice único.
do $$ begin
  if exists (select 1 from public.asistencias group by casa_oracion_id, miembro_id, fecha having count(*) > 1) then
    raise exception 'Hay asistencias duplicadas: archivarlas a mano antes de crear el indice unico';
  end if;
end $$;


create unique index if not exists adn_asistencias_unica_idx on public.asistencias (casa_oracion_id, miembro_id, fecha);
$cuerpo$;
end $tramo$;
select 'ok: tramo 11 de 15 aplicado' as resultado, (to_regclass('public.adn_asistencias_duplicadas') is not null) as comprobado;
