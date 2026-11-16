-- Vive ADN, incremental tras 20261111360000. Aplicar una vez, solo sobre un proyecto que ya tiene el paquete completo hasta esa migración. Detenerse en el primer error.
set search_path = public, extensions;

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
