-- Reversion de 20261111130000_adn_exportacion.sql. No es una migracion: se ejecuta a mano, solo si Gerencia
-- lo ordena, y tests/adn_reversion.sh demuestra que deja el esquema identico al anterior.
-- Solo borra funciones nuevas (adn_*): no toca ninguna tabla ni ningun dato. exportar_iglesia, la funcion
-- original de exportacion, no se modifica en la migracion y sigue funcionando igual.
\set ON_ERROR_STOP on
begin;
drop function if exists public.adn_verificar_carga(jsonb);
drop function if exists public.adn_exportar_paquete(uuid);
drop function if exists public.adn_tablas_exportables();
drop function if exists public.adn_fila_exportable(jsonb, text[]);
drop function if exists public.adn_csv_campo(jsonb);
commit;
