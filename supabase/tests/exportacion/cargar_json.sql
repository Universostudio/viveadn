-- Carga datos.json en una base vacia. Uso: ADN_DATOS=/ruta/datos.json ADN_MANIFIESTO=/ruta/manifest.json psql -f cargar_json.sql
\set ON_ERROR_STOP on
\i tests/exportacion/cargar_comun.sql
\set datos `cat "$ADN_DATOS"`
\set manifiesto `cat "$ADN_MANIFIESTO"`
create or replace function pg_temp.cargar(d jsonb, m jsonb) returns void language plpgsql as $$
declare t jsonb; n text; cols text; filas jsonb; om text[];
begin
  for t in select value from jsonb_array_elements(m -> 'tablas') order by (value ->> 'orden_carga')::int, value ->> 'nombre' loop
    n := t ->> 'nombre';
    filas := case when n = 'iglesias' then jsonb_build_array(d -> 'iglesia') else d -> 'tablas' -> n end;
    om := array(select jsonb_array_elements_text(t -> 'omitidas'));
    perform pg_temp.preparar(n, om);
    select string_agg(quote_ident(c ->> 'nombre'), ', ') into cols from jsonb_array_elements(t -> 'columnas') c;
    execute format('insert into public.%1$I (%2$s) overriding system value select %2$s from jsonb_populate_recordset(null::public.%1$I, $1)', n, cols) using filas;
    perform pg_temp.rellenar(n);
  end loop;
  perform pg_temp.usuarios_de_acceso();
  perform pg_temp.secuencias();
end $$;
begin;
set local session_replication_role = replica;
\o /dev/null
select pg_temp.cargar(:'datos'::jsonb, :'manifiesto'::jsonb);
\o
commit;
