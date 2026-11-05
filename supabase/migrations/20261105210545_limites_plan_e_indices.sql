-- Corte duro de los limites del plan y indices de las tablas que mas crecen.
--
-- Hasta ahora planes.max_miembros y planes.max_usuarios solo se mostraban: nada los hacia cumplir.
-- Ahora la base rechaza el alta que supera el tope, con el mensaje "PLAN_LIMITE: miembros" o
-- "PLAN_LIMITE: usuarios". Un limite nulo significa sin tope. Cada iglesia se serializa con un cerrojo
-- propio, para que dos altas simultaneas no se cuelen a la vez.
--   * miembros: cuentan los activos; tambien se comprueba al reactivar uno
--   * usuarios: cuentan los perfiles activos; una invitacion pendiente reserva su plaza

create or replace function private.limitar_plan_miembros()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare v_max integer; v_n integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_miembros into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.miembros where iglesia_id = new.iglesia_id and activo;
  if v_n >= v_max then
    raise exception 'PLAN_LIMITE: miembros' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

create or replace function private.limitar_plan_usuarios()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare v_max integer; v_n integer;
begin
  if new.activo is not true then return new; end if;
  if tg_op = 'UPDATE' and old.activo is true then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  if v_n >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

-- Una invitacion pendiente reserva una plaza: perfiles activos mas invitaciones vigentes no superan el tope
create or replace function private.limitar_plan_invitaciones()
 returns trigger
 language plpgsql
 set search_path to ''
as $$
declare v_max integer; v_n integer; v_i integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('plan:' || new.iglesia_id::text, 0));
  select p.max_usuarios into v_max from public.iglesias i join public.planes p on p.clave = i.plan where i.id = new.iglesia_id;
  if v_max is null then return new; end if;
  select count(*) into v_n from public.perfiles where iglesia_id = new.iglesia_id and activo;
  select count(*) into v_i from public.invitaciones
   where iglesia_id = new.iglesia_id and usada_en is null and revocada_en is null and caduca_en > now();
  if v_n + v_i >= v_max then
    raise exception 'PLAN_LIMITE: usuarios' using errcode = 'check_violation', detail = format('Tope del plan: %s', v_max);
  end if;
  return new;
end;
$$;

revoke execute on function private.limitar_plan_miembros() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_usuarios() from public, anon, authenticated, service_role;
revoke execute on function private.limitar_plan_invitaciones() from public, anon, authenticated, service_role;

create trigger miembros_limite_plan before insert or update of activo on public.miembros
  for each row execute function private.limitar_plan_miembros();
create trigger perfiles_limite_plan before insert or update of activo on public.perfiles
  for each row execute function private.limitar_plan_usuarios();
create trigger invitaciones_limite_plan before insert on public.invitaciones
  for each row execute function private.limitar_plan_invitaciones();

-- El registro por QR no debe romperse cuando la iglesia no tiene plazas: a quien llega se le responde
-- como si el registro estuviera cerrado. Es la misma funcion de antes con un bloque de captura alrededor del alta.
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
   where ec.token = p_token
   for update of ec;
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

revoke execute on function public.registrar_checkin(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text) to service_role;

-- Indices que empiezan por iglesia_id, que es por lo que filtra la seguridad por filas, y que cubren
-- las claves foraneas compuestas (iglesia_id, id) de las tablas que mas crecen
create index asistencia_evento_iglesia_evento_idx on public.asistencia_evento (iglesia_id, evento_id);
create index asistencia_evento_iglesia_miembro_idx on public.asistencia_evento (iglesia_id, miembro_id);
create index checkin_registros_iglesia_evento_idx on public.checkin_registros (iglesia_id, evento_id);
create index checkin_registros_iglesia_miembro_idx on public.checkin_registros (iglesia_id, miembro_id);
create index evento_checkin_iglesia_evento_idx on public.evento_checkin (iglesia_id, evento_id);
create index eventos_iglesia_casa_idx on public.eventos (iglesia_id, casa_oracion_id);
create index invitaciones_iglesia_rol_idx on public.invitaciones (iglesia_id, rol);
create index invitaciones_creada_por_idx on public.invitaciones (creada_por);
create index zonas_lider_idx on public.zonas (lider_id);
