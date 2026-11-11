#!/usr/bin/env bash
# Aislamiento entre iglesias a traves de la API: siembra dos iglesias y tres usuarios de prueba, lanza
# tests/aislamiento_api.py contra PostgREST y borra todo lo sembrado, pase lo que pase.
# Requiere PostgREST en marcha con tests/postgrest.conf sobre la base indicada (ver supabase/README.md).
# Uso: PGHOST=... PGPORT=... PGUSER=postgres tests/aislamiento_api.sh <base_con_migraciones> [url_de_la_api]
# Nunca apuntar a produccion: se niega si la base tiene iglesias que no sean de prueba.
set -euo pipefail
cd "$(dirname "$0")/.."
export PGDATABASE="$1"
API="${2:-http://localhost:3555}"
A=ea100000-0000-0000-0000-00000000000a
B=ea100000-0000-0000-0000-00000000000b

limpiar() {
  psql -q -v ON_ERROR_STOP=1 -f - <<SQL
begin;
set local session_replication_role = replica;
delete from public.rol_permisos where rol_id in (select id from public.roles where iglesia_id in ('$A', '$B'));
do \$\$
declare r record;
begin
  for r in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and c.relname <> 'iglesias'
           and exists (select 1 from pg_attribute a where a.attrelid = c.oid and a.attname = 'iglesia_id' and not a.attisdropped) loop
    execute format('delete from public.%I where iglesia_id in (%L, %L)', r.relname, '$A', '$B');
  end loop;
end \$\$;
delete from public.iglesias where id in ('$A', '$B');
delete from auth.users where id in ('ea000000-0000-0000-0000-000000000001', 'ea000000-0000-0000-0000-000000000002', 'ea000000-0000-0000-0000-000000000003');
commit;
SQL
}

# origen.sql se niega a correr con iglesias reales y deja los datos sembrados gracias a conservar=1
psql -q -At -v ON_ERROR_STOP=1 -v salida=/dev/null -v conservar=1 -f tests/exportacion/origen.sql > /dev/null
trap limpiar EXIT
python3 tests/aislamiento_api.py "$API" ea000000-0000-0000-0000-000000000001 "$A" ea000000-0000-0000-0000-000000000003 "$B"
