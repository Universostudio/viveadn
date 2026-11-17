-- Vive ADN, traspaso al proyecto real, archivo 16 de 19: tramo 15 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('public.adn_avisos_estadisticas(uuid[])') is not null then raise notice 'Tramo 15 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('public.adn_aviso_entregar(uuid)') is not null) then raise exception 'Falta aplicar antes el tramo 14 de 15: no se sigue.'; end if;
  execute $cuerpo$

alter table public.planes add column if not exists moneda text;
alter table public.planes add constraint adn_planes_precio_coherente check (
  (precio_mensual_centimos is null or precio_mensual_centimos between 0 and 10000000)
  and (precio_anual_centimos is null or precio_anual_centimos between 0 and 100000000)
  and (moneda is null or moneda ~ '^[A-Z]{3}$')
  and ((precio_mensual_centimos is null and precio_anual_centimos is null) or moneda is not null));
-- ===== 20261111370000_adn_prueba_vencida_lectura (origen sha256 b86ac835b780, compilado sha256 b4f0f1757e1c) =====
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
-- ===== 20261111380000_adn_purga_tarea_estado (origen sha256 73fd429e1604, compilado sha256 d7c16a5b4f58) =====
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
-- ===== 20261111390000_adn_soporte_prueba_vencida (origen sha256 2e391cdde5de, compilado sha256 828f3d3232b5) =====
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
create policy adn_tickets_ver on public.adn_tickets for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
create policy adn_tickets_crear on public.adn_tickets for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and creado_por = (select auth.uid()) and estado = 'abierto' and (select private.adn_puede_pedir_ayuda()));
create policy adn_ticket_mensajes_ver on public.adn_ticket_mensajes for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.adn_puede_pedir_ayuda()));
create policy adn_ticket_mensajes_crear on public.adn_ticket_mensajes for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and autor_tipo = 'iglesia' and autor = (select auth.uid()) and (select private.adn_puede_pedir_ayuda()));
-- ===== 20261111400000_adn_agregados_plataforma (origen sha256 4bbc3337c1c2, compilado sha256 baf402657d7e) =====
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
$cuerpo$;
end $tramo$;
select 'ok: tramo 15 de 15 aplicado' as resultado, (to_regprocedure('public.adn_avisos_estadisticas(uuid[])') is not null) as comprobado;
