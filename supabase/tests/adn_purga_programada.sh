#!/usr/bin/env bash
# Purga programada: prueba los guiones de scripts/entorno/purga-programada con sustitutos locales de pg_cron, pg_net y Vault (la base local no los tiene) y la función que
# muestra el estado de la tarea en «Sistema». Demuestra que el guion se niega a ejecutarse sin los secretos, que programa dos tareas sin duplicarlas al repetirlo,
# que la orden no contiene ninguna clave escrita a mano y que desprogramar quita solo las suyas. No toca ninguna base real: crea y borra su propia base.
# Uso: bash tests/adn_purga_programada.sh [base_temporal]
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${1:-adn_purga_prog_t}
PSQL=(psql -q -v ON_ERROR_STOP=1)
SC=../scripts/entorno/purga-programada
falla() { echo "FALLO: $*"; "${PSQL[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; exit 1; }
sql() { "${PSQL[@]}" -d $DB -At -c "$1" | tail -1; }
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql >/dev/null
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql >/dev/null
"${PSQL[@]}" -d $DB -f schema/seed.sql >/dev/null
for m in migrations/*.sql; do "${PSQL[@]}" -d $DB -f "$m" >/dev/null 2>&1 || falla "migracion $m"; done

# 1. Sin pg_cron la función de estado dice «no disponible» y no falla
[ "$(sql "select public.adn_purga_tarea_estado() ->> 'disponible'")" = "false" ] || falla "sin pg_cron debia decir no disponible"
echo "OK: sin pg_cron, el estado de la tarea dice «no disponible»"
# Solo el servidor la ejecuta
[ "$(sql "select has_function_privilege('authenticated', 'public.adn_purga_tarea_estado()', 'execute') or has_function_privilege('anon', 'public.adn_purga_tarea_estado()', 'execute')")" = "f" ] || falla "una sesion ejecuta el estado de la tarea"
echo "OK: ninguna sesion ejecuta el estado de la tarea"

# 2. Con el guion sin extensiones, se niega con un mensaje claro
if "${PSQL[@]}" -d $DB -f $SC/programar.sql >/dev/null 2>/tmp/prog_err.$$; then falla "programar.sql se ejecuto sin pg_cron"; fi
grep -q "pg_cron" /tmp/prog_err.$$ || falla "el mensaje no nombra pg_cron"
echo "OK: sin pg_cron el guion se niega y lo dice"

# 3. Sustitutos de pg_cron, pg_net y Vault
"${PSQL[@]}" -d $DB >/dev/null <<'SQL'
create schema cron; create schema net; create schema vault;
create table cron.job(jobid serial primary key, jobname text, schedule text, command text, active boolean default true);
create table cron.job_run_details(jobid int, start_time timestamptz default now(), status text);
create function cron.schedule(n text, s text, c text) returns bigint language sql as $$ insert into cron.job(jobname, schedule, command) values (n, s, c) returning jobid::bigint $$;
create function cron.unschedule(n text) returns boolean language sql as $$ with d as (delete from cron.job where jobname = n returning 1) select exists (select 1 from d) $$;
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{"Content-Type":"application/json"}', timeout_milliseconds integer default 5000) returns bigint language sql as 'select 1::bigint';
create table vault.decrypted_secrets(name text, decrypted_secret text);
insert into cron.job(jobname, schedule, command) values ('otra-tarea-ajena', '0 * * * *', 'select 1');
SQL
if "${PSQL[@]}" -d $DB -f $SC/programar.sql >/dev/null 2>/tmp/prog_err.$$; then falla "programar.sql se ejecuto sin secretos"; fi
grep -q "Faltan secretos" /tmp/prog_err.$$ || falla "el mensaje no habla de los secretos"
echo "OK: sin los secretos en Vault el guion se niega y lo dice"
sql "insert into vault.decrypted_secrets values ('adn_cron_secret', 'corto'), ('adn_anon_key', 'clave-publica-de-prueba'), ('adn_funciones_url', 'https://proyecto.example.test')" >/dev/null
if "${PSQL[@]}" -d $DB -f $SC/programar.sql >/dev/null 2>/tmp/prog_err.$$; then falla "programar.sql acepto un secreto corto"; fi
grep -q "32 caracteres" /tmp/prog_err.$$ || falla "el mensaje no habla de los 32 caracteres"
echo "OK: un secreto de menos de 32 caracteres se rechaza"
sql "update vault.decrypted_secrets set decrypted_secret = 'a-secret-de-prueba-con-mas-de-32-caracteres' where name = 'adn_cron_secret'" >/dev/null
sql "update vault.decrypted_secrets set decrypted_secret = 'https://proyecto.example.test/' where name = 'adn_funciones_url'" >/dev/null
if "${PSQL[@]}" -d $DB -f $SC/programar.sql >/dev/null 2>/tmp/prog_err.$$; then falla "programar.sql acepto una direccion con barra final"; fi
echo "OK: una dirección con barra final se rechaza"
sql "update vault.decrypted_secrets set decrypted_secret = 'https://proyecto.example.test' where name = 'adn_funciones_url'" >/dev/null

# 4. Programa, y repetirlo no duplica
"${PSQL[@]}" -d $DB -f $SC/programar.sql >/dev/null 2>&1 || falla "programar.sql fallo con todo en orden"
"${PSQL[@]}" -d $DB -f $SC/programar.sql >/dev/null 2>&1 || falla "programar.sql fallo al repetirse"
[ "$(sql "select string_agg(jobname || '=' || schedule, ',' order by jobname) from cron.job where jobname like 'adn-%'")" = "adn-avisar-purga=30 8 * * *,adn-purga-vencidas=15 3 * * *" ] || falla "las tareas no son las esperadas"
echo "OK: dos tareas diarias (purga 03:15 y aviso 08:30 UTC) y repetirlo no las duplica"
[ "$(sql "select count(*) from cron.job where jobname = 'otra-tarea-ajena'")" = "1" ] || falla "programar toco una tarea ajena"
echo "OK: no toca tareas ajenas"
c=$(sql "select replace(command, E'\\n', ' ') from cron.job where jobname = 'adn-purga-vencidas'")
case "$c" in *x-adn-cron*purgar_vencidas*'"max":10'*) ;; *) falla "la orden no lleva cabecera, accion y lote";; esac
case "$c" in *a-secret-de-prueba*|*clave-publica-de-prueba*|*proyecto.example.test*) falla "la orden lleva un secreto o la direccion escritos";; esac
case "$c" in *vault.decrypted_secrets*) ;; *) falla "la orden no lee de Vault";; esac
echo "OK: la orden lleva la cabecera, la accion y el lote de 10, y lee todo de Vault (no lleva ningun valor escrito)"

# 5. El estado de la tarea (con los sustitutos) muestra horario, activa y la última pasada
sql "insert into cron.job_run_details(jobid, start_time, status) select jobid, '2026-11-15 03:15+00', 'succeeded' from cron.job where jobname = 'adn-purga-vencidas'" >/dev/null
e=$(sql "select public.adn_purga_tarea_estado()::text")
[ "$(sql "select (public.adn_purga_tarea_estado() ->> 'disponible')")" = "true" ] || falla "con pg_cron debia estar disponible"
[ "$(sql "select t ->> 'ultimo_resultado' from jsonb_array_elements(public.adn_purga_tarea_estado() -> 'tareas') t where t ->> 'nombre' = 'adn-purga-vencidas'")" = "succeeded" ] || falla "no refleja la ultima pasada"
[ "$(sql "select jsonb_array_length(public.adn_purga_tarea_estado() -> 'tareas')")" = "2" ] || falla "debia listar solo las dos tareas adn-"
case "$e" in *x-adn-cron*|*decrypted*|*command*) falla "el estado de la tarea muestra la orden o un secreto";; esac
echo "OK: el estado muestra las dos tareas, su horario y la última pasada, sin mostrar la orden ni ningún secreto"

# 6. Desprogramar quita solo las suyas
"${PSQL[@]}" -d $DB -f $SC/desprogramar.sql >/dev/null 2>&1 || falla "desprogramar.sql fallo"
[ "$(sql "select string_agg(jobname, ',') from cron.job")" = "otra-tarea-ajena" ] || falla "desprogramar no dejo solo la ajena"
echo "OK: desprogramar quita las dos tareas adn- y deja la ajena"
rm -f /tmp/prog_err.$$
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" >/dev/null
