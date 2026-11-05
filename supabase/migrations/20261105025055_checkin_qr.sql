-- Registro de asistencia por QR. Cada evento puede tener un enlace secreto (evento_checkin) que abre
-- una pagina publica donde una persona se registra desde su movil. Los registros nuevos entran como
-- miembros con su seguimiento de 72 horas abierto; los que ya existen solo marcan asistencia.
-- Medidas: enlace de 256 bits que se pausa o regenera, ventana de tiempo, tope de registros por
-- evento, limite por dispositivo (solo huella de la IP), y respuesta identica para nuevos y existentes.
-- Las funciones solo las ejecuta el servidor (service_role), a traves de la funcion de borde checkin-evento.

create table public.evento_checkin (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  evento_id uuid not null,
  token text not null unique default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '')
    check (token ~ '^[0-9a-f]{64}$'),
  activo boolean not null default true,
  abre_en timestamptz,
  cierra_en timestamptz,
  max_registros integer not null default 300 check (max_registros between 1 and 2000),
  created_at timestamptz not null default now(),
  unique (evento_id),
  check (abre_en is null or cierra_en is null or cierra_en > abre_en),
  constraint evento_checkin_evento_fk foreign key (iglesia_id, evento_id) references public.eventos (iglesia_id, id) on delete cascade
);

create table public.checkin_registros (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias(id) on delete cascade,
  evento_id uuid not null,
  miembro_id uuid,
  ip_hash text not null,
  creado boolean not null,
  created_at timestamptz not null default now(),
  constraint checkin_registros_evento_fk foreign key (iglesia_id, evento_id) references public.eventos (iglesia_id, id) on delete cascade,
  constraint checkin_registros_miembro_fk foreign key (iglesia_id, miembro_id) references public.miembros (iglesia_id, id) on delete set null (miembro_id)
);
create index checkin_registros_evento_idx on public.checkin_registros (evento_id, created_at);
create index checkin_registros_ip_idx on public.checkin_registros (evento_id, ip_hash, created_at);

alter table public.evento_checkin enable row level security;
alter table public.checkin_registros enable row level security;

-- El enlace solo lo ven y lo cambian quienes gestionan eventos
create policy evento_checkin_ver on public.evento_checkin for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));
create policy evento_checkin_crear on public.evento_checkin for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));
create policy evento_checkin_editar on public.evento_checkin for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')))
  with check (iglesia_id = (select private.get_iglesia_id()));
create policy evento_checkin_borrar on public.evento_checkin for delete to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));

-- Los registros solo se leen (para las cifras); los escribe unicamente el servidor
create policy checkin_registros_ver on public.checkin_registros for select to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('eventos.gestionar')));

grant select, insert, update, delete on public.evento_checkin to authenticated;
grant select on public.checkin_registros to authenticated;
grant all on public.evento_checkin, public.checkin_registros to service_role;

-- Datos publicos de un enlace: null si no existe o esta pausado
create or replace function public.info_checkin(p_token text)
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
as $$
declare c record; v_abre timestamptz; v_cierra timestamptz; v_n integer; v_estado text;
begin
  select ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.lugar, e.cancelado, i.nombre as iglesia, i.email_contacto
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token;
  if not found or not c.activo or c.cancelado then return null; end if;
  v_abre := coalesce(c.abre_en, c.inicia_en - interval '2 hours');
  v_cierra := coalesce(c.cierra_en, coalesce(c.termina_en, c.inicia_en + interval '6 hours') + interval '1 hour');
  select count(*) into v_n from public.checkin_registros where evento_id = c.evento_id;
  v_estado := case when now() < v_abre or now() > v_cierra then 'cerrado' when v_n >= c.max_registros then 'lleno' else 'abierto' end;
  -- Fuera de plazo solo se dice el estado y la iglesia: no se adelanta nada del evento
  if v_estado <> 'abierto' then return jsonb_build_object('estado', v_estado, 'iglesia', c.iglesia); end if;
  return jsonb_build_object('estado', v_estado, 'iglesia', c.iglesia, 'contacto', c.email_contacto,
    'evento', c.titulo, 'inicia_en', c.inicia_en, 'lugar', c.lugar);
end;
$$;

-- Registra una persona. Devuelve: ok_nuevo, ok_existente, cerrado, lleno, limite o no_valido.
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
begin
  select ec.iglesia_id, ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.casa_oracion_id, e.cancelado
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token;
  if not found or not c.activo or c.cancelado then return 'no_valido'; end if;

  v_abre := coalesce(c.abre_en, c.inicia_en - interval '2 hours');
  v_cierra := coalesce(c.cierra_en, coalesce(c.termina_en, c.inicia_en + interval '6 hours') + interval '1 hour');
  if now() < v_abre or now() > v_cierra then return 'cerrado'; end if;

  select count(*) into v_n from public.checkin_registros where evento_id = c.evento_id;
  if v_n >= c.max_registros then return 'lleno'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and ip_hash = p_ip_hash and created_at > now() - interval '10 minutes';
  if v_n >= 5 then return 'limite'; end if;
  select count(*) into v_n from public.checkin_registros
    where evento_id = c.evento_id and created_at > now() - interval '1 minute';
  if v_n >= 40 then return 'limite'; end if;

  -- Ya existe si coincide el correo, o el telefono y el nombre completo juntos (un telefono de familia no fusiona personas)
  v_dig := regexp_replace(coalesce(p_telefono, ''), '\D', '', 'g');
  select m.id into v_miembro from public.miembros m
   where m.iglesia_id = c.iglesia_id and m.activo
     and ((coalesce(p_email, '') <> '' and lower(m.email) = lower(p_email))
       or (length(v_dig) >= 7
           and right(regexp_replace(coalesce(m.telefono, ''), '\D', '', 'g'), 9) = right(v_dig, 9)
           and lower(btrim(m.nombre)) = lower(btrim(p_nombre))
           and lower(btrim(m.apellido)) = lower(btrim(p_apellido))))
   order by m.created_at
   limit 1;

  if v_miembro is null then
    insert into public.miembros (iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, activo, notas)
      values (c.iglesia_id, btrim(p_nombre), btrim(p_apellido), nullif(btrim(coalesce(p_email, '')), ''), btrim(p_telefono),
              c.casa_oracion_id, true, 'Registrado por QR en el evento: ' || c.titulo)
      returning id into v_miembro;
    v_nuevo := true;
    insert into public.consolidaciones (iglesia_id, miembro_id, fecha_conversion, notas)
      values (c.iglesia_id, v_miembro, now(), 'Registro por QR en el evento: ' || c.titulo);
  end if;

  insert into public.asistencia_evento (iglesia_id, evento_id, miembro_id, presente)
    values (c.iglesia_id, c.evento_id, v_miembro, true)
    on conflict (evento_id, miembro_id) do update set presente = true;
  insert into public.checkin_registros (iglesia_id, evento_id, miembro_id, ip_hash, creado)
    values (c.iglesia_id, c.evento_id, v_miembro, p_ip_hash, v_nuevo);

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.info_checkin(text), public.registrar_checkin(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.info_checkin(text), public.registrar_checkin(text, text, text, text, text, text) to service_role;
