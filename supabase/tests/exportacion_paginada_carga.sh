#!/usr/bin/env bash
# Prueba de la exportacion por paginas de extremo a extremo: carga la iglesia sintetica en una base, la exporta con el mismo
# recorrido que usa el panel (paginas de 2 filas, para forzar muchas paginas), lee el ZIP resultante con Python y pasa el
# paquete por la misma verificacion que la exportacion de una sola respuesta (recarga JSON y CSV en bases vacias).
# Uso: exportacion_paginada_carga.sh <base_con_migraciones>
# Nunca apuntar a produccion: crea y borra las bases viveadn_pag_origen, viveadn_carga_json y viveadn_carga_csv.
set -euo pipefail
cd "$(dirname "$0")/.."
DB="$1"
ORIGEN=viveadn_pag_origen
IGLESIA=ea100000-0000-0000-0000-00000000000a
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"; psql -q -d postgres -c "drop database if exists $ORIGEN" >/dev/null 2>&1 || true' EXIT
PSQL=(psql -q -v ON_ERROR_STOP=1)
falla() { echo "FALLO: $*"; exit 1; }

bash tests/exportacion/preparar_base.sh "$ORIGEN"
"${PSQL[@]}" -At -d "$ORIGEN" -v salida=/dev/null -v conservar=1 -f tests/exportacion/origen.sql

# Paginas de 2 filas y paginas por defecto: las dos deben dar un paquete verificable
for filas in 2 1000; do
  rm -rf "$OUT/exp" "$OUT/p.zip"
  cifras=$(PGUSER="${PGUSER:-postgres}" node tests/exportacion/exportar_paginado.mts "$ORIGEN" "$IGLESIA" "$OUT/p.zip" "$filas")
  echo "paginas de $filas filas: $cifras"
  python3 -I - "$OUT/p.zip" "$OUT/exp" "$cifras" <<'PY'
import json, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
bad = z.testzip()
if bad: sys.exit(f"FALLO: el ZIP tiene un archivo corrupto: {bad}")
nombres = z.namelist()
if len(nombres) != len(set(nombres)): sys.exit("FALLO: nombres repetidos en el ZIP")
z.extractall(sys.argv[2])
m = json.load(open(sys.argv[2] + '/manifest.json', encoding='utf-8'))
c = json.loads(sys.argv[3])
if not m.get('paginado'): sys.exit("FALLO: el manifiesto no marca paginado")
if m.get('cambios_durante_la_exportacion'): sys.exit("FALLO: cambios detectados sin que nadie escribiera")
if c['cambios']: sys.exit("FALLO: el recorrido marca cambios")
if m['total_filas'] != c['filas']: sys.exit("FALLO: total de filas distinto")
d = json.load(open(sys.argv[2] + '/datos.json', encoding='utf-8'))
if sum(len(v) for v in d['tablas'].values()) + (1 if d['iglesia'] else 0) != m['total_filas']: sys.exit("FALLO: filas de datos.json distintas del manifiesto")
print(f"OK: ZIP integro, {len(nombres)} archivos, {m['total_filas']} filas")
PY
  bash tests/exportacion/verificar_paquete.sh "$DB" "$OUT/exp"
done
echo "OK: exportacion por paginas verificada de extremo a extremo (paginas de 2 y de 1000 filas)"
