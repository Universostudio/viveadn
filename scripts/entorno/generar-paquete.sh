#!/usr/bin/env bash
# Regenera supabase/paquete-pruebas: calcula en una base LOCAL de referencia (montada con montar-rama.sh) las huellas esperadas, genera los
# archivos SQL numerados y comprueba el resultado con supabase/tests/paquete_pruebas.sh. Solo local: crea y borra las bases viveadn_paquete_*.
# Uso (con acceso a un PostgreSQL local, por ejemplo como el usuario postgres): scripts/entorno/generar-paquete.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
SAL="${SALIDA:-supabase/paquete-pruebas}"   # SALIDA permite escribir en otra carpeta si el usuario de PostgreSQL no puede escribir en el repositorio
TMP=$(mktemp -d)
REF=viveadn_paquete_ref
trap 'rm -rf "$TMP"; psql -q -d postgres -c "drop database if exists '$REF'" >/dev/null 2>&1 || true' EXIT
psql -q -d postgres -c "drop database if exists $REF" -c "create database $REF" >/dev/null
DATABASE_URL="postgresql:///$REF" bash scripts/entorno/montar-rama.sh --rama-de-pruebas --con-stub >/dev/null
# search_path vacío, igual que 99_verificacion.sql, para que las expresiones se muestren con nombres completos
(echo "set search_path = pg_catalog;"; cat scripts/entorno/huellas.sql) | psql -X -q -At -F'|' -d "$REF" > "$TMP/esperados.txt"
mkdir -p "$SAL"
node scripts/entorno/generar-paquete.mts --salida "$SAL" --esperados "$TMP/esperados.txt"
cp "$TMP/esperados.txt" "$SAL/esperados.txt"
PAQUETE="$SAL" bash supabase/tests/paquete_pruebas.sh
