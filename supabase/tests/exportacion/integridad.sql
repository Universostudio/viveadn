-- Comprueba que en la base no queda ninguna clave foranea colgando (las cargas van sin disparadores, asi que
-- la propia base no las ha comprobado). Falla con la lista de las que no se cumplen.
\set ON_ERROR_STOP on
do $$
declare r record; n bigint; malas text[] := '{}'; revisadas int := 0;
begin
  for r in
    select c.conname, c.conrelid::regclass::text as hijo, c.confrelid::regclass::text as padre,
      (select string_agg(format('h.%I = p.%I', a.attname, b.attname), ' and ' order by k.ord)
         from unnest(c.conkey, c.confkey) with ordinality k(ck, pk, ord)
         join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.ck
         join pg_attribute b on b.attrelid = c.confrelid and b.attnum = k.pk) as cond,
      (select string_agg(format('h.%I is not null', a.attname), ' and ')
         from unnest(c.conkey) k(ck) join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.ck) as todas
    from pg_constraint c
    where c.contype = 'f' and c.connamespace = 'public'::regnamespace
  loop
    execute format('select count(*) from %s h where %s and not exists (select 1 from %s p where %s)', r.hijo, r.todas, r.padre, r.cond) into n;
    revisadas := revisadas + 1;
    if n > 0 then malas := malas || format('%s: %s filas sin padre (%s -> %s)', r.conname, n, r.hijo, r.padre); end if;
  end loop;
  if array_length(malas, 1) > 0 then raise exception E'INTEGRIDAD: % clave(s) foranea(s) incumplida(s)\n%', array_length(malas, 1), array_to_string(malas, E'\n'); end if;
  raise notice 'OK: las % claves foraneas se cumplen en la base cargada', revisadas;
end $$;
