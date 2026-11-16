-- Reversión de 20261111370000_adn_prueba_vencida_lectura.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena.
-- Devuelve tiene_permiso a su forma anterior (una prueba vencida corta todos los módulos) y quita la función nueva. No toca ningún dato.
\set ON_ERROR_STOP on
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
