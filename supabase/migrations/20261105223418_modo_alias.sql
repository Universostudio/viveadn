-- Modo alias de la iglesia (OP72 v2): la persona se registra con un alias o ID interno, no con su identidad civil.
-- Si el dato no se guarda, no puede filtrarse ni hace falta enmascararlo. En este modo la base normaliza
-- cada miembro nuevo: el alias va en `nombre`, `apellido` queda vacio y no se guarda correo.
-- El telefono se conserva porque la llamada de las 72 horas lo necesita. Los miembros que ya existian no se tocan.

alter table public.iglesias add column modo_alias boolean not null default false;

create or replace function private.aplicar_modo_alias()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if exists (select 1 from public.iglesias i where i.id = new.iglesia_id and i.modo_alias) then
    -- En una edicion solo se toca lo que cambia, para no borrar lo que ya habia
    if tg_op = 'INSERT' or new.apellido is distinct from old.apellido then new.apellido := ''; end if;
    if tg_op = 'INSERT' or new.email is distinct from old.email then new.email := null; end if;
  end if;
  return new;
end $$;
revoke all on function private.aplicar_modo_alias() from public, anon, authenticated, service_role;

create trigger miembros_modo_alias
  before insert or update on public.miembros
  for each row execute function private.aplicar_modo_alias();

-- La pagina publica de registro necesita saber si pide alias o nombre y apellido
create or replace function public.info_checkin(p_token text)
returns jsonb
language plpgsql
stable
set search_path to ''
as $$
declare c record; v_abre timestamptz; v_cierra timestamptz; v_n integer; v_estado text;
begin
  select ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.lugar, e.cancelado, i.nombre as iglesia, i.email_contacto, i.modo_alias
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
    'evento', c.titulo, 'inicia_en', c.inicia_en, 'lugar', c.lugar, 'alias', c.modo_alias);
end;
$$;

-- registrar_checkin: lee el modo de la iglesia y, fuera del modo alias, sigue exigiendo el apellido
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
begin
  select ec.iglesia_id, ec.evento_id, ec.activo, ec.abre_en, ec.cierra_en, ec.max_registros,
         e.titulo, e.inicia_en, e.termina_en, e.casa_oracion_id, e.cancelado, i.modo_alias
    into c
    from public.evento_checkin ec
    join public.eventos e on e.id = ec.evento_id and e.iglesia_id = ec.iglesia_id
    join public.iglesias i on i.id = ec.iglesia_id and i.activa
   where ec.token = p_token
   for update of ec;
  if not found or not c.activo or c.cancelado then return 'no_valido'; end if;
  -- La pagina publica deja el apellido opcional porque no sabe el modo de la iglesia: aqui se exige si no es modo alias
  if not c.modo_alias and btrim(coalesce(p_apellido, '')) = '' then return 'datos'; end if;

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
    begin
      insert into public.miembros (iglesia_id, nombre, apellido, email, telefono, casa_oracion_id, activo, notas)
        values (c.iglesia_id, btrim(p_nombre), btrim(p_apellido), nullif(btrim(coalesce(p_email, '')), ''), btrim(p_telefono),
                c.casa_oracion_id, true, 'Registrado por QR en el evento: ' || c.titulo)
        returning id into v_miembro;
    exception when check_violation then
      if sqlerrm like 'PLAN_LIMITE%' then return 'cerrado'; end if;
      raise;
    end;
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
