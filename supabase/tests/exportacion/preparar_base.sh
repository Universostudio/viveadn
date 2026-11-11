#!/usr/bin/env bash
# Crea una base vacia con esquema, catalogo y todas las migraciones. Uso: preparar_base.sh <nombre>
# Nunca apuntar a produccion: la base se borra y se crea de nuevo.
set -euo pipefail
cd "$(dirname "$0")/../.."
DB="$1"
PSQL=(psql -q -v ON_ERROR_STOP=1)
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d "$DB" -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d "$DB" -f tests/stub_supabase.sql
"${PSQL[@]}" -d "$DB" -f schema/esquema_completo.sql
"${PSQL[@]}" -d "$DB" -f schema/seed.sql
for m in migrations/*.sql; do "${PSQL[@]}" -d "$DB" -f "$m" > /dev/null 2>&1; done
