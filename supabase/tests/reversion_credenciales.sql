-- La reversion de credenciales deja la base como antes y la migracion se puede volver a aplicar.
\set ON_ERROR_STOP on
create or replace function pg_temp.igual(obtenido text, esperado text, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
select pg_temp.igual((to_regclass('public.credenciales_miembro') is null)::text, 'true', 'la reversion borra la tabla');
select pg_temp.igual((select count(*)::text from public.permisos where clave = 'credenciales.gestionar'), '0', 'y el permiso');
select pg_temp.igual((select count(*)::text from public.rol_permisos where permiso = 'credenciales.gestionar'), '0', 'y su asignacion a los roles');
select pg_temp.igual((select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where p.proname in ('emitir_credencial', 'retirar_credencial', 'registrar_asistencia_credencial', 'sembrar_credencial')), '0', 'y todas las funciones');
select pg_temp.igual((pg_get_functiondef('private.trg_sembrar_roles'::regproc) like '%sembrar_credencial%')::text, 'false', 'el disparador vuelve a su version anterior');
select pg_temp.igual((pg_get_functiondef('private.trg_sembrar_roles'::regproc) like '%sembrar_formacion%')::text, 'true', 'sin perder la siembra de formacion');
