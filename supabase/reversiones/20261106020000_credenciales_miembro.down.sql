-- Reversion de 20261106020000_credenciales_miembro.sql. Borra la tabla de credenciales (los QR impresos dejan de valer),
-- sus funciones y el permiso. No toca la asistencia ya registrada. Solo para una base temporal o una decision explicita.
begin;
-- El disparador vuelve a su version anterior, sin la semilla de credenciales
create or replace function private.trg_sembrar_roles()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  perform private.sembrar_formacion(new.id);
  return new;
end $$;
drop function if exists public.registrar_asistencia_credencial(uuid, text);
drop function if exists public.retirar_credencial(uuid);
drop function if exists public.emitir_credencial(uuid, boolean);
drop function if exists private.registrar_asistencia_credencial(uuid, text);
drop function if exists private.retirar_credencial(uuid);
drop function if exists private.emitir_credencial(uuid, boolean);
drop table if exists public.credenciales_miembro;
drop function if exists private.sembrar_credencial(uuid);
delete from public.rol_permisos where permiso = 'credenciales.gestionar';
delete from public.permisos where clave = 'credenciales.gestionar';
commit;
