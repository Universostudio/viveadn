-- Vive ADN, REVERSIÓN del traspaso, archivo 1 de 7. Solo si Gerencia lo ordena. Aplicar en orden y detenerse en el primer error. Deja el real como estaba antes del traspaso (salvo los datos que se hayan creado después).
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
