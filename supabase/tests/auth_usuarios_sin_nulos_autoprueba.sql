-- Autoprueba de la comprobacion de NULL en auth.users: simula en una transaccion las columnas reales de GoTrue.
\set ON_ERROR_STOP on
\set solo_definir 1
begin;
\i tests/auth_usuarios_sin_nulos.sql
do $$
declare r text;
begin
  -- Sin las columnas de GoTrue se omite
  r := pg_temp.comprobar_auth_sin_nulos();
  if r not like 'OMITIDO%' then raise exception 'FALLO: debia omitirse en la base local (%)', r; end if;
  raise notice 'OK: en la base local sin columnas de GoTrue se omite';
end $$;
alter table auth.users add column confirmation_token varchar(255), add column email_change varchar(255), add column phone_change varchar(255);
insert into auth.users (id) values ('0a000000-0000-0000-0000-000000000001');   -- cuenta creada por SQL: las columnas quedan NULL
do $$
begin
  begin
    perform pg_temp.comprobar_auth_sin_nulos();
  exception when others then
    if sqlerrm like 'FALLO: auth.users tiene NULL%confirmation_token:1%email_change:1%phone_change:1%' then
      raise notice 'OK: una cuenta creada por SQL con NULL se detecta, con el recuento por columna y sin datos personales'; return;
    end if;
    raise exception 'FALLO: error inesperado %', sqlerrm;
  end;
  raise exception 'FALLO: no se detecto el NULL';
end $$;
update auth.users set confirmation_token = '', email_change = '', phone_change = '' where id = '0a000000-0000-0000-0000-000000000001';
do $$
declare r text;
begin
  r := pg_temp.comprobar_auth_sin_nulos();
  if r <> 'OK: ninguna de las 3 columnas de texto de auth.users tiene NULL' then raise exception 'FALLO: %', r; end if;
  raise notice 'OK: con cadenas vacias en lugar de NULL pasa';
end $$;
rollback;
