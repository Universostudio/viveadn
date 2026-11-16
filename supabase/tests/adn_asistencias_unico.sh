#!/usr/bin/env bash
# Índice único de asistencias: con duplicados reales ANTES de aplicar. Comprueba la limpieza (se conserva la fila más reciente), el archivo,
# el índice, y que la reversión devuelve los duplicados y deja el esquema idéntico. Uso: bash tests/adn_asistencias_unico.sh [base_temporal]
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${1:-adn_asistencias_unico_t}
PSQL=(psql -q -v ON_ERROR_STOP=1)
MIG=20261111310000_adn_asistencias_unico
volcado() { pg_dump -s --no-owner -d "$DB" | grep -vE '^\\(un)?restrict '; }
falla() { echo "FALLO: $*"; "${PSQL[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; exit 1; }
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
for m in migrations/*.sql; do [ "$m" = "migrations/$MIG.sql" ] && continue; "${PSQL[@]}" -d $DB -f "$m" > /dev/null; done
# Las migraciones posteriores a esta (si las hubiera) no se aplican: solo las anteriores
"${PSQL[@]}" -d $DB <<'SQL'
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('ae200000-0000-0000-0000-00000000000a', 'Prueba Asist', 'prueba-asist', 'ES', 'Sevilla', 'premium');
insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, pais, ciudad, direccion) values ('ae210000-0000-0000-0000-0000000000c1', 'ae200000-0000-0000-0000-00000000000a', 'ZN-900001', 'Casa 1', 'ES', 'Sevilla', 'Calle 1');
insert into public.miembros (id, iglesia_id, nombre, apellido, casa_oracion_id) values
  ('ae220000-0000-0000-0000-0000000000a1', 'ae200000-0000-0000-0000-00000000000a', 'A', 'Uno', 'ae210000-0000-0000-0000-0000000000c1'),
  ('ae220000-0000-0000-0000-0000000000a2', 'ae200000-0000-0000-0000-00000000000a', 'B', 'Dos', 'ae210000-0000-0000-0000-0000000000c1');
-- A1 el 10-11: tres filas (la más reciente dice presente = false); A1 el 17-11: una; A2 el 10-11: dos iguales en fecha de creación (desempata el id)
insert into public.asistencias (id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente, created_at) values
  ('ae230000-0000-0000-0000-000000000001', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-10', true,  '2026-11-10 20:00+00'),
  ('ae230000-0000-0000-0000-000000000002', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-10', true,  '2026-11-10 21:00+00'),
  ('ae230000-0000-0000-0000-000000000003', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-10', false, '2026-11-10 22:00+00'),
  ('ae230000-0000-0000-0000-000000000004', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-17', true,  '2026-11-17 20:00+00'),
  ('ae230000-0000-0000-0000-000000000005', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a2', '2026-11-10', true,  '2026-11-10 20:00+00'),
  ('ae230000-0000-0000-0000-000000000006', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a2', '2026-11-10', false, '2026-11-10 20:00+00');
SQL
volcado > /tmp/adn_as_antes.$$.sql
antes=$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.asistencias")
[ "$antes" = "6" ] || falla "se esperaban 6 filas de partida y hay $antes"

"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
res=$("${PSQL[@]}" -d $DB -At -c "select string_agg(right(id::text, 1) || ':' || presente::text, ',' order by id) from public.asistencias")
[ "$res" = "3:false,4:true,6:false" ] || falla "se conserva la más reciente de cada grupo (y desempata el id): salió $res"
echo "OK: la limpieza conserva la fila más reciente de cada casa, persona y fecha (y desempata por id)"
arch=$("${PSQL[@]}" -d $DB -At -c "select string_agg(right(id::text, 1), ',' order by id) from public.adn_asistencias_duplicadas")
[ "$arch" = "1,2,5" ] || falla "las filas borradas deben estar archivadas: salió $arch"
echo "OK: las tres filas sobrantes quedan archivadas antes de borrarse"
if "${PSQL[@]}" -d $DB -c "insert into public.asistencias (iglesia_id, casa_oracion_id, miembro_id, fecha) values ('ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-17')" >/dev/null 2>&1; then falla "el índice único admite un duplicado"; fi
echo "OK: el índice único rechaza una segunda fila de la misma casa, persona y fecha"
"${PSQL[@]}" -d $DB -c "insert into public.asistencias (iglesia_id, casa_oracion_id, miembro_id, fecha) values ('ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-24'), ('ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a2', '2026-11-24')" || falla "otra fecha o persona debe poder guardarse"
"${PSQL[@]}" -d $DB -c "update public.asistencias set presente = false where id = 'ae230000-0000-0000-0000-000000000004'" || falla "actualizar presente debe seguir pudiéndose"
echo "OK: otra fecha u otra persona se guardan, y actualizar la asistencia sigue funcionando"
priv=$("${PSQL[@]}" -d $DB -At -c "select has_table_privilege('authenticated', 'public.adn_asistencias_duplicadas', 'select') or has_table_privilege('anon', 'public.adn_asistencias_duplicadas', 'select')")
[ "$priv" = "f" ] || falla "el archivo de duplicados no debe leerse con sesión"
echo "OK: el archivo de duplicados no lo lee nadie con sesión"
# Sin duplicados no se toca nada: se vuelve a aplicar la limpieza sobre datos limpios
"${PSQL[@]}" -d $DB -c "drop index public.adn_asistencias_unica_idx" -c "truncate public.adn_asistencias_duplicadas"
n0=$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.asistencias")
"${PSQL[@]}" -d $DB -c "drop table public.adn_asistencias_duplicadas" -f "migrations/$MIG.sql" > /dev/null
[ "$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.asistencias")" = "$n0" ] || falla "sin duplicados la migración no debe borrar filas"
[ "$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.adn_asistencias_duplicadas")" = "0" ] || falla "sin duplicados no se archiva nada"
echo "OK: sin duplicados no se borra ni se archiva ninguna fila"

# Reversión: vuelve a la situación de partida (los duplicados incluidos) con el esquema idéntico
"${PSQL[@]}" -d $DB -c "drop index public.adn_asistencias_unica_idx" -c "drop table public.adn_asistencias_duplicadas" >/dev/null
"${PSQL[@]}" -d $DB -c "delete from public.asistencias where id not in ('ae230000-0000-0000-0000-000000000003','ae230000-0000-0000-0000-000000000004','ae230000-0000-0000-0000-000000000006')" >/dev/null
# Se rehace el estado de partida de seis filas y se aplica y revierte de nuevo, comprobando que vuelven las seis
"${PSQL[@]}" -d $DB <<'SQL'
insert into public.asistencias (id, iglesia_id, casa_oracion_id, miembro_id, fecha, presente, created_at) values
  ('ae230000-0000-0000-0000-000000000001', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-10', true,  '2026-11-10 20:00+00'),
  ('ae230000-0000-0000-0000-000000000002', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a1', '2026-11-10', true,  '2026-11-10 21:00+00'),
  ('ae230000-0000-0000-0000-000000000005', 'ae200000-0000-0000-0000-00000000000a', 'ae210000-0000-0000-0000-0000000000c1', 'ae220000-0000-0000-0000-0000000000a2', '2026-11-10', true,  '2026-11-10 20:00+00');
SQL
"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
[ "$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.asistencias")" = "3" ] || falla "tras aplicar deben quedar 3 filas"
"${PSQL[@]}" -d $DB -f "reversiones/$MIG.down.sql" > /dev/null
[ "$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.asistencias")" = "6" ] || falla "la reversión debe devolver las 3 filas archivadas (6 en total)"
echo "OK: la reversión devuelve las filas duplicadas archivadas"
volcado > /tmp/adn_as_despues.$$.sql
diff -q /tmp/adn_as_antes.$$.sql /tmp/adn_as_despues.$$.sql >/dev/null || { diff /tmp/adn_as_antes.$$.sql /tmp/adn_as_despues.$$.sql | head; falla "la reversión no deja el esquema como estaba"; }
echo "OK: tras revertir, el esquema es idéntico al de antes de aplicar"
rm -f /tmp/adn_as_*.$$.sql
"${PSQL[@]}" -d postgres -c "drop database $DB"
