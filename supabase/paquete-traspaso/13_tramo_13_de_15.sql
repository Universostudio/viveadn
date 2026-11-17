-- Vive ADN, traspaso al proyecto real, archivo 14 de 19: tramo 13 de 15. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.
set search_path = public, extensions;
do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if to_regclass('public.adn_tickets') is not null then raise notice 'Tramo 13 de 15 ya aplicado: no se repite'; return; end if;
  if not (to_regprocedure('public.adn_seguimiento_alerta(timestamptz,bool,uuid,timestamptz)') is not null) then raise exception 'Falta aplicar antes el tramo 12 de 15: no se sigue.'; end if;
  execute $cuerpo$

-- ===== 20261111340000_adn_seguimiento_propio (origen sha256 f00fb86b3cf7, compilado sha256 225f08bf186a) =====
-- Método de seguimiento configurable, FASE 3: la iglesia elige su método y, en Premium, crea y edita el suyo. Diseño: docs/SEGUIMIENTO-CONFIGURABLE.md.
--  * Módulo nuevo seguimiento_propio (una fila en modulos y en plan_modulos, solo Premium para las pruebas de desarrollo; el empaquetado real por plan queda pendiente).
--    No se reutiliza consolidacion_etapas, que es otra idea (etapas hasta el bautismo).
--  * Elegir entre OP72 y Seguimiento simple está en todos los planes; crear y editar un método propio exige el módulo. Quien configura es quien tiene iglesia.configurar.
--  * Escritura por seguridad de filas, sin funciones nuevas para guardar: solo se pueden insertar y editar métodos de la propia iglesia, y solo las columnas de contenido
--    (la iglesia, la clave y la plantilla de origen no se pueden cambiar). Nada se borra: un método se archiva, y uno archivado o activo no se archiva ni se elige de nuevo.
--  * Un proceso nuevo toma el método activo de la iglesia (sin fila de configuración, OP72) mediante un disparador; la columna sigue con OP72 por defecto. Los procesos abiertos conservan el suyo.
--  * Si se editan los plazos de un método, la fecha límite y el color de sus procesos abiertos se recalculan; los completados no cambian.
--  * adn_seguimiento_en_uso() dice cuántos procesos usan un método, para avisar antes de guardar.
-- Reversión: supabase/reversiones/20261111340000_adn_seguimiento_propio.down.sql (deja los métodos propios y los procesos como están: solo quita la posibilidad de editarlos).

insert into public.modulos (clave, nombre, descripcion, tipo, orden) values
  ('seguimiento_propio', 'Método de seguimiento propio', 'La iglesia crea y edita su propio método de seguimiento de nuevas personas: número de contactos, plazo y colores', 'especial', 216)
on conflict (clave) do nothing;
insert into public.plan_modulos (plan, modulo) values ('premium', 'seguimiento_propio') on conflict do nothing;

-- La comprobación de la plantilla de origen debe poder mirar métodos de otras iglesias que quien escribe no ve: con la seguridad de quien llama,
-- el método ajeno no se vería y la copia pasaría. Por eso pasa a security definer (su contenido no cambia).
create or replace function private.adn_comprobar_plantilla() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.plantilla_origen is not null and exists (select 1 from public.adn_seguimiento_metodos o where o.id = new.plantilla_origen and o.iglesia_id is not null and o.iglesia_id is distinct from new.iglesia_id) then
    raise exception 'ADN_PLANTILLA_DE_OTRA_IGLESIA' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_plantilla() from public, anon, authenticated, service_role;
-- Lo mismo con la comprobación del método de un proceso o de la configuración: debe distinguir «no existe» de «es de otra iglesia» sin que la seguridad de filas esconda la fila
create or replace function private.adn_comprobar_metodo() returns trigger language plpgsql security definer set search_path to '' as $$
declare m record;
begin
  select iglesia_id, archivado_en into m from public.adn_seguimiento_metodos where id = new.metodo_id;
  if not found then raise exception 'ADN_METODO_INEXISTENTE' using errcode = 'foreign_key_violation'; end if;
  if m.iglesia_id is not null and m.iglesia_id <> new.iglesia_id then raise exception 'ADN_METODO_DE_OTRA_IGLESIA' using errcode = 'check_violation'; end if;
  if m.archivado_en is not null and (tg_op = 'INSERT' or new.metodo_id is distinct from old.metodo_id) then raise exception 'ADN_METODO_ARCHIVADO' using errcode = 'check_violation'; end if;
  return new;
end $$;
revoke all on function private.adn_comprobar_metodo() from public, anon, authenticated, service_role;

-- Un método se puede elegir si es de plataforma o es de la propia iglesia con el módulo contratado, y no está archivado
create or replace function private.adn_metodo_usable(p_metodo uuid) returns boolean language sql stable security definer set search_path to '' as $$
  select exists (
    select 1 from public.adn_seguimiento_metodos m
     where m.id = p_metodo and m.archivado_en is null
       and (m.iglesia_id is null or (m.iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_modulo('seguimiento_propio'))))
  )
$$;
revoke all on function private.adn_metodo_usable(uuid) from public, anon, authenticated, service_role;
grant execute on function private.adn_metodo_usable(uuid) to authenticated, service_role;

-- Escritura sobre los métodos: solo los de la propia iglesia, con permiso de configuración y con el módulo
revoke all on public.adn_seguimiento_metodos from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_metodos to authenticated;
grant insert (id, iglesia_id, clave, nombre, plantilla_origen, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas, primer_contacto_horas) on public.adn_seguimiento_metodos to authenticated;
grant update (nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas, primer_contacto_horas, archivado_en) on public.adn_seguimiento_metodos to authenticated;
grant all on public.adn_seguimiento_metodos to service_role;
create policy adn_seguimiento_metodos_crear on public.adn_seguimiento_metodos for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and archivado_en is null
              and (select private.tiene_permiso('iglesia.configurar')) and (select private.tiene_modulo('seguimiento_propio')));
create policy adn_seguimiento_metodos_editar on public.adn_seguimiento_metodos for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.tiene_modulo('seguimiento_propio')))
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.tiene_modulo('seguimiento_propio')));

-- Como mucho diez métodos propios sin archivar por iglesia
create or replace function private.adn_limitar_metodos() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.iglesia_id is not null and (select count(*) from public.adn_seguimiento_metodos m where m.iglesia_id = new.iglesia_id and m.archivado_en is null) >= 10 then
    raise exception 'ADN_DEMASIADOS_METODOS' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_limitar_metodos() from public, anon, authenticated, service_role;
create trigger adn_seguimiento_metodos_limite before insert on public.adn_seguimiento_metodos
  for each row execute function private.adn_limitar_metodos();

-- El método que la iglesia tiene activo no se archiva (primero se elige otro)
create or replace function private.adn_no_archivar_activo() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.archivado_en is not null and old.archivado_en is null and exists (select 1 from public.adn_seguimiento_config c where c.metodo_id = new.id) then
    raise exception 'ADN_METODO_ACTIVO' using errcode = 'check_violation';
  end if;
  return new;
end $$;
revoke all on function private.adn_no_archivar_activo() from public, anon, authenticated, service_role;
create trigger adn_seguimiento_metodos_archivo before update of archivado_en on public.adn_seguimiento_metodos
  for each row execute function private.adn_no_archivar_activo();

-- Si cambian el plazo o los colores, los procesos abiertos de ese método recalculan su fecha límite y su color. Los completados no cambian.
create or replace function private.adn_metodo_recalcular() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.plazo_horas is distinct from old.plazo_horas or new.umbral_amarillo_horas is distinct from old.umbral_amarillo_horas or new.umbral_naranja_horas is distinct from old.umbral_naranja_horas then
    update public.consolidaciones c set fecha_limite = c.fecha_conversion + make_interval(hours => new.plazo_horas)
     where c.metodo_id = new.id and c.completado is not true;
  end if;
  return null;
end $$;
revoke all on function private.adn_metodo_recalcular() from public, anon, authenticated, service_role;
create trigger adn_seguimiento_metodos_recalcular after update of plazo_horas, umbral_amarillo_horas, umbral_naranja_horas on public.adn_seguimiento_metodos
  for each row execute function private.adn_metodo_recalcular();

-- Elegir el método activo de la iglesia
revoke all on public.adn_seguimiento_config from public, anon, authenticated, service_role;
grant select on public.adn_seguimiento_config to authenticated;
grant insert (iglesia_id, metodo_id), update (metodo_id) on public.adn_seguimiento_config to authenticated;
grant all on public.adn_seguimiento_config to service_role;
create policy adn_seguimiento_config_elegir on public.adn_seguimiento_config for insert to authenticated
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.adn_metodo_usable(metodo_id)));
create policy adn_seguimiento_config_cambiar on public.adn_seguimiento_config for update to authenticated
  using (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')))
  with check (iglesia_id = (select private.get_iglesia_id()) and (select private.tiene_permiso('iglesia.configurar')) and (select private.adn_metodo_usable(metodo_id)));
create or replace function private.adn_config_tocar() returns trigger language plpgsql set search_path to '' as $$
begin new.updated_at := now(); return new; end $$;
revoke all on function private.adn_config_tocar() from public, anon, authenticated, service_role;
create trigger adn_seguimiento_config_fecha before update on public.adn_seguimiento_config for each row execute function private.adn_config_tocar();

-- Un proceso nuevo toma el método activo de la iglesia. La columna conserva OP72 como valor por defecto (es la red de seguridad de las cargas sin disparadores,
-- como una restauración); este disparador, que se ejecuta antes que el de comprobación por llevar un nombre anterior en orden alfabético, cambia OP72 por el
-- método activo cuando la iglesia eligió otro. Un método distinto de OP72 dado a mano se respeta. Límite conocido: un proceso insertado a mano con OP72
-- explícito en una iglesia que usa otro método pasa al método activo; las restauraciones se hacen sin disparadores (docs/EXPORTACION.md) y no se ven afectadas.
create or replace function private.adn_consolidacion_metodo_activo() returns trigger language plpgsql security definer set search_path to '' as $$
begin
  if new.metodo_id = '5e000000-0000-4000-8000-000000000072'::uuid then new.metodo_id := private.adn_metodo_activo(new.iglesia_id); end if;
  return new;
end $$;
revoke all on function private.adn_consolidacion_metodo_activo() from public, anon, authenticated, service_role;
create trigger consolidaciones_a_metodo before insert on public.consolidaciones for each row execute function private.adn_consolidacion_metodo_activo();

-- Cuántos procesos de la iglesia usan un método (para avisar antes de guardar un cambio). Solo lo ve quien puede configurar.
-- La parte con privilegios vive en private (la regla del proyecto es que en public no haya funciones con SECURITY DEFINER); la pública solo la llama.
create or replace function private.adn_seguimiento_en_uso(p_metodo uuid) returns jsonb language sql stable security definer set search_path to '' as $$
  select case when (select private.tiene_permiso('iglesia.configurar')) then
    (select jsonb_build_object('abiertos', count(*) filter (where c.completado is not true), 'total', count(*))
       from public.consolidaciones c where c.iglesia_id = (select private.get_iglesia_id()) and c.metodo_id = p_metodo)
  end
$$;
revoke all on function private.adn_seguimiento_en_uso(uuid) from public, anon, authenticated, service_role;
grant execute on function private.adn_seguimiento_en_uso(uuid) to authenticated, service_role;
create or replace function public.adn_seguimiento_en_uso(p_metodo uuid) returns jsonb language sql stable set search_path to '' as $$
  select private.adn_seguimiento_en_uso(p_metodo)
$$;
revoke all on function public.adn_seguimiento_en_uso(uuid) from public, anon, authenticated, service_role;
grant execute on function public.adn_seguimiento_en_uso(uuid) to authenticated, service_role;
-- ===== 20261111350000_adn_soporte (origen sha256 dddf06b599e8, compilado sha256 88c62c62458b) =====
-- Soporte dentro de la plataforma, sin servicios externos de pago. Tres piezas independientes:
--  (a) Tickets: la iglesia (quien puede configurarla, iglesia.configurar) abre un ticket con asunto, texto y prioridad y sigue su conversación; la plataforma
--      lo ve, responde y cierra desde la función de borde (service_role). Una iglesia solo ve los suyos.
--  (b) Novedades de plataforma: registro de cambios publicado por la plataforma (versión, fecha, texto), que lee cualquier persona con sesión, con una marca
--      de «vistas» por persona para el aviso de «novedades».
--  (c) Avisos masivos dentro de la aplicación: la plataforma redacta un aviso (actualización, mantenimiento o alerta) y elige destinatarios (todas, por plan
--      o por estado). Al crearlo se reparte una entrega a cada iglesia destinataria; cada iglesia lo ve como banner descartable y queda registro de entrega,
--      lectura y descarte. El correo masivo NO se envía: solo se anota si se pidió y que el envío está apagado.
-- Todo con el prefijo adn_. Las tablas con iglesia_id caen con la iglesia al purgarla.
-- Reversión: supabase/reversiones/20261111350000_adn_soporte.down.sql (borra estas tablas y sus datos: es lo único que se pierde).
-- Escrito para poder repetirse sin error y sin reordenar permisos (if not exists, quitar ... if exists, create or replace, revoke con todos los roles).

-- ---------------------------------------------------------------- (a) Tickets
create table if not exists public.adn_tickets (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null default private.get_iglesia_id() references public.iglesias(id) on delete cascade,
  creado_por uuid not null default auth.uid(),
  asunto text not null check (length(btrim(asunto)) between 3 and 120),
  prioridad text not null default 'normal' check (prioridad in ('baja', 'normal', 'alta', 'urgente')),
  estado text not null default 'abierto' check (estado in ('abierto', 'respondido', 'cerrado')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cerrado_en timestamptz,
  constraint adn_tickets_cierre check ((estado = 'cerrado') = (cerrado_en is not null)),
  constraint adn_tickets_id_iglesia_uq unique (id, iglesia_id)
);
create index if not exists adn_tickets_iglesia_idx on public.adn_tickets (iglesia_id, created_at desc);
create index if not exists adn_tickets_estado_idx on public.adn_tickets (estado, updated_at desc);
$cuerpo$;
end $tramo$;
select 'ok: tramo 13 de 15 aplicado' as resultado, (to_regclass('public.adn_tickets') is not null) as comprobado;
