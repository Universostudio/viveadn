-- Reversion de 20261111140000_adn_importar_contactos.sql. No es una migracion: se ejecuta a mano, solo si
-- Gerencia lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
--
-- Efectos sobre datos, a tener en cuenta antes de ejecutarla:
--  * Se borra `adn_miembro_contactos`: los segundos correos, telefonos adicionales, direcciones y etiquetas
--    importados se pierden. Los miembros importados NO se tocan (nombre, apellido, correo y telefono principales,
--    fecha de nacimiento y notas viven en `miembros`). Para conservar los extras, copiarlos antes con:
--      \copy public.adn_miembro_contactos to 'contactos.csv' csv header
--  * No toca ninguna otra fila de negocio.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_importar_miembros(jsonb, text);
drop function if exists public.adn_telefono_canonico(text);
drop table if exists public.adn_miembro_contactos;
commit;
