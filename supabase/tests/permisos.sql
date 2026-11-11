-- Comprobaciones de permisos sobre el catálogo, tras aplicar esquema y migraciones.
-- Detectan: tablas sin seguridad por filas o sin políticas, tablas nuevas sin GRANT
-- (cambio de Supabase del 30-10-2026), permisos a visitantes sin sesión, permisos por
-- defecto que expondrían objetos futuros y funciones o vistas que se salten la seguridad.
-- Falla con la lista de objetos afectados.

\set ON_ERROR_STOP on

do $$
declare
  -- Tablas que a propósito solo usa el servidor (service_role) y no tienen políticas
  solo_servidor constant text[] := array['plataforma_auditoria', 'plataforma_ajustes', 'registro_codigos', 'registro_intentos', 'adn_ciclo_auditoria', 'adn_datos_auditoria', 'adn_bajas_enlaces', 'adn_confirmaciones'];
  errores text[] := '{}';
  r record;
begin
  -- 1. Seguridad por filas activada en todas las tablas de public
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
  loop
    errores := errores || format('tabla sin seguridad por filas: %s', r.relname);
  end loop;

  -- 2. Al menos una política en cada tabla usada por la web
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
      and c.relname <> all (solo_servidor)
      and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname)
  loop
    errores := errores || format('tabla sin políticas: %s', r.relname);
  end loop;

  -- 3. GRANT explícito a authenticated y service_role en cada tabla usada por la web
  for r in
    select c.relname, c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relname <> all (solo_servidor)
  loop
    if not has_table_privilege('authenticated', r.oid, 'select') then
      errores := errores || format('tabla sin GRANT a authenticated: %s', r.relname);
    end if;
    if not has_table_privilege('service_role', r.oid, 'select') then
      errores := errores || format('tabla sin GRANT a service_role: %s', r.relname);
    end if;
  end loop;

  -- 4. Las tablas solo de servidor no se exponen a usuarios
  for r in
    select c.relname, c.oid from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = any (solo_servidor)
      and (has_table_privilege('authenticated', c.oid, 'select')
           or has_table_privilege('authenticated', c.oid, 'insert'))
  loop
    errores := errores || format('tabla solo de servidor accesible a usuarios: %s', r.relname);
  end loop;

  -- 5. Los visitantes sin sesión (anon) no tienen ningún permiso en tablas ni secuencias
  for r in
    select c.relname, c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private') and c.relkind in ('r', 'p', 'v', 'm', 'S')
      and (has_table_privilege('anon', c.oid, 'select, insert, update, delete')
           or (c.relkind = 'S' and has_sequence_privilege('anon', c.oid, 'usage, select, update')))
  loop
    errores := errores || format('anon tiene permisos en: %s', r.relname);
  end loop;

  -- 6. Ninguna función de public o private ejecutable por anon
  for r in
    select n.nspname, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and has_function_privilege('anon', p.oid, 'execute')
  loop
    errores := errores || format('anon puede ejecutar: %s.%s', r.nspname, r.proname);
  end loop;

  -- 7. Ningún permiso por defecto que exponga objetos futuros de public
  for r in
    select d.defaclobjtype, d.defaclacl::text as acl from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
    where n.nspname = 'public' and pg_get_userbyid(d.defaclrole) = 'postgres'
      and d.defaclacl::text ~ '(^|[{,])(anon|authenticated|service_role)='
  loop
    errores := errores || format('permiso por defecto de postgres en public (%s): %s', r.defaclobjtype, r.acl);
  end loop;

  -- 8. Ninguna función SECURITY DEFINER expuesta en public; las de private fijan search_path
  for r in
    select n.nspname, p.proname, p.proconfig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where p.prosecdef and n.nspname in ('public', 'private')
  loop
    if r.nspname = 'public' then
      errores := errores || format('función SECURITY DEFINER en public: %s', r.proname);
    elsif r.proconfig is null or not exists (select 1 from unnest(r.proconfig) x where x like 'search_path=%') then
      errores := errores || format('función SECURITY DEFINER sin search_path: %s.%s', r.nspname, r.proname);
    end if;
  end loop;

  -- 9. Ninguna vista de public que se salte la seguridad por filas
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('v', 'm')
      and not coalesce(c.reloptions @> array['security_invoker=true'], false)
  loop
    errores := errores || format('vista sin security_invoker: %s', r.relname);
  end loop;

  -- 10. Ninguna clave foránea simple entre dos tablas de iglesia: debe ser compuesta con iglesia_id,
  --     para que una fila nunca pueda apuntar a otra iglesia (las claves hacia iglesias son la excepción)
  for r in
    select o.relname as origen, a.attname as columna, d.relname as destino
    from pg_constraint k
    join pg_class o on o.oid = k.conrelid and o.relnamespace = 'public'::regnamespace
    join pg_class d on d.oid = k.confrelid and d.relnamespace = 'public'::regnamespace
    join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
    where k.contype = 'f' and array_length(k.conkey, 1) = 1 and d.relname <> 'iglesias'
      and exists (select 1 from pg_attribute x where x.attrelid = o.oid and x.attname = 'iglesia_id' and not x.attisdropped)
      and exists (select 1 from pg_attribute x where x.attrelid = d.oid and x.attname = 'iglesia_id' and not x.attisdropped)
  loop
    errores := errores || format('clave foránea simple entre tablas de iglesia: %s.%s -> %s (debe incluir iglesia_id)', r.origen, r.columna, r.destino);
  end loop;

  -- 11. Toda tabla de public lleva iglesia_id o esta clasificada como global. Asi la exportacion
  --     y el borrado de una iglesia no pueden dejar fuera una tabla nueva sin que CI avise.
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
      and c.relname <> all (array['iglesias', 'modulos', 'permisos', 'plan_modulos', 'planes', 'plataforma_admins',
                                  'plataforma_ajustes', 'registro_codigos', 'registro_intentos', 'rol_permisos', 'adn_ciclo_auditoria', 'adn_datos_auditoria', 'adn_consentimiento_textos'])
      and not exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and not a.attisdropped)
  loop
    errores := errores || format('la tabla %s no tiene iglesia_id ni esta clasificada como global (exportar_iglesia y borrar_iglesia no la cubririan)', r.relname);
  end loop;

  if array_length(errores, 1) > 0 then
    raise exception E'PERMISOS: % problema(s)\n%', array_length(errores, 1), array_to_string(errores, E'\n');
  end if;
  raise notice 'PERMISOS: todas las comprobaciones pasan';
end $$;

-- 10. Prueba de comportamiento: una tabla creada después de las migraciones nace sin
--     permisos para la API, como ocurrirá en Supabase desde el 30-10-2026.
begin;
create table public.prueba_tabla_nueva (id int);
do $$
begin
  if has_table_privilege('authenticated', 'public.prueba_tabla_nueva', 'select')
     or has_table_privilege('anon', 'public.prueba_tabla_nueva', 'select')
     or has_table_privilege('service_role', 'public.prueba_tabla_nueva', 'select') then
    raise exception 'PERMISOS: una tabla nueva recibe permisos por defecto';
  end if;
  raise notice 'PERMISOS: una tabla nueva nace sin permisos, como en Supabase desde el 30-10-2026';
end $$;
rollback;
