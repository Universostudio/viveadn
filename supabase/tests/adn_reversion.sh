#!/usr/bin/env bash
# Demuestra que la reversion de 20261111120000_adn_ciclo_vida deja el esquema identico al anterior,
# no pierde datos de negocio y que la migracion se puede volver a aplicar.
# Usa su propia base desechable. Nunca apuntar a produccion.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=viveadn_reversion
UP=migrations/20261111120000_adn_ciclo_vida.sql
DOWN=reversiones/20261111120000_adn_ciclo_vida.down.sql
PSQL=(psql -q -v ON_ERROR_STOP=1)
# pg_dump 16 añade un token aleatorio (\restrict) en cada volcado: se filtra para poder comparar
volcado() { pg_dump -s --no-owner -d "$DB" | grep -vE '^\\(un)?restrict '; }

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
for m in migrations/*.sql; do
  [ "$m" = "$UP" ] && continue
  "${PSQL[@]}" -d $DB -f "$m" > /dev/null
done
volcado > /tmp/adn_antes.$$.sql

# Aplicar, usarla y revertir
"${PSQL[@]}" -d $DB -f "$UP"
"${PSQL[@]}" -d $DB <<'SQL'
insert into auth.users (id) values ('ae000000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ae100000-0000-0000-0000-00000000000a', 'Prueba Reversion', 'prueba-reversion', 'ES', 'Sevilla', 'premium');
insert into public.miembros (iglesia_id, nombre, apellido) values ('ae100000-0000-0000-0000-00000000000a', 'M', 'R');
select public.adn_borrar_suave('ae100000-0000-0000-0000-00000000000a', null, 'prueba de reversion');
SQL
"${PSQL[@]}" -d $DB -f "$DOWN"
volcado > /tmp/adn_despues.$$.sql

if ! diff -u /tmp/adn_antes.$$.sql /tmp/adn_despues.$$.sql > /tmp/adn_diff.$$.txt; then
  echo "FALLO: la reversion no deja el esquema como estaba:"; head -40 /tmp/adn_diff.$$.txt; exit 1
fi
echo "OK: tras revertir, el esquema es identico al de antes de la migracion"

# Los datos de negocio sobreviven y la iglesia en borrado suave queda protegida por el mecanismo anterior
res=$("${PSQL[@]}" -d $DB -At -c "select etapa || ',' || (borrado_programado_en is not null) || ',' || (select count(*) from public.miembros) from public.iglesias where slug = 'prueba-reversion'")
[ "$res" = "suspendida,true,1" ] || { echo "FALLO: se esperaba suspendida,true,1 y salio $res"; exit 1; }
echo "OK: la reversion conserva la iglesia, sus miembros y su plazo de borrado"

# Reaplicar la migracion sobre lo revertido
"${PSQL[@]}" -d $DB -f "$UP"
"${PSQL[@]}" -d $DB -f "$DOWN"
volcado > /tmp/adn_despues2.$$.sql
diff -q /tmp/adn_antes.$$.sql /tmp/adn_despues2.$$.sql > /dev/null || { echo "FALLO: aplicar, revertir y volver a aplicar no es idempotente"; exit 1; }
echo "OK: aplicar, revertir y volver a aplicar y revertir termina siempre en el mismo esquema"
rm -f /tmp/adn_*.$$.*
"${PSQL[@]}" -d postgres -c "drop database $DB"
