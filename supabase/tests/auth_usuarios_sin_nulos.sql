-- Comprobacion de solo lectura: ningun usuario de auth.users puede tener NULL en las columnas de texto que lee el
-- servicio de Supabase (GoTrue). Una cuenta creada por SQL con NULL ahi rompe el inicio de sesion de ese servicio
-- ("converting NULL to string is unsupported"). Las cuentas creadas con la API de administracion no tienen el problema.
-- Se ejecuta contra una base con el esquema real de Supabase (la rama de pruebas). En la base local de pruebas, que
-- solo tiene la columna id, se omite. No imprime ningun dato de los usuarios, solo cuantas filas tiene cada columna.
-- Uso: psql -f tests/auth_usuarios_sin_nulos.sql [-v solo_definir=1 para solo definir la funcion]
\set ON_ERROR_STOP on
create or replace function pg_temp.comprobar_auth_sin_nulos() returns text language plpgsql as $$
declare
  col text; n bigint; mal text[] := '{}'; vistas int := 0;
  -- Columnas de texto de auth.users que GoTrue convierte a string sin admitir NULL
  columnas constant text[] := array['confirmation_token', 'recovery_token', 'email_change_token_new', 'email_change',
    'email_change_token_current', 'phone_change', 'phone_change_token', 'reauthentication_token'];
begin
  foreach col in array columnas loop
    if exists (select 1 from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name = col) then
      vistas := vistas + 1;
      execute format('select count(*) from auth.users where %I is null', col) into n;
      if n > 0 then mal := mal || (col || ':' || n); end if;
    end if;
  end loop;
  if vistas = 0 then return 'OMITIDO: auth.users no tiene las columnas de GoTrue (base local de pruebas)'; end if;
  if array_length(mal, 1) > 0 then
    raise exception 'FALLO: auth.users tiene NULL en columnas de texto que GoTrue no admite (columna:filas) %. Corrige con: update auth.users set <columna> = '''' where <columna> is null', mal;
  end if;
  return format('OK: ninguna de las %s columnas de texto de auth.users tiene NULL', vistas);
end $$;
\if :{?solo_definir}
\else
  select pg_temp.comprobar_auth_sin_nulos();
\endif
