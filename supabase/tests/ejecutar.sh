#!/usr/bin/env bash
# Crea una base vacia, aplica esquema, catalogo y migraciones, y ejecuta las pruebas.
# Uso: PGHOST=... PGPORT=... PGUSER=postgres supabase/tests/ejecutar.sh
# Nunca apuntar a produccion: la base de prueba se borra y se crea de nuevo.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=viveadn_pruebas
PSQL=(psql -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
for m in migrations/*.sql; do
  echo "Aplicando $m"
  "${PSQL[@]}" -d $DB -f "$m"
done
"${PSQL[@]}" -d $DB -f tests/aislamiento.sql
"${PSQL[@]}" -d $DB -f tests/roles_nuevos.sql
"${PSQL[@]}" -d $DB -f tests/invitaciones.sql
"${PSQL[@]}" -d $DB -f tests/permisos.sql
"${PSQL[@]}" -d $DB -f tests/eventos.sql
"${PSQL[@]}" -d $DB -f tests/checkin.sql
bash tests/checkin_concurrencia.sh "$DB"
"${PSQL[@]}" -d $DB -f tests/dar_plantillas.sql
"${PSQL[@]}" -d $DB -f tests/enlaces_dar.sql
"${PSQL[@]}" -d $DB -f tests/red_iglesias.sql
"${PSQL[@]}" -d $DB -f tests/registro.sql
"${PSQL[@]}" -d $DB -f tests/referencias_cruzadas.sql
"${PSQL[@]}" -d $DB -f tests/ciclo_vida.sql
"${PSQL[@]}" -d $DB -f tests/exportar_borrar.sql
"${PSQL[@]}" -d $DB -f tests/archivos.sql
"${PSQL[@]}" -d $DB -f tests/modo_alias.sql
"${PSQL[@]}" -d $DB -f tests/op72_avanzado.sql
"${PSQL[@]}" -d $DB -f tests/motor_formacion.sql
"${PSQL[@]}" -d $DB -f tests/certificados.sql
"${PSQL[@]}" -d $DB -f tests/precios_catalogo.sql
"${PSQL[@]}" -d $DB -f tests/altas_iglesia.sql
"${PSQL[@]}" -d $DB -f tests/limites_plan.sql
bash tests/limites_concurrencia.sh "$DB"
bash tests/formacion_concurrencia.sh "$DB"
# La reversion del catalogo de precios lo borra sin tocar planes ni modulos, y se puede volver a aplicar
"${PSQL[@]}" -d $DB -f reversiones/20261116120000_precios_catalogo.down.sql
"${PSQL[@]}" -d $DB -c "do \$\$ begin if to_regclass('public.precios_plan') is not null or (select count(*) from public.planes) <> 3 then raise exception 'FALLO: la reversion de precios no dejo la base como antes'; end if; raise notice 'OK: la reversion de precios deja la base como antes'; end \$\$"
"${PSQL[@]}" -d $DB -f migrations/20261116120000_precios_catalogo.sql
"${PSQL[@]}" -d $DB -f tests/precios_catalogo.sql

# La reversion de altas deja la base como antes y se puede volver a aplicar
"${PSQL[@]}" -d $DB -f reversiones/20261116130000_altas_iglesia.down.sql
"${PSQL[@]}" -d $DB -c "do \$\$ begin if to_regclass('public.altas_iglesia') is not null or to_regclass('public.iglesias') is null then raise exception 'FALLO: la reversion de altas no dejo la base como antes'; end if; raise notice 'OK: la reversion de altas deja la base como antes'; end \$\$"
"${PSQL[@]}" -d $DB -f migrations/20261116130000_altas_iglesia.sql
"${PSQL[@]}" -d $DB -f tests/altas_iglesia.sql
