-- Enlaces para dar: aislamiento entre iglesias, permiso de edicion y validacion de la direccion.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then
    raise exception 'Este script no se ejecuta en una base con iglesias reales';
  end if;
end $$;

create or replace function pg_temp.igual(obtenido int, esperado int, msg text) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLO: % (esperado %, obtenido %)', msg, esperado, obtenido; end if;
  raise notice 'OK: %', msg;
end $$;
grant execute on function pg_temp.igual(int, int, text) to authenticated, service_role;

insert into auth.users (id) values ('e0000000-0000-0000-0000-000000000001'), ('e0000000-0000-0000-0000-000000000002'), ('e0000000-0000-0000-0000-000000000003');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('16000000-0000-0000-0000-00000000000a', 'Prueba D1', 'prueba-d1', 'ES', 'Sevilla', 'premium'),
  ('16000000-0000-0000-0000-00000000000b', 'Prueba D2', 'prueba-d2', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values
  ('e0000000-0000-0000-0000-000000000001', '16000000-0000-0000-0000-00000000000a', 'S', 'Uno', 's@d1.test', 'propietario', true),
  ('e0000000-0000-0000-0000-000000000002', '16000000-0000-0000-0000-00000000000a', 'M', 'Dos', 'm@d1.test', 'miembro', true),
  ('e0000000-0000-0000-0000-000000000003', '16000000-0000-0000-0000-00000000000b', 'S', 'Tres', 's@d2.test', 'propietario', true);

insert into public.enlaces_dar (iglesia_id, tipo, url) values
  ('16000000-0000-0000-0000-00000000000a', 'diezmo', 'https://dar.d1.test/diezmo'),
  ('16000000-0000-0000-0000-00000000000b', 'diezmo', 'https://dar.d2.test/diezmo');

-- Una direccion que no es https o con espacios se rechaza
do $$ begin
  begin
    insert into public.enlaces_dar (iglesia_id, tipo, url) values ('16000000-0000-0000-0000-00000000000a', 'ofrenda', 'http://inseguro.test');
    raise exception 'FALLO: se acepto una direccion http';
  exception when check_violation then raise notice 'OK: se rechaza http'; end;
  begin
    insert into public.enlaces_dar (iglesia_id, tipo, url) values ('16000000-0000-0000-0000-00000000000a', 'ofrenda', 'javascript:alert(1)');
    raise exception 'FALLO: se acepto javascript:';
  exception when check_violation then raise notice 'OK: se rechaza javascript:'; end;
end $$;

-- Miembro de la iglesia 1: ve solo los enlaces de su iglesia y no puede cambiarlos
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e0000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.igual((select count(*)::int from public.enlaces_dar), 1, 'el miembro ve solo los enlaces de su iglesia');
do $$ declare n int; begin
  update public.enlaces_dar set url = 'https://otro.test';
  get diagnostics n = row_count;
  perform pg_temp.igual(n, 0, 'el miembro no puede editar');
end $$;
do $$ begin
  begin
    insert into public.enlaces_dar (iglesia_id, tipo, url) values ('16000000-0000-0000-0000-00000000000a', 'donacion', 'https://x.test');
    raise exception 'FALLO: el miembro pudo crear';
  exception when insufficient_privilege then raise notice 'OK: el miembro no puede crear'; end;
end $$;

-- Propietario de la iglesia 1: edita los suyos pero no los de otra iglesia
select set_config('request.jwt.claims', '{"sub":"e0000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
insert into public.enlaces_dar (iglesia_id, tipo, url) values ('16000000-0000-0000-0000-00000000000a', 'donacion', 'https://dar.d1.test/donar');
select pg_temp.igual((select count(*)::int from public.enlaces_dar), 2, 'el propietario crea y ve sus dos enlaces');
do $$ declare n int; begin
  update public.enlaces_dar set url = 'https://dar.d1.test/nuevo' where tipo = 'diezmo';
  get diagnostics n = row_count;
  perform pg_temp.igual(n, 1, 'el propietario edita solo el suyo');
end $$;
do $$ begin
  begin
    insert into public.enlaces_dar (iglesia_id, tipo, url) values ('16000000-0000-0000-0000-00000000000b', 'ofrenda', 'https://x.test');
    raise exception 'FALLO: creo en otra iglesia';
  exception when insufficient_privilege then raise notice 'OK: no crea en otra iglesia'; end;
end $$;

rollback;
