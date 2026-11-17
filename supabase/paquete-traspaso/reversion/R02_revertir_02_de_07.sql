-- Vive ADN, REVERSIÓN del traspaso, archivo 2 de 7. Solo si Gerencia lo ordena. Aplicar en orden y detenerse en el primer error. Deja el real como estaba antes del traspaso (salvo los datos que se hayan creado después).
set search_path = public, extensions;

-- ===== reversión de 20261111300000_adn_checkin_nuevo_creyente =====
-- Reversión de 20261111300000_adn_checkin_nuevo_creyente.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo
-- ordena, y tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior.
-- Devuelve registrar_checkin a su definición anterior (con la doble confirmación; toda persona nueva abre seguimiento).
-- No toca datos: los seguimientos que se abrieron o no se abrieron mientras estuvo la pregunta se quedan como están.

begin;
drop function public.registrar_checkin(text, text, text, text, text, text, text, text, text[], boolean);
create or replace function public.registrar_checkin(p_token text, p_nombre text, p_apellido text, p_email text, p_telefono text, p_ip_hash text, p_texto_version text default null, p_idioma text default null, p_canales text[] default null)
 returns text
 language plpgsql
 set search_path to ''
as $$
declare
  c record; v_miembro uuid; v_nuevo boolean := false; v_dig text; v_n integer; v_abre timestamptz; v_cierra timestamptz;
  v_ver text := nullif(btrim(coalesce(p_texto_version, '')), ''); v_hash text;
  v_canal text; v_hash_c text; v_doble boolean := private.adn_doble_confirmacion_activa(); v_aplica boolean;
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

  -- Evidencia de lo que aceptó quien se registró: qué texto (versión y huella) y cuándo. Cada registro deja una fila.
  -- La versión la afirma la página: si no consta en la tabla de textos se anota 'sin_version' y no se inventa una huella.
  select t.texto_hash into v_hash from public.adn_consentimiento_textos t where t.finalidad = 'checkin' and t.version = v_ver and t.idioma = p_idioma;
  insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, finalidad, texto_version, idioma, texto_hash, evento_id, origen)
    values (c.iglesia_id, v_miembro, 'checkin', 'checkin', case when v_hash is null then 'sin_version' else v_ver end,
            case when v_hash is null then null else p_idioma end, v_hash, c.evento_id, 'qr');

  -- Casillas de canal (correo, WhatsApp, SMS): cada una marcada deja su evidencia con el texto que acompañaba a esa casilla.
  -- Solo una persona NUEVA queda suscrita: a quien ya existía no se le cambia el consentimiento, porque el correo o el
  -- teléfono que escribe alguien en un formulario público no prueban que sea la misma persona. Sin una versión de texto
  -- verificable en la tabla, la casilla queda anotada pero no concede nada.
  for v_canal in select distinct u from unnest(coalesce(p_canales, '{}')) u order by u loop
    continue when v_canal not in ('email', 'whatsapp', 'sms');
    continue when v_canal = 'email' and coalesce(btrim(p_email), '') = '';
    select t.texto_hash into v_hash_c from public.adn_consentimiento_textos t where t.finalidad = 'checkin_' || v_canal and t.version = v_ver and t.idioma = p_idioma;
    -- Con la doble confirmación activa, la casilla NO concede nada todavía: el consentimiento llega cuando la persona
    -- confirma desde el enlace que se le envía. Hoy solo el correo tiene ese mecanismo; WhatsApp y SMS quedan sin conceder.
    v_aplica := v_nuevo and v_hash_c is not null and not v_doble;
    insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, finalidad, texto_version, idioma, texto_hash, evento_id, aplicado, origen)
      values (c.iglesia_id, v_miembro, 'checkin', v_canal, 'checkin_' || v_canal, case when v_hash_c is null then 'sin_version' else v_ver end,
              case when v_hash_c is null then null else p_idioma end, v_hash_c, c.evento_id, v_aplica, 'qr');
    if v_aplica then
      perform private.adn_escribir_consentimiento(c.iglesia_id, v_miembro, v_canal, 'suscrito', 'qr', null);
    elsif v_nuevo and v_hash_c is not null and v_doble and v_canal = 'email'
          and lower(btrim(p_email)) ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and char_length(btrim(p_email)) <= 254 then
      insert into public.adn_confirmaciones (iglesia_id, miembro_id, canal, destino, idioma)
        values (c.iglesia_id, v_miembro, 'email', lower(btrim(p_email)), p_idioma) on conflict do nothing;
    end if;
  end loop;

  return case when v_nuevo then 'ok_nuevo' else 'ok_existente' end;
end;
$$;

revoke execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) from public, anon, authenticated;
grant execute on function public.registrar_checkin(text, text, text, text, text, text, text, text, text[]) to service_role;
commit;

-- ===== reversión de 20261111290000_adn_plataforma_resumen =====
-- Reversión de 20261111290000_adn_plataforma_resumen.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las tres funciones de lectura del Panel Maestro
-- (no tocan datos: solo leen). Sin ellas, la función de borde 'plataforma' vuelve a contar con 2 consultas por iglesia y las pantallas
-- de actividad e historial dicen que no están disponibles; el resto del panel sigue funcionando.

begin;
drop function public.adn_plataforma_historial(uuid, integer);
drop function public.adn_plataforma_actividad(integer);
drop function public.adn_plataforma_resumen();
commit;

-- ===== reversión de 20261111280000_adn_envios_topes =====
-- Reversión de 20261111280000_adn_envios_topes.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las dos funciones y la tabla de contadores
-- diarios de envío (con sus filas: solo son cuentas del día, sin datos de personas). Sin ella, el envío de correo no debe estar encendido.

begin;
drop function public.adn_envio_liberar(text, uuid);
drop function public.adn_envio_reservar(text, uuid, integer, integer, integer);
drop table public.adn_envios_dia;
commit;

-- ===== reversión de 20261111270000_adn_autoservicio_datos =====
-- Reversión de 20261111270000_adn_autoservicio_datos.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Quita las funciones de autoservicio y la tabla de
-- auditoría que creó esa migración (con las filas que tuviera). Las iglesias que ya estuvieran en borrado suave por una baja pedida
-- por su propietario siguen su curso normal: el borrado suave y su auditoría (adn_ciclo_auditoria) no los toca esta reversión,
-- y la plataforma puede recuperarlas con `recuperar` como a cualquier otra.

begin;
drop function public.adn_autoservicio_cancelar_baja(uuid, uuid, text);
drop function public.adn_autoservicio_baja(uuid, uuid, text);
drop function public.adn_autoservicio_exportar(uuid, uuid);
drop function public.adn_autoservicio_estado(uuid, uuid);
drop function public.adn_es_propietario(uuid, uuid);
drop table public.adn_datos_auditoria;
commit;

-- ===== reversión de 20261111260000_adn_exportacion_paginada =====
-- Reversión de 20261111260000_adn_exportacion_paginada.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita las funciones de la exportación por páginas;
-- adn_exportar_paquete, que sigue existiendo, no se toca.

begin;
drop function public.adn_exportar_pagina(uuid, text, text, jsonb, integer);
drop function public.adn_exportar_plan(uuid);
drop function public.adn_exportar_orden();
drop function public.adn_exportar_secretos();
commit;

-- ===== reversión de 20261111250000_adn_purgas_libro =====
-- Reversión de 20261111250000_adn_purgas_libro.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita las dos funciones; no toca datos ni la
-- auditoría del ciclo de vida, y las iglesias que ya se hubieran marcado con adn_repurgar_registradas siguen su curso normal.

begin;
drop function public.adn_repurgar_registradas(uuid[], uuid);
drop function public.adn_purgas_desde(timestamptz);
commit;

-- ===== reversión de 20261111240000_adn_purga_estado =====
-- Reversión de 20261111240000_adn_purga_estado.sql. No es una migración: se ejecuta a mano, solo si Gerencia lo ordena, y
-- tests/adn_reversion.sh demuestra que deja el esquema idéntico al anterior. Solo quita la función de lectura.

begin;
drop function public.adn_purga_estado(integer);
commit;
