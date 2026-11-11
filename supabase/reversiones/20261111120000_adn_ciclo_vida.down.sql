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
\set ON_ERROR_STOP on
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
