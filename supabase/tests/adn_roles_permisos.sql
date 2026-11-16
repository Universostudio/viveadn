-- Permisos de cada rol de sistema: huella md5 de la lista ordenada. scripts/probar-acceso.mts usa las mismas huellas para el menú y las rutas:
-- si alguien cambia los permisos de un rol, fallan las dos pruebas y hay que actualizar la tabla de esa prueba y docs/MAPA-ACCESOS.md.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if exists (select 1 from public.iglesias where slug not like 'prueba-%') then
    raise exception 'Este script no se ejecuta en una base con iglesias reales';
  end if;
end $$;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('a9a00000-0000-0000-0000-00000000000a', 'Prueba Roles', 'prueba-roles', 'ES', 'Sevilla', 'premium');
do $$
declare
  r record;
  hallada text; total int;
begin
  for r in select * from (values
  ('administrador', '94f21315898a062f51439b534f8990c5', 45),
  ('coadministrador', '280bd9da3c8d9f210221bd0286847eda', 31),
  ('colaborador', '28bdeb85339d0a520fff40c52bbfcfbc', 9),
  ('consolidador', '4416dc8d48acd52a09d250e0ad8ffae5', 6),
  ('lider_casa', 'ea7edaf4267bfde9028b96471cafb529', 7),
  ('lider_escuela', '8cda70fc2cb1a1e452c2b6665932ef7b', 9),
  ('lider_zona', '1e565d6c7c5747edd5b0d0f8332662f1', 9),
  ('miembro', '9bb5ce6c79fb6454d037f4cead6b5dfb', 1),
  ('propietario', 'd41d8cd98f00b204e9800998ecf8427e', 0)
  ) as v(clave, huella, n) loop
    select md5(coalesce(string_agg(rp.permiso, ',' order by rp.permiso collate "C"), '')), count(rp.permiso)::int into hallada, total
    from public.roles ro left join public.rol_permisos rp on rp.rol_id = ro.id
    where ro.iglesia_id = 'a9a00000-0000-0000-0000-00000000000a' and ro.clave = r.clave;
    if hallada is distinct from r.huella then
      raise exception 'FALLO: los permisos del rol % cambiaron (huella %, esperada %, % permisos, esperados %)', r.clave, hallada, r.huella, total, r.n;
    end if;
    raise notice 'OK: permisos del rol % sin cambios (% permisos)', r.clave, r.n;
  end loop;
  if (select count(*) from public.roles where iglesia_id = 'a9a00000-0000-0000-0000-00000000000a') <> 9 then
    raise exception 'FALLO: una iglesia nueva debe nacer con 9 roles de sistema';
  end if;
  raise notice 'OK: una iglesia nueva nace con los 9 roles de sistema';
end $$;
rollback;
