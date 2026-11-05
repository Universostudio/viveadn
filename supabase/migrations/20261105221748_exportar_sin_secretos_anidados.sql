-- La exportacion tambien quita los secretos que viven dentro de `detalle` (p. ej. el ip_hash
-- que guarda el registro por autoservicio en la auditoria), no solo los del primer nivel.
create or replace function public.exportar_iglesia(p_iglesia uuid)
returns jsonb language plpgsql set search_path to '' as $$
declare
  r record;
  filas jsonb;
  tablas jsonb := '{}'::jsonb;
  secretos constant text[] := array['token', 'token_hash', 'ip_hash'];
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;
  for r in
    select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
      and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and a.attnum > 0 and not a.attisdropped)
    order by c.relname
  loop
    execute format(
      'select coalesce(jsonb_agg(case when jsonb_typeof(to_jsonb(t)->''detalle'') = ''object'' '
      || 'then jsonb_set(to_jsonb(t) - %1$L::text[], ''{detalle}'', (to_jsonb(t)->''detalle'') - %1$L::text[]) '
      || 'else to_jsonb(t) - %1$L::text[] end), ''[]''::jsonb) from public.%2$I t where t.iglesia_id = $1',
      secretos, r.relname)
      into filas using p_iglesia;
    tablas := tablas || jsonb_build_object(r.relname, filas);
  end loop;
  select coalesce(jsonb_agg(to_jsonb(rp)), '[]'::jsonb) into filas
    from public.rol_permisos rp join public.roles ro on ro.id = rp.rol_id where ro.iglesia_id = p_iglesia;
  tablas := tablas || jsonb_build_object('rol_permisos', filas);
  return jsonb_build_object(
    'formato', 'viveadn-exportacion-1',
    'exportado_en', now(),
    'iglesia', (select to_jsonb(i) from public.iglesias i where i.id = p_iglesia),
    'tablas', tablas
  );
end $$;

revoke all on function public.exportar_iglesia(uuid) from public, anon, authenticated;
grant execute on function public.exportar_iglesia(uuid) to service_role;
