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

-- Importacion atomica de un lote de hasta 1000 contactos ya limpiados por la web. Cada elemento:
--   { nombre, apellido, email, telefono, fecha_nacimiento, notas,
--     contactos: [ { tipo: correo|telefono|direccion|etiqueta, etiqueta, valor } ] }
-- Se ejecuta con los permisos de quien llama (seguridad por filas, limites del plan y disparadores incluidos).
-- Duplicados, en este orden: un correo ya existente (principal o adicional) en la iglesia; si el contacto no tiene
-- correo, un telefono ya existente; si no tiene ni correo ni telefono, el mismo nombre. Tambien entre las filas del lote.
-- Devuelve conteos. Si algo falla (p. ej. el limite del plan), no se importa nada de ese lote.
create or replace function public.adn_importar_miembros(p_filas jsonb, p_origen text default 'google')
returns jsonb language plpgsql set search_path to '' as $$
declare
  ig uuid := private.get_iglesia_id();
  hoy date := (now() at time zone 'UTC')::date;
  f jsonb;
  c jsonb;
  nuevo uuid;
  nombre text; apellido text; email text; tel text; nac date; notas text;
  correos text[]; telefonos text[];
  clave_nombre text;
  existe boolean;
  n_ok int := 0; n_dup_correo int := 0; n_dup_tel int := 0; n_dup_nombre int := 0; n_invalidas int := 0; n_notas int := 0;
  extra_tipo text; extra_valor text; extra_etiqueta text; extra_tel text;
  orden int;
  -- Una nota que parece guardar una clave no se importa
  clave_re constant text := '\m(contrase(ñ|n)a|password|passwd|passcode|clave|pin|secreto?|secret)\s*[:=]';
  -- En este lote, para detectar repetidos entre sus propias filas
  vistos_correos text[] := '{}'; vistos_tel text[] := '{}'; vistos_nombre text[] := '{}';
begin
  if ig is null then raise exception 'ADN_SIN_IGLESIA'; end if;
  if not (select private.tiene_permiso('miembros.importar')) then raise exception 'ADN_SIN_PERMISO'; end if;
  if coalesce((select modo_alias from public.iglesias where id = ig), false) then raise exception 'ADN_MODO_ALIAS'; end if;
  if p_origen is null or p_origen !~ '^[a-z0-9_-]{1,30}$' then raise exception 'ADN_ORIGEN_INVALIDO'; end if;
  if jsonb_typeof(p_filas) is distinct from 'array' or jsonb_array_length(p_filas) > 1000 then raise exception 'ADN_LOTE_INVALIDO'; end if;

  for f in select value from jsonb_array_elements(p_filas) loop
    nombre := left(btrim(coalesce(f ->> 'nombre', '')), 100);
    apellido := left(btrim(coalesce(f ->> 'apellido', '')), 100);
    if nombre = '' then n_invalidas := n_invalidas + 1; continue; end if;

    -- Correo principal y adicionales, en minusculas y con forma de correo
    correos := '{}';
    email := lower(btrim(coalesce(f ->> 'email', '')));
    if email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(email) <= 254 then correos := array[email]; else email := null; end if;
    -- Telefono principal y adicionales, solo digitos y un + inicial, entre 7 y 15 digitos
    telefonos := '{}';
    tel := public.adn_telefono_canonico(f ->> 'telefono');
    if tel ~ '^\+?[0-9]{7,15}$' and tel !~ '^\+?(.)\1+$' then telefonos := array[tel]; else tel := null; end if;
    for c in select value from jsonb_array_elements(case when jsonb_typeof(f -> 'contactos') = 'array' then f -> 'contactos' else '[]'::jsonb end) loop
      if c ->> 'tipo' = 'correo' then
        extra_valor := lower(btrim(coalesce(c ->> 'valor', '')));
        if extra_valor ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(extra_valor) <= 254 and not extra_valor = any (correos) then correos := correos || extra_valor; end if;
      elsif c ->> 'tipo' = 'telefono' then
        extra_tel := public.adn_telefono_canonico(c ->> 'valor');
        if extra_tel ~ '^\+?[0-9]{7,15}$' and extra_tel !~ '^\+?(.)\1+$' and not extra_tel = any (telefonos) then telefonos := telefonos || extra_tel; end if;
      end if;
    end loop;

    -- Duplicados
    existe := false;
    if array_length(correos, 1) > 0 then
      if correos && vistos_correos
         or exists (select 1 from public.miembros m where lower(m.email) = any (correos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'correo' and lower(x.valor) = any (correos)) then
        n_dup_correo := n_dup_correo + 1; continue;
      end if;
    elsif array_length(telefonos, 1) > 0 then
      if telefonos && vistos_tel
         or exists (select 1 from public.miembros m where public.adn_telefono_canonico(m.telefono) = any (telefonos))
         or exists (select 1 from public.adn_miembro_contactos x where x.tipo = 'telefono' and public.adn_telefono_canonico(x.valor) = any (telefonos)) then
        n_dup_tel := n_dup_tel + 1; continue;
      end if;
    else
      clave_nombre := lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
      if clave_nombre = any (vistos_nombre)
         or exists (select 1 from public.miembros m where lower(regexp_replace(btrim(m.nombre || ' ' || m.apellido), '\s+', ' ', 'g')) = clave_nombre) then
        n_dup_nombre := n_dup_nombre + 1; continue;
      end if;
    end if;

    -- Fecha de nacimiento: solo una fecha real entre 1900 y hoy
    nac := null;
    begin
      nac := nullif(btrim(coalesce(f ->> 'fecha_nacimiento', '')), '')::date;
      if nac < date '1900-01-01' or nac > hoy then nac := null; end if;
    exception when others then nac := null;
    end;

    notas := nullif(left(btrim(coalesce(f ->> 'notas', '')), 1000), '');
    if notas ~* clave_re then notas := null; n_notas := n_notas + 1; end if;

    nuevo := gen_random_uuid();
    insert into public.miembros (id, nombre, apellido, email, telefono, fecha_nacimiento, notas, activo)
    values (nuevo, nombre, apellido, correos[1], telefonos[1], nac, notas, true);

    -- Datos adicionales: el segundo correo en adelante, el segundo telefono en adelante, direcciones y etiquetas
    orden := 0;
    foreach extra_valor in array coalesce(correos[2:array_length(correos, 1)], '{}') loop
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, valor, orden) values (nuevo, 'correo', extra_valor, orden) on conflict do nothing;
    end loop;
    foreach extra_valor in array coalesce(telefonos[2:array_length(telefonos, 1)], '{}') loop
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, valor, orden) values (nuevo, 'telefono', extra_valor, orden) on conflict do nothing;
    end loop;
    for c in select value from jsonb_array_elements(case when jsonb_typeof(f -> 'contactos') = 'array' then f -> 'contactos' else '[]'::jsonb end) loop
      extra_tipo := c ->> 'tipo';
      continue when extra_tipo not in ('direccion', 'etiqueta');
      extra_valor := left(btrim(coalesce(c ->> 'valor', '')), 500);
      continue when extra_valor = '';
      extra_etiqueta := nullif(left(btrim(coalesce(c ->> 'etiqueta', '')), 60), '');
      orden := orden + 1;
      insert into public.adn_miembro_contactos (miembro_id, tipo, etiqueta, valor, orden)
      values (nuevo, extra_tipo, extra_etiqueta, extra_valor, orden) on conflict do nothing;
    end loop;
    -- Marca de la importacion, para poder encontrar (y deshacer) lo que entro de una vez
    insert into public.adn_miembro_contactos (miembro_id, tipo, etiqueta, valor, orden)
    values (nuevo, 'etiqueta', 'importacion', 'Importado ' || hoy::text || ' (' || p_origen || ')', 999) on conflict do nothing;

    vistos_correos := vistos_correos || correos;
    vistos_tel := vistos_tel || telefonos;
    if array_length(correos, 1) is null and array_length(telefonos, 1) is null then
      vistos_nombre := vistos_nombre || lower(regexp_replace(btrim(nombre || ' ' || apellido), '\s+', ' ', 'g'));
    end if;
    n_ok := n_ok + 1;
  end loop;

  return jsonb_build_object('importados', n_ok, 'duplicados_correo', n_dup_correo, 'duplicados_telefono', n_dup_tel,
                            'duplicados_nombre', n_dup_nombre, 'invalidas', n_invalidas, 'notas_descartadas', n_notas);
end $$;

revoke all on function public.adn_importar_miembros(jsonb, text) from public, anon;
grant execute on function public.adn_importar_miembros(jsonb, text) to authenticated, service_role;
