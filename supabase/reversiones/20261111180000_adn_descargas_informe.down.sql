-- Reversion de 20261111180000_adn_descargas_informe.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Borra el registro de descargas (la tabla y sus filas) y devuelve adn_informe_miembros a su definicion anterior.
\set ON_ERROR_STOP on
begin;
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
drop function if exists private.adn_registrar_descarga(text, integer);
drop table if exists public.adn_informe_descargas;
drop function if exists private.trg_descarga_inmutable();
commit;
