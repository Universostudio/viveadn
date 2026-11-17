#!/usr/bin/env bash
# Monta en LOCAL una base en el estado que tiene hoy el proyecto real: esquema base, catálogo y las migraciones hasta la última que el real tiene registrada.
# Uso (como el usuario postgres): scripts/entorno/traspaso_base.sh <base> [<ultima_migracion>|todas]
set -euo pipefail
cd "$(dirname "$0")/../../supabase"
DB=$1; HASTA=${2:-20261106011008}
export PGOPTIONS="-c search_path=public,extensions"
P=(psql -q -v ON_ERROR_STOP=1)
"${P[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
"${P[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions" >/dev/null
"${P[@]}" -d $DB -f tests/stub_supabase.sql >/dev/null
"${P[@]}" -d $DB -f schema/esquema_completo.sql >/dev/null
"${P[@]}" -d $DB -f schema/seed.sql >/dev/null
for m in migrations/*.sql; do
  v=$(basename "$m" | cut -c1-14)
  if [ "$HASTA" != "todas" ] && [[ "$v" > "$HASTA" ]]; then continue; fi
  "${P[@]}" -d $DB -f "$m" >/dev/null 2>&1 || { echo "FALLA $m"; "${P[@]}" -d $DB -f "$m" 2>&1 | tail -5; exit 1; }
done
echo "base $DB montada hasta $HASTA"
