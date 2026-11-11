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
"${PSQL[@]}" -d $DB -f tests/adn_ciclo_vida.sql
"${PSQL[@]}" -d $DB -f tests/adn_importar_contactos.sql
"${PSQL[@]}" -d $DB -f tests/adn_informes.sql
"${PSQL[@]}" -d $DB -f tests/adn_comunicacion.sql
"${PSQL[@]}" -d $DB -f tests/adn_panel_inicio.sql
"${PSQL[@]}" -d $DB -f tests/adn_descargas_informe.sql
"${PSQL[@]}" -d $DB -f tests/adn_consentimiento.sql
"${PSQL[@]}" -d $DB -f tests/adn_consentimiento_evidencia.sql
"${PSQL[@]}" -d $DB -f tests/adn_checkin_canales.sql
"${PSQL[@]}" -d $DB -f tests/adn_doble_confirmacion.sql
"${PSQL[@]}" -d $DB -f tests/auth_usuarios_sin_nulos_autoprueba.sql
"${PSQL[@]}" -At -d $DB -f tests/auth_usuarios_sin_nulos.sql
"${PSQL[@]}" -At -d $DB -v salida=/dev/null -v despues=tests/adn_aislamiento_total.sql -f tests/exportacion/origen.sql
"${PSQL[@]}" -d $DB -f tests/limites_plan.sql
bash tests/limites_concurrencia.sh "$DB"
bash tests/formacion_concurrencia.sh "$DB"
bash tests/exportacion_carga.sh "$DB"
bash tests/adn_reversion.sh
