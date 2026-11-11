#!/usr/bin/env bash
# Prueba de la exportacion completa: exporta una iglesia sintetica, carga el paquete (JSON y CSV) en dos bases
# vacias y compara cifras y contenido con el manifiesto. Uso: exportacion_carga.sh <base_con_migraciones>
# Nunca apuntar a produccion: crea y borra las bases viveadn_carga_json y viveadn_carga_csv.
set -euo pipefail
cd "$(dirname "$0")/.."
DB="$1"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
PSQL=(psql -q -v ON_ERROR_STOP=1)
falla() { echo "FALLO: $*"; exit 1; }

# 1. Exportar la iglesia de prueba (deja la base de origen como estaba)
"${PSQL[@]}" -At -d "$DB" -v salida="$OUT/paquete.json" -f tests/exportacion/origen.sql
python3 tests/exportacion/desempaquetar.py "$OUT/paquete.json" "$OUT/exp"

bash tests/exportacion/verificar_paquete.sh "$DB" "$OUT/exp"
echo "OK: exportacion completa verificada: JSON y CSV recargados en bases vacias con las mismas cifras"
