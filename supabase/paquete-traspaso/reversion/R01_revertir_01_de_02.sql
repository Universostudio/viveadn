-- Vive ADN, REVERSIÓN del traspaso, archivo 1 de 2. Solo si Gerencia lo ordena. Aplicar en orden y detenerse en el primer error. Deja el real como estaba antes del traspaso (salvo los datos que se hayan creado después).
set search_path = public, extensions;

-- ===== reversión de 20261111400000_adn_agregados_plataforma =====
-- Reversión de 20261111400000_adn_agregados_plataforma.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las tres funciones de agregado (solo leen, no tocan datos).
-- Sin ellas, la función de borde 'plataforma' lee las filas y cuenta ella misma, por páginas, como antes de esta migración.

begin;
drop function public.adn_avisos_estadisticas(uuid[]);
drop function public.adn_soporte_resumen(boolean);
drop function public.adn_plataforma_facturacion();
commit;

-- ===== reversión de 20261111390000_adn_soporte_prueba_vencida =====
-- Reversión de 20261111390000_adn_soporte_prueba_vencida.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena.
-- Devuelve las cuatro políticas de tickets y mensajes a su forma de 350000 (solo iglesia.configurar) y quita la función nueva. No toca ningún dato.

begin;
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
drop function if exists private.adn_puede_pedir_ayuda();
commit;

-- ===== reversión de 20261111380000_adn_purga_tarea_estado =====
-- Reversión de 20261111380000_adn_purga_tarea_estado.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena. No toca ningún dato ni ninguna tarea programada.

begin;
drop function if exists public.adn_purga_tarea_estado();
drop function if exists private.adn_purga_tarea_estado();
commit;

-- ===== reversión de 20261111370000_adn_prueba_vencida_lectura =====
-- Reversión de 20261111370000_adn_prueba_vencida_lectura.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena.
-- Devuelve tiene_permiso a su forma anterior (una prueba vencida corta todos los módulos) y quita la función nueva. No toca ningún dato.

begin;
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
drop function if exists private.adn_nucleo_en_lectura(text, text);
commit;

-- ===== reversión de 20261111360000_adn_precios_plan =====
-- Reversión de 20261111360000_adn_precios_plan.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena.
-- Quita las tres columnas de precio de planes; los precios que alguien hubiera fijado se pierden (no hay otra copia). El resto de planes no se toca.

begin;
alter table public.planes drop constraint if exists adn_planes_precio_coherente;
alter table public.planes drop column if exists moneda;
alter table public.planes drop column if exists precio_anual_centimos;
alter table public.planes drop column if exists precio_mensual_centimos;
commit;

-- ===== reversión de 20261111350000_adn_soporte =====
-- Reversión de 20261111350000_adn_soporte.sql (soporte dentro de la plataforma). No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh y tests/adn_soporte.sh demuestran que deja el esquema idéntico al anterior.
-- ATENCIÓN: borra las tablas nuevas y TODO lo que tengan (tickets, mensajes, novedades, avisos y sus entregas). Es lo único que se pierde; ninguna tabla anterior se toca.

begin;
-- La lista de tablas exportables vuelve a su definición anterior (sin la exclusión de las entregas de avisos)
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
drop function if exists public.adn_aviso_entregar(uuid);
drop policy if exists adn_avisos_ver on public.adn_avisos;
drop table if exists public.adn_avisos_entregas;
drop table if exists public.adn_avisos;
drop function if exists private.adn_destino_valido(jsonb);
drop function if exists public.adn_novedades_marcar_vistas();
drop table if exists public.adn_novedades_vistas;
drop table if exists public.adn_novedades;
drop function if exists public.adn_ticket_crear(text, text, text);
drop table if exists public.adn_ticket_mensajes;
drop table if exists public.adn_tickets;
drop function if exists private.adn_mensaje_iglesia();
drop function if exists private.adn_mensaje_estado();
drop function if exists private.adn_tickets_limite();
commit;

-- ===== reversión de 20261111340000_adn_seguimiento_propio =====
-- Reversión de 20261111340000_adn_seguimiento_propio.sql (fase 3 del método de seguimiento configurable). No es una migración: se ejecuta a mano,
-- solo si Gerencia lo ordena, y tests/adn_reversion.sh y tests/adn_seguimiento_propio.sh demuestran que deja el esquema idéntico al anterior.
-- NO borra ningún método propio, ninguna configuración ni ningún proceso: solo quita la posibilidad de escribir desde la web, el módulo y los disparadores.
-- Los métodos propios que existan siguen en la base y los procesos que los usan siguen calculando con ellos. Los procesos nuevos vuelven a tomar OP72.

begin;
drop function if exists public.adn_seguimiento_en_uso(uuid);
drop function if exists private.adn_seguimiento_en_uso(uuid);
drop trigger if exists consolidaciones_a_metodo on public.consolidaciones;
drop function if exists private.adn_consolidacion_metodo_activo();
drop trigger if exists adn_seguimiento_config_fecha on public.adn_seguimiento_config;
drop function if exists private.adn_config_tocar();
drop policy if exists adn_seguimiento_config_cambiar on public.adn_seguimiento_config;
drop policy if exists adn_seguimiento_config_elegir on public.adn_seguimiento_config;
revoke all on public.adn_seguimiento_config from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_config to authenticated;
grant all on public.adn_seguimiento_config to service_role;
drop trigger if exists adn_seguimiento_metodos_recalcular on public.adn_seguimiento_metodos;
drop function if exists private.adn_metodo_recalcular();
drop trigger if exists adn_seguimiento_metodos_archivo on public.adn_seguimiento_metodos;
drop function if exists private.adn_no_archivar_activo();
drop trigger if exists adn_seguimiento_metodos_limite on public.adn_seguimiento_metodos;
drop function if exists private.adn_limitar_metodos();
drop policy if exists adn_seguimiento_metodos_editar on public.adn_seguimiento_metodos;
drop policy if exists adn_seguimiento_metodos_crear on public.adn_seguimiento_metodos;
revoke all on public.adn_seguimiento_metodos from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_metodos to authenticated;
grant all on public.adn_seguimiento_metodos to service_role;
drop function if exists private.adn_metodo_usable(uuid);
-- La comprobación de plantilla vuelve a su definición de la fase 1 (con la seguridad de quien llama)
create or replace function private.adn_comprobar_plantilla() returns trigger language plpgsql set search_path to '' as $$
begin
  if new.plantilla_origen is not null and exists (select 1 from public.adn_seguimiento_metodos o where o.id = new.plantilla_origen and o.iglesia_id is not null and o.iglesia_id is distinct from new.iglesia_id) then
    raise exception 'ADN_PLANTILLA_DE_OTRA_IGLESIA' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_plantilla() from public, anon, authenticated, service_role;
create or replace function private.adn_comprobar_metodo() returns trigger language plpgsql set search_path to '' as $$
declare m record;
begin
  select iglesia_id, archivado_en into m from public.adn_seguimiento_metodos where id = new.metodo_id;
  if not found then raise exception 'ADN_METODO_INEXISTENTE' using errcode = 'foreign_key_violation'; end if;
  if m.iglesia_id is not null and m.iglesia_id <> new.iglesia_id then raise exception 'ADN_METODO_DE_OTRA_IGLESIA' using errcode = 'check_violation'; end if;
  if m.archivado_en is not null and (tg_op = 'INSERT' or new.metodo_id is distinct from old.metodo_id) then raise exception 'ADN_METODO_ARCHIVADO' using errcode = 'check_violation'; end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_metodo() from public, anon, authenticated, service_role;
-- El módulo: si alguna iglesia lo tenía contratado aparte, esa fila se quita con él
delete from public.iglesia_modulos where modulo = 'seguimiento_propio';
delete from public.plan_modulos where modulo = 'seguimiento_propio';
delete from public.modulos where clave = 'seguimiento_propio';
commit;

-- ===== reversión de 20261111330000_adn_seguimiento_metricas =====
-- Reversión de 20261111330000_adn_seguimiento_metricas.sql (fase 2 del método de seguimiento configurable). No es una migración: se ejecuta a mano,
-- solo si Gerencia lo ordena, y tests/adn_reversion.sh y tests/adn_seguimiento_metricas.sh demuestran que deja el esquema idéntico al anterior.
-- Devuelve metricas_op72 a su definición anterior (72 y 24 horas escritas en la función). No toca ningún dato.

begin;
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
commit;

-- ===== reversión de 20261111320000_adn_seguimiento_metodos =====
-- Reversión de 20261111320000_adn_seguimiento_metodos.sql (fase 1 del método de seguimiento configurable). No es una migración: se ejecuta a mano,
-- solo si Gerencia lo ordena, y tests/adn_reversion.sh y tests/adn_seguimiento_metodos.sh demuestran que deja el esquema idéntico al anterior.
-- Devuelve el disparador de consolidaciones a su versión anterior (72 horas y colores a 24, 48 y 72 escritos en la función), quita la columna
-- metodo_id y borra los métodos y la configuración. No toca ningún dato de consolidaciones: todos los procesos siguen con sus fechas y su color.

begin;
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

drop view public.adn_seguimiento_estado;
drop trigger consolidaciones_metodo on public.consolidaciones;
alter table public.consolidaciones drop column metodo_id;
drop function public.adn_seguimiento_alerta(timestamptz, boolean, uuid, timestamptz);
drop function private.adn_alerta_con_umbrales(timestamptz, boolean, integer, integer, integer, timestamptz);
drop function private.adn_metodo_activo(uuid);
drop table public.adn_seguimiento_config;
drop table public.adn_seguimiento_metodos;
drop function private.adn_comprobar_metodo();
drop function private.adn_comprobar_plantilla();
commit;

-- ===== reversión de 20261111310000_adn_asistencias_unico =====
-- Reversión de 20261111310000_adn_asistencias_unico.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo
-- ordena, y tests/adn_reversion.sh y tests/adn_asistencias_unico.sh demuestran que deja el esquema idéntico al anterior.
-- Quita el índice único y DEVUELVE a asistencias las filas duplicadas que la limpieza archivó, para que los datos
-- queden como estaban antes de aplicar la migración. Después borra la tabla de archivo.

begin;
drop index public.adn_asistencias_unica_idx;
insert into public.asistencias (id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente, notas, created_at)
  select id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente, notas, created_at from public.adn_asistencias_duplicadas;
drop table public.adn_asistencias_duplicadas;
commit;

-- ===== reversión de 20261111300000_adn_checkin_nuevo_creyente =====
-- Reversión de 20261111300000_adn_checkin_nuevo_creyente.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo
-- ordena, y tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior.
-- Devuelve registrar_checkin a su definición anterior (con la doble confirmación; toda persona nueva abre seguimiento).
-- No toca datos: los seguimientos que se abrieron o no se abrieron mientras estuvo la pregunta se quedan como están.

begin;
drop function public.registrar_checkin(text, text, text, text, text, text, text, text, text[], boolean);
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null, p_canales text[] default null)
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
    insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, notas)
      values (c.iglesia_id, v_miembro, now(), 'Registro por QR en el evento: ' || c.titulo);
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

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) to service_role;
commit;

-- ===== reversión de 20261111290000_adn_plataforma_resumen =====
-- Reversión de 20261111290000_adn_plataforma_resumen.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las tres funciones de lectura del Panel Maestro
-- (no tocan datos: solo leen). Sin ellas, la función de borde 'plataforma' vuelve a contar con 2 consultas por iglesia y las pantallas
-- de actividad e historial dicen que no están disponibles; el resto del panel sigue funcionando.

begin;
drop function public.adn_plataforma_historial(uuid, integer);
drop function public.adn_plataforma_actividad(integer);
drop function public.adn_plataforma_resumen();
commit;

-- ===== reversión de 20261111280000_adn_envios_topes =====
-- Reversión de 20261111280000_adn_envios_topes.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las dos funciones y la tabla de contadores
-- diarios de envío (con sus filas: solo son cuentas del día, sin datos de personas). Sin ella, el envío de correo no debe estar encendido.

begin;
drop function public.adn_envio_liberar(text, uuid);
drop function public.adn_envio_reservar(text, uuid, integer, integer, integer);
drop table public.adn_envios_dia;
commit;

-- ===== reversión de 20261111270000_adn_autoservicio_datos =====
-- Reversión de 20261111270000_adn_autoservicio_datos.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las funciones de autoservicio y la tabla de
-- auditoría que creó esa migración (con las filas que tuviera). Las iglesias que ya estuvieran en borrado suave por una baja pedida
-- por su propietario siguen su curso normal: el borrado suave y su auditoría (adn_ciclo_auditoria) no los toca esta reversión,
-- y la plataforma puede recuperarlas con `recuperar` como a cualquier otra.

begin;
drop function public.adn_autoservicio_cancelar_baja(uuid, uuid, text);
drop function public.adn_autoservicio_baja(uuid, uuid, text);
drop function public.adn_autoservicio_exportar(uuid, uuid);
drop function public.adn_autoservicio_estado(uuid, uuid);
drop function public.adn_es_propietario(uuid, uuid);
drop table public.adn_datos_auditoria;
commit;

-- ===== reversión de 20261111260000_adn_exportacion_paginada =====
-- Reversión de 20261111260000_adn_exportacion_paginada.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita las funciones de la exportación por páginas;
-- adn_exportar_paquete, que sigue existiendo, no se toca.

begin;
drop function public.adn_exportar_pagina(uuid, text, text, jsonb, integer);
drop function public.adn_exportar_plan(uuid);
drop function public.adn_exportar_orden();
drop function public.adn_exportar_secretos();
commit;

-- ===== reversión de 20261111250000_adn_purgas_libro =====
-- Reversión de 20261111250000_adn_purgas_libro.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita las dos funciones; no toca datos ni la
-- auditoría del ciclo de vida, y las iglesias que ya se hubieran marcado con adn_repurgar_registradas siguen su curso normal.

begin;
drop function public.adn_repurgar_registradas(uuid[], uuid);
drop function public.adn_purgas_desde(timestamptz);
commit;

-- ===== reversión de 20261111240000_adn_purga_estado =====
-- Reversión de 20261111240000_adn_purga_estado.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita la función de lectura.

begin;
drop function public.adn_purga_estado(integer);
commit;

-- ===== reversión de 20261111230000_adn_doble_confirmacion =====
-- Reversión de 20261111230000_adn_doble_confirmacion.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo
-- ordena, y tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior.
-- Borra las solicitudes de confirmación y las evidencias de tipo confirmacion, quita el ajuste y devuelve registrar_checkin a
-- su definición anterior. NO borra los consentimientos que las confirmaciones concedieron ni su auditoría.

begin;
drop function public.adn_confirmacion_consumir(text);
drop function public.adn_confirmacion_fallida(uuid);
drop function public.adn_confirmacion_preparar(integer, integer);
drop function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]);
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null, p_canales text[] default null)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
  v_ver text := nullif(btrim(coalesce(p_texto_version, '')), ''); v_hash text;
  v_canal text; v_hash_c text;
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
    insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, finalidad, texto_version, idioma, texto_hash, evento_id, aplicado, origen)
      values (c.iglesia_id, v_miembro, 'checkin', v_canal, 'checkin_' || v_canal, case when v_hash_c is null then 'sin_version' else v_ver end,
              case when v_hash_c is null then null else p_idioma end, v_hash_c, c.evento_id, v_nuevo and v_hash_c is not null, 'qr');
    if v_nuevo and v_hash_c is not null then
      perform private.adn_escribir_consentimiento(c.iglesia_id, v_miembro, v_canal, 'suscrito', 'qr', null);
    end if;
  end loop;

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) to service_role;
drop function private.adn_doble_confirmacion_activa();
delete from public.adn_consentimiento_evidencias where tipo = 'confirmacion';
alter table public.adn_consentimiento_evidencias drop constraint adn_consentimiento_evidencias_forma;
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_forma check (
  (tipo = 'checkin' and finalidad is not null and texto_version is not null)
  or (tipo = 'importacion' and canal is not null and texto_original is not null));
alter table public.adn_consentimiento_evidencias drop constraint adn_consentimiento_evidencias_tipo_check;
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_tipo_check check (tipo in ('checkin', 'importacion'));
drop table public.adn_confirmaciones;
delete from public.plataforma_ajustes where clave = 'adn_doble_confirmacion';
commit;

-- ===== reversión de 20261111220000_adn_checkin_canales =====
-- Reversión de 20261111220000_adn_checkin_canales.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo
-- ordena, y tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior.
-- Borra las evidencias de las casillas de canal y los textos v2, y devuelve registrar_checkin a su definición anterior.
-- NO borra los consentimientos que esas casillas concedieron (adn_consentimientos y su auditoría se conservan).

begin;
drop function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]);
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
  v_ver text := nullif(btrim(coalesce(p_texto_version, '')), ''); v_hash text;
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

  -- Evidencia de lo que aceptó quien se registró: qué texto (versión y huella) y cuándo. Cada registro deja una fila.
  -- La versión la afirma la página: si no consta en la tabla de textos se anota 'sin_version' y no se inventa una huella.
  select t.texto_hash into v_hash from public.adn_consentimiento_textos t where t.finalidad = 'checkin' and t.version = v_ver and t.idioma = p_idioma;
  insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, finalidad, texto_version, idioma, texto_hash, evento_id, origen)
    values (c.iglesia_id, v_miembro, 'checkin', 'checkin', case when v_hash is null then 'sin_version' else v_ver end,
            case when v_hash is null then null else p_idioma end, v_hash, c.evento_id, 'qr');

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text) to service_role;
delete from public.adn_consentimiento_evidencias where tipo = 'checkin' and canal is not null;
alter table public.adn_consentimiento_evidencias drop constraint adn_consentimiento_evidencias_forma;
alter table public.adn_consentimiento_evidencias add constraint adn_consentimiento_evidencias_forma check (
    (tipo = 'checkin' and finalidad is not null and texto_version is not null and canal is null)
    or (tipo = 'importacion' and canal is not null and texto_original is not null));
alter table public.adn_consentimiento_textos disable trigger adn_consentimiento_textos_inmutable;
delete from public.adn_consentimiento_textos where version = 'v2' and finalidad like 'checkin%';
alter table public.adn_consentimiento_textos enable trigger adn_consentimiento_textos_inmutable;
commit;

-- ===== reversión de 20261111210000_adn_consentimiento_evidencia =====
-- Reversión de 20261111210000_adn_consentimiento_evidencia.sql. No es una migración: se ejecuta a mano, solo si
-- Gerencia lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior.
-- Borra las evidencias de consentimiento (tabla y filas) y los textos versionados, y devuelve registrar_checkin, la
-- importación y su función de consentimiento a su definición anterior. NO toca adn_consentimientos ni su auditoría.

begin;
drop function public.registrar_checkin(text, text, text, text, text, text, text, text);
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

revoke execute on function public.registrar_checkin(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text) to service_role;
drop function private.adn_aplicar_consentimiento(uuid, jsonb, text, text, jsonb);
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
        perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
      end if;
    elsif (rango ->> v_nuevo)::int > (rango ->> v_actual)::int then
      perform private.adn_escribir_consentimiento(ig, p_miembro, v_canal, v_nuevo, p_origen, (select auth.uid()));
    end if;
  end loop;
end $$;
revoke execute on function private.adn_aplicar_consentimiento(uuid, jsonb, text, text) from public, anon;
grant execute on function private.adn_aplicar_consentimiento(uuid, jsonb, text, text) to authenticated, service_role;
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
drop table public.adn_consentimiento_evidencias;
drop table public.adn_consentimiento_textos;
drop function private.trg_consentimiento_inmutable();
commit;
