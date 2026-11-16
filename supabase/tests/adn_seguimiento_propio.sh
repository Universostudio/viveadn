#!/usr/bin/env bash
# Fase 3: reversión de 20261111340000_adn_seguimiento_propio. Con métodos propios y procesos ya creados, revertir deja el esquema idéntico al anterior,
# CONSERVA los métodos propios, la configuración y los procesos (siguen calculando con su método), los procesos nuevos vuelven a OP72 y ya no se puede escribir
# desde la web; volver a aplicar y a revertir termina en el mismo esquema.
# Uso: bash tests/adn_seguimiento_propio.sh [base_temporal]
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${1:-adn_propio_t}
PSQL=(psql -q -v ON_ERROR_STOP=1)
MIG=20261111340000_adn_seguimiento_propio
volcado() { pg_dump -s --no-owner -d "$DB" | grep -vE '^\\(un)?restrict '; }
falla() { echo "FALLO: $*"; "${PSQL[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; exit 1; }
sql() { "${PSQL[@]}" -d $DB -At -c "$1" | tail -1; }
como_propietaria() { "${PSQL[@]}" -d $DB -At <<SQL | tail -1
select set_config('request.jwt.claim.sub', 'ae500000-0000-0000-0000-000000000001', false);
set role authenticated;
$1
SQL
}
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
for m in migrations/*.sql; do [ "$m" = "migrations/$MIG.sql" ] && continue; "${PSQL[@]}" -d $DB -f "$m" > /dev/null; done
"${PSQL[@]}" -d $DB <<'SQL'
insert into auth.users (id) values ('ae500000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('ae510000-0000-0000-0000-00000000000a', 'Prueba Propio T', 'prueba-propio-t', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values ('ae500000-0000-0000-0000-000000000001', 'ae510000-0000-0000-0000-00000000000a', 'P', 'T', 'pt@propio.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) select ('ae530000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'ae510000-0000-0000-0000-00000000000a', 'M' || n, 'Prueba' from generate_series(1, 4) n;
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion)
  select ('ae540000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'ae510000-0000-0000-0000-00000000000a', ('ae530000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, now() - (n * 20 || ' hours')::interval
    from generate_series(1, 3) n;
SQL
volcado > /tmp/adn_propio_antes.$$.sql
# Estado de los procesos de partida (método, fecha límite, color): lo que NO debe cambiar al aplicar
ESTADO0=$(sql "select string_agg(metodo_id || '/' || fecha_limite || '/' || estado_alerta, ',' order by id) from public.consolidaciones")

"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
ESTADO1=$(sql "select string_agg(metodo_id || '/' || fecha_limite || '/' || estado_alerta, ',' order by id) from public.consolidaciones")
[ "$ESTADO0" = "$ESTADO1" ] || { echo "$ESTADO0"; echo "$ESTADO1"; falla "aplicar la fase 3 cambia procesos existentes"; }
echo "OK: aplicar la fase 3 no cambia ningún proceso existente (método, fecha límite ni color)"

# Con la web: la propietaria crea su método, lo elige, y un proceso nuevo lo toma
[ "$(como_propietaria "insert into public.adn_seguimiento_metodos (id, iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('ae550000-0000-0000-0000-0000000000a1', 'ae510000-0000-0000-0000-00000000000a', 'propio_t', 'Mío', 2, 40, 10, 20) returning clave;")" = "propio_t" ] || falla "la propietaria no pudo crear su método"
como_propietaria "insert into public.adn_seguimiento_config (iglesia_id, metodo_id) values ('ae510000-0000-0000-0000-00000000000a', 'ae550000-0000-0000-0000-0000000000a1') returning 1;" >/dev/null
"${PSQL[@]}" -d $DB -c "insert into public.miembros (id, iglesia_id, nombre, apellido) values ('ae530000-0000-0000-0000-0000000000a9', 'ae510000-0000-0000-0000-00000000000a', 'N', 'Nueva'); insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion) values ('ae540000-0000-0000-0000-0000000000a9', 'ae510000-0000-0000-0000-00000000000a', 'ae530000-0000-0000-0000-0000000000a9', now() - interval '30 hours')" >/dev/null
[ "$(sql "select metodo_id from public.consolidaciones where id = 'ae540000-0000-0000-0000-0000000000a9'")" = "ae550000-0000-0000-0000-0000000000a1" ] || falla "el proceso nuevo no tomó el método activo"
echo "OK: con la fase 3 aplicada, el proceso nuevo toma el método propio elegido (40 horas)"

# Reversión
"${PSQL[@]}" -d $DB -f "reversiones/$MIG.down.sql" > /dev/null
volcado > /tmp/adn_propio_despues.$$.sql
diff -q /tmp/adn_propio_antes.$$.sql /tmp/adn_propio_despues.$$.sql >/dev/null || { diff /tmp/adn_propio_antes.$$.sql /tmp/adn_propio_despues.$$.sql | head -20; falla "la reversión no deja el esquema como estaba"; }
echo "OK: tras revertir, el esquema es idéntico al de antes de aplicar"
[ "$(sql "select count(*) from public.adn_seguimiento_metodos where id = 'ae550000-0000-0000-0000-0000000000a1'")" = "1" ] || falla "la reversión borró el método propio"
[ "$(sql "select count(*) from public.adn_seguimiento_config")" = "1" ] || falla "la reversión borró la configuración"
[ "$(sql "select metodo_id from public.consolidaciones where id = 'ae540000-0000-0000-0000-0000000000a9'")" = "ae550000-0000-0000-0000-0000000000a1" ] || falla "la reversión cambió el método de un proceso"
[ "$(sql "select estado from public.adn_seguimiento_estado where id = 'ae540000-0000-0000-0000-0000000000a9'")" = "naranja" ] || falla "el proceso con método propio dejó de calcular con él (30 horas con colores a 10 y 20 y plazo de 40 es naranja)"
echo "OK: tras revertir se conservan el método propio, la configuración y el proceso, que sigue calculando con su método"
"${PSQL[@]}" -d $DB -c "insert into public.miembros (id, iglesia_id, nombre, apellido) values ('ae530000-0000-0000-0000-0000000000b9', 'ae510000-0000-0000-0000-00000000000a', 'O', 'Otra'); insert into public.consolidaciones (id, iglesia_id, miembro_id) values ('ae540000-0000-0000-0000-0000000000b9', 'ae510000-0000-0000-0000-00000000000a', 'ae530000-0000-0000-0000-0000000000b9')" >/dev/null
[ "$(sql "select metodo_id from public.consolidaciones where id = 'ae540000-0000-0000-0000-0000000000b9'")" = "5e000000-0000-4000-8000-000000000072" ] || falla "tras revertir un proceso nuevo debe nacer con OP72"
echo "OK: tras revertir, un proceso nuevo vuelve a nacer con OP72"
if como_propietaria "insert into public.adn_seguimiento_metodos (iglesia_id, clave, nombre, pasos, plazo_horas, umbral_amarillo_horas, umbral_naranja_horas) values ('ae510000-0000-0000-0000-00000000000a', 'otro', 'X', 1, 72, 24, 48) returning 1;" >/dev/null 2>&1; then falla "tras revertir la web todavía puede crear métodos"; fi
echo "OK: tras revertir la web ya no puede crear métodos"

# Volver a aplicar y revertir: mismo esquema, y el módulo vuelve a existir
"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
[ "$(sql "select count(*) from public.plan_modulos where modulo = 'seguimiento_propio'")" = "1" ] || falla "al volver a aplicar falta el módulo"
"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null || falla "repetir la migración da error"
"${PSQL[@]}" -d $DB -f "reversiones/$MIG.down.sql" > /dev/null
volcado > /tmp/adn_propio_final.$$.sql
diff -q /tmp/adn_propio_antes.$$.sql /tmp/adn_propio_final.$$.sql >/dev/null || falla "tras aplicar, repetir y revertir el esquema no coincide"
echo "OK: aplicar, repetir y revertir termina siempre en el mismo esquema"
rm -f /tmp/adn_propio_*.$$.sql
"${PSQL[@]}" -d postgres -c "drop database $DB"
