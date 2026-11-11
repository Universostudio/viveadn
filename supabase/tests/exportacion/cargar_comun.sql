-- Piezas comunes de los cargadores de prueba (JSON y CSV). Solo para pruebas: viven en pg_temp.
-- Aflojar y rellenar las columnas NOT NULL omitidas por la exportacion (secretos): se regeneran con valores nuevos
create temp table if not exists omitidas_nn (tabla text, columna text);
create or replace function pg_temp.preparar(p_tabla text, p_omitidas text[]) returns void language plpgsql as $$
declare c text;
begin
  foreach c in array p_omitidas loop
    if exists (select 1 from pg_attribute a where a.attrelid = ('public.' || quote_ident(p_tabla))::regclass and a.attname = c and a.attnotnull) then
      execute format('alter table public.%I alter column %I drop not null', p_tabla, c);
      insert into omitidas_nn values (p_tabla, c);
    end if;
  end loop;
end $$;
create or replace function pg_temp.rellenar(p_tabla text) returns void language plpgsql as $$
declare r record;
begin
  for r in select columna from omitidas_nn where tabla = p_tabla loop
    -- 64 caracteres hexadecimales de dos UUID v4 (generador criptografico de la base)
    execute format($f$update public.%1$I set %2$I = replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '') where %2$I is null$f$, p_tabla, r.columna);
    execute format('alter table public.%I alter column %I set not null', p_tabla, r.columna);
  end loop;
  delete from omitidas_nn where tabla = p_tabla;
end $$;
-- En una base de Supabase las cuentas de acceso se vuelven a invitar; aqui basta con los identificadores que exige la FK
create or replace function pg_temp.usuarios_de_acceso() returns void language plpgsql as $$
begin
  insert into auth.users (id) select id from public.perfiles on conflict do nothing;
end $$;
-- Las columnas de identidad conservan los valores cargados: la secuencia debe seguir despues del mayor
create or replace function pg_temp.secuencias() returns void language plpgsql as $$
declare r record;
begin
  for r in
    select c.relname, a.attname, pg_get_serial_sequence('public.' || quote_ident(c.relname), a.attname) as seq
    from pg_class c join pg_attribute a on a.attrelid = c.oid
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and a.attidentity <> '' and not a.attisdropped
  loop
    execute format('select setval(%L, greatest(coalesce((select max(%I) from public.%I), 0), 1), (select max(%I) is not null from public.%I))', r.seq, r.attname, r.relname, r.attname, r.relname);
  end loop;
end $$;
