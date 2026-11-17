-- Vive ADN, traspaso al proyecto real, archivo 3 de 19: tramo 2 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regprocedure('public.adn_telefono_canonico(text)') is not null then raise notice 'Tramo 2 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('public.adn_tablas_exportables()') is not null) then raise exception 'Falta aplicar antes el tramo 1 de 15: no se sigue.'; end if;
  execute $cuerpo$


create or replace function public.adn_exportar_paquete(p_iglesia uuid)
returns jsonb language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  -- Columnas que nunca salen: secretos y marcas internas del borrado suave
  secretos constant text[] := array['token', 'token_hash', 'ip_hash', 'adn_borrada_en', 'adn_borrada_por', 'adn_estado_previo'];
  r record;
  cols jsonb;
  nombres text[];
  omitidas text[];
  filas jsonb;
  csv text;
  tablas jsonb := '{}'::jsonb;
  csvs jsonb := '{}'::jsonb;
  man jsonb := '[]'::jsonb;
  total bigint := 0;
  ig jsonb;
begin
  if not exists (select 1 from public.iglesias where id = p_iglesia) then
    raise exception 'La iglesia no existe';
  end if;

  -- Orden de carga: una tabla va despues de las que referencia (las autorreferencias no cuentan)
  for r in
    with recursive tabla as (select x.nombre, x.filtro from public.adn_tablas_exportables() x),
    fk as (
      select co.relname::text collate "default" as origen, cd.relname::text collate "default" as destino
      from pg_constraint c
      join pg_class co on co.oid = c.conrelid join pg_class cd on cd.oid = c.confrelid
      where c.contype = 'f' and c.connamespace = 'public'::regnamespace and c.conrelid <> c.confrelid
    ),
    niv(nombre, n) as (
      select nombre, 0 from tabla
      union
      select fk.origen, niv.n + 1 from niv join fk on fk.destino = niv.nombre
      where fk.origen in (select nombre from tabla) and niv.n < 50
    )
    select t.nombre, t.filtro, max(niv.n) as nivel
    from tabla t join niv on niv.nombre = t.nombre
    group by t.nombre, t.filtro
    order by max(niv.n), t.nombre
  loop
    select coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text <> all (secretos)), '{}'),
           coalesce(array_agg(a.attname::text order by a.attnum) filter (where a.attname::text = any (secretos)), '{}'),
           coalesce(jsonb_agg(jsonb_build_object('nombre', a.attname, 'tipo', format_type(a.atttypid, a.atttypmod), 'obligatoria', a.attnotnull)
                              order by a.attnum) filter (where a.attname::text <> all (secretos)), '[]')
      into nombres, omitidas, cols
      from pg_attribute a
      where a.attrelid = ('public.' || quote_ident(r.nombre))::regclass and a.attnum > 0 and not a.attisdropped;

    -- Filas en un orden estable para que dos exportaciones iguales den el mismo resultado
    execute format(
      'select coalesce(jsonb_agg(public.adn_fila_exportable(to_jsonb(t), $2) order by to_jsonb(t)::text), ''[]''::jsonb) from public.%I t where %s',
      r.nombre, r.filtro) into filas using p_iglesia, omitidas;

    csv := (select string_agg(public.adn_csv_campo(to_jsonb(c.n)), ',' order by c.ord) from unnest(nombres) with ordinality c(n, ord))
           || E'\r\n'
           || coalesce((
                select string_agg(
                  (select string_agg(public.adn_csv_campo(e.f -> c.n), ',' order by c.ord) from unnest(nombres) with ordinality c(n, ord)),
                  E'\r\n' order by e.fo)
                from jsonb_array_elements(filas) with ordinality e(f, fo)
              ) || E'\r\n', '');

    if r.nombre = 'iglesias' then ig := filas -> 0; end if;
    csvs := csvs || jsonb_build_object(r.nombre, csv);
    -- La iglesia va en su propio campo, no dentro de `tablas`, igual que en exportar_iglesia
    if r.nombre <> 'iglesias' then tablas := tablas || jsonb_build_object(r.nombre, filas); end if;
    total := total + jsonb_array_length(filas);
    man := man || jsonb_build_array(jsonb_build_object(
      'nombre', r.nombre, 'orden_carga', r.nivel, 'archivo_csv', 'csv/' || r.nombre || '.csv',
      'filas', jsonb_array_length(filas), 'columnas', cols, 'omitidas', to_jsonb(omitidas),
      'huella', (select md5(coalesce(string_agg(md5(e.f::text), ',' order by md5(e.f::text)), '')) from jsonb_array_elements(filas) e(f)),
      'md5_csv', md5(csv)));
  end loop;

  return jsonb_build_object(
    'formato', 'viveadn-exportacion-2',
    'exportado_en', now(),
    'iglesia', ig,
    'tablas', tablas,
    'csv', csvs,
    'manifiesto', jsonb_build_object(
      'formato', 'viveadn-exportacion-2', 'iglesia_id', p_iglesia, 'exportado_en', now(),
      'codificacion', 'UTF-8 sin BOM', 'separador', ',', 'fin_de_linea', 'CRLF',
      'nulos', 'campo vacio sin comillas; la cadena vacia va entre comillas ("")',
      'total_filas', total, 'tablas', man));
end $$;

-- Recalcula en la base actual las cifras del manifiesto, tabla a tabla, para la iglesia del manifiesto.
-- Devuelve una fila por tabla: filas y huella esperadas frente a las cargadas.
create or replace function public.adn_verificar_carga(p_manifiesto jsonb)
returns table (tabla text, filas_esperadas bigint, filas_cargadas bigint, huella_ok boolean, ok boolean)
language plpgsql set search_path to '' set timezone to 'UTC' as $$
declare
  t jsonb;
  f record;
  filas bigint;
  huella text;
  omitidas text[];
  iglesia uuid := (p_manifiesto ->> 'iglesia_id')::uuid;
begin
  for t in select * from jsonb_array_elements(p_manifiesto -> 'tablas') loop
    select * into f from public.adn_tablas_exportables() x where x.nombre = t ->> 'nombre';
    if not found then
      tabla := t ->> 'nombre'; filas_esperadas := (t ->> 'filas')::bigint; filas_cargadas := 0; huella_ok := false; ok := false;
      return next; continue;
    end if;
    select coalesce(array_agg(v), '{}') into omitidas from jsonb_array_elements_text(t -> 'omitidas') v;
    execute format(
      'select count(*), md5(coalesce(string_agg(md5(public.adn_fila_exportable(to_jsonb(x), $2)::text), '','' order by md5(public.adn_fila_exportable(to_jsonb(x), $2)::text)), '''')) from public.%I x where %s',
      f.nombre, f.filtro) into filas, huella using iglesia, omitidas;
    tabla := f.nombre;
    filas_esperadas := (t ->> 'filas')::bigint;
    filas_cargadas := filas;
    huella_ok := huella = (t ->> 'huella');
    ok := filas = filas_esperadas and huella_ok;
    return next;
  end loop;
end $$;

revoke all on function
  public.adn_csv_campo(jsonb), public.adn_fila_exportable(jsonb, text[]), public.adn_tablas_exportables(), public.adn_exportar_paquete(uuid), public.adn_verificar_carga(jsonb)
  from public, anon, authenticated;
grant execute on function
  public.adn_csv_campo(jsonb), public.adn_fila_exportable(jsonb, text[]), public.adn_tablas_exportables(), public.adn_exportar_paquete(uuid), public.adn_verificar_carga(jsonb)
  to service_role;
-- ===== 20261111140000_adn_importar_contactos (origen sha256 37b24f172370, compilado sha256 41a2275dd60c) =====
-- Importador de contactos (formato Google Contacts): tabla de datos de contacto adicionales y funcion de
-- importacion atomica, con deduplicacion por correo y filtros que no dependen del navegador.
-- Reversion: supabase/reversiones/20261111140000_adn_importar_contactos.down.sql.
--
-- `miembros` guarda un correo y un telefono. Un contacto de Google puede traer dos correos, tres telefonos,
-- direcciones y etiquetas: lo que no cabe en `miembros` va a `adn_miembro_contactos`, una fila por dato.
-- Nunca se importan contraseñas: la funcion solo acepta una lista cerrada de campos y descarta cualquier nota que
-- parezca contener una clave, aunque el archivo llegue de un cliente modificado.

create table public.adn_miembro_contactos (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias (id) on delete cascade,
  miembro_id uuid not null,
  tipo text not null check (tipo in ('correo', 'telefono', 'direccion', 'etiqueta')),
  etiqueta text check (etiqueta is null or char_length(etiqueta) <= 60),
  valor text not null check (char_length(valor) between 1 and 500),
  orden smallint not null default 0,
  created_at timestamptz not null default now(),
  constraint adn_miembro_contactos_miembro_fk foreign key (iglesia_id, miembro_id)
    references public.miembros (iglesia_id, id) on delete cascade,
  constraint adn_miembro_contactos_unico unique (miembro_id, tipo, valor)
);
create index adn_miembro_contactos_miembro_idx on public.adn_miembro_contactos (iglesia_id, miembro_id);
create index adn_miembro_contactos_valor_idx on public.adn_miembro_contactos (iglesia_id, tipo, lower(valor));

grant select, insert, update, delete on public.adn_miembro_contactos to authenticated, service_role;
alter table public.adn_miembro_contactos enable row level security;

-- Se ve lo que se ve del miembro (la politica de miembros se aplica a la subconsulta); se escribe con los
-- permisos de miembros. Siempre dentro de la iglesia de quien pregunta.
create policy adn_miembro_contactos_ver on public.adn_miembro_contactos for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id())
         and exists (select 1 from public.miembros m where m.id = miembro_id and m.iglesia_id = iglesia_id));
create policy adn_miembro_contactos_crear on public.adn_miembro_contactos for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id())
              and ((select private.tiene_permiso('miembros.crear')) or (select private.tiene_permiso('miembros.editar'))));
create policy adn_miembro_contactos_editar on public.adn_miembro_contactos for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('miembros.editar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy adn_miembro_contactos_borrar on public.adn_miembro_contactos for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('miembros.editar')));

-- Telefono en forma canonica: solo digitos y un + inicial. Es la misma que calcula la web
create or replace function public.adn_telefono_canonico(p_valor text)
returns text language sql immutable set search_path to '' as $$
  select case when left(btrim(coalesce(p_valor, '')), 1) = '+'
              then '+' || regexp_replace(substr(btrim(p_valor), 2), '[^0-9]', '', 'g')
              else regexp_replace(coalesce(p_valor, ''), '[^0-9]', '', 'g') end
$$;
revoke all on function public.adn_telefono_canonico(text) from public, anon;
grant execute on function public.adn_telefono_canonico(text) to authenticated, service_role;
$cuerpo$;
end $tramo$;
select 'ok: tramo 2 de 15 aplicado' as resultado, (to_regprocedure('public.adn_telefono_canonico(text)') is not null) as comprobado;
