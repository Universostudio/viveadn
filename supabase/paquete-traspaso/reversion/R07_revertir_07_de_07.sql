-- Vive ADN, REVERSIÓN del traspaso, archivo 7 de 7. Solo si Gerencia lo ordena. Aplicar en orden y detenerse en el primer error. Deja el real como estaba antes del traspaso (salvo los datos que se hayan creado después).
set search_path = public, extensions;

-- ===== reversión de 20261111170000_adn_panel_inicio =====
-- Reversion de 20261111170000_adn_panel_inicio.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena.
-- Solo borra una funcion de lectura: no toca ninguna tabla ni ningun dato.

begin;
drop function if exists public.adn_panel_inicio(date);
commit;

-- ===== reversión de 20261111160000_adn_comunicacion =====
-- Reversion de 20261111160000_adn_comunicacion.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borran adn_mensajes, adn_mensaje_destinatarios y adn_comunicacion_bajas: el historial del buzon de pruebas y
--    la lista de personas que pidieron no recibir mensajes se pierden. Las bajas son una obligacion legal en cuanto
--    exista un proveedor real: copiarlas antes con \copy public.adn_comunicacion_bajas to 'bajas.csv' csv header
--  * Se quitan los permisos comunicacion.ver y comunicacion.enviar de todos los roles.
--  * No toca ninguna otra fila de negocio.

begin;
drop function if exists public.adn_vista_previa_envio(text, text);
drop function if exists public.adn_enviar_mensaje(uuid, text, text, text, text, text);
drop function if exists private.adn_vista_previa_envio(text, text);
drop function if exists private.adn_enviar_mensaje(uuid, text, text, text, text, text);
drop function if exists private.adn_destinatarios(uuid, text, text);
drop table if exists public.adn_mensaje_destinatarios;
drop table if exists public.adn_mensajes;
drop table if exists public.adn_comunicacion_bajas;

-- Cadena de siembra de roles anterior (la de 20261105235306_motor_formacion.sql)
create or replace function private.trg_sembrar_roles()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  perform private.sembrar_roles(new.id);
  perform private.sembrar_roles_nuevos(new.id);
  perform private.sembrar_eventos(new.id);
  perform private.sembrar_formacion(new.id);
  return new;
end $$;
drop function if exists private.sembrar_comunicacion(uuid);

delete from public.rol_permisos where permiso in ('comunicacion.ver', 'comunicacion.enviar');
delete from public.permisos where clave in ('comunicacion.ver', 'comunicacion.enviar');
commit;

-- ===== reversión de 20261111150000_adn_informes =====
-- Reversion de 20261111150000_adn_informes.sql. No es una migracion: se ejecuta a mano, solo si Gerencia lo ordena,
-- y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Solo borra funciones de lectura (adn_informe_*): no toca ninguna tabla ni ningun dato.

begin;
drop function if exists public.adn_informe_miembros();
drop function if exists public.adn_informe_miembros_resumen();
drop function if exists public.adn_informe_asistencia(date, date);
drop function if exists public.adn_informe_crecimiento(integer);
commit;

-- ===== reversión de 20261111140000_adn_importar_contactos =====
-- Reversion de 20261111140000_adn_importar_contactos.sql. No es una migracion: se ejecuta a mano, solo si
-- Gerencia lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borra `adn_miembro_contactos`: los segundos correos, telefonos adicionales, direcciones y etiquetas
--    importados se pierden. Los miembros importados NO se tocan (nombre, apellido, correo y telefono principales,
--    fecha de nacimiento y notas viven en `miembros`). Para conservar los extras, copiarlos antes con:
--      \copy public.adn_miembro_contactos to 'contactos.csv' csv header
--  * No toca ninguna otra fila de negocio.

begin;
drop function if exists public.adn_importar_miembros(jsonb, text);
drop function if exists public.adn_telefono_canonico(text);
drop table if exists public.adn_miembro_contactos;
commit;

-- ===== reversión de 20261111130000_adn_exportacion =====
-- Reversion de 20261111130000_adn_exportacion.sql. No es una migracion: se ejecuta a mano, solo si Gerencia
-- lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Solo borra funciones nuevas (adn_*): no toca ninguna tabla ni ningun dato. exportar_iglesia, la funcion
-- original de exportacion, no se modifica en la migracion y sigue funcionando igual.

begin;
drop function if exists public.adn_verificar_carga(jsonb);
drop function if exists public.adn_exportar_paquete(uuid);
drop function if exists public.adn_tablas_exportables();
drop function if exists public.adn_fila_exportable(jsonb, text[]);
drop function if exists public.adn_csv_campo(jsonb);
commit;

-- ===== reversión de 20261111120000_adn_ciclo_vida =====
-- Reversion de 20261111120000_adn_ciclo_vida.sql. No es una migracion: vive fuera de
-- `migrations/` para que el CLI de Supabase no la aplique sola. Se ejecuta a mano, solo si
-- Gerencia lo ordena, y la prueba supabase/tests/adn_reversion.sh demuestra que deja el
-- esquema identico al de antes de la migracion.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borra `adn_ciclo_auditoria`: el historial de borrados suaves, recuperaciones y purgas se pierde.
--    Si importa conservarlo, copiarlo antes con: \copy public.adn_ciclo_auditoria to 'auditoria.csv' csv header
--  * Una iglesia que estuviera en borrado suave NO se recupera ni se purga: conserva etapa `suspendida` y su
--    `borrado_programado_en` (el mismo plazo de 30 dias), de modo que el mecanismo anterior sigue protegiendola
--    y el borrado manual existente la podra borrar al vencer el plazo. Se pierden solo las marcas adn_*.
--  * No toca ninguna fila de negocio.

begin;

drop trigger if exists iglesias_zz_adn_coherencia on public.iglesias;
drop function if exists private.adn_coherencia_borrado();

drop function if exists public.adn_purgar_iglesia(uuid, uuid);
drop function if exists public.adn_iglesias_vencidas();
drop function if exists public.adn_recuperar_iglesia(uuid, uuid, text);
drop function if exists public.adn_borrar_suave(uuid, uuid, text);
drop function if exists public.adn_auditar_ciclo(uuid, text, uuid, text, jsonb);

alter table public.iglesias
  drop constraint if exists adn_iglesias_borrada_check,
  drop column if exists adn_borrada_en,
  drop column if exists adn_borrada_por,
  drop column if exists adn_estado_previo;

-- Cuerpo anterior de la guarda (el de 20261105221251_exportar_borrar_iglesia.sql)
create or replace function private.guardar_iglesia()
returns trigger language plpgsql set search_path to '' as $$
begin
  if (select auth.uid()) is null then
    return new;
  end if;
  if new.plan is distinct from old.plan or new.activa is distinct from old.activa
     or new.slug is distinct from old.slug or new.es_demo is distinct from old.es_demo
     or new.iglesia_madre_id is distinct from old.iglesia_madre_id or new.red_acceso is distinct from old.red_acceso
     or new.etapa is distinct from old.etapa or new.etapa_desde is distinct from old.etapa_desde
     or new.prueba_hasta is distinct from old.prueba_hasta
     or new.borrado_programado_en is distinct from old.borrado_programado_en then
    raise exception 'El plan, el estado, la etapa, la direccion y la red de la iglesia solo los cambia la plataforma';
  end if;
  return new;
end;
$$;

drop table if exists public.adn_ciclo_auditoria;

commit;
