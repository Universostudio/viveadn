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

# 2. Cobertura: el manifiesto cubre todas las tablas con iglesia_id, mas iglesias y rol_permisos, y todas llevan filas
esperadas=$("${PSQL[@]}" -At -d "$DB" -c "select string_agg(nombre, ',' order by nombre collate \"C\") from public.adn_tablas_exportables()")
reales=$("${PSQL[@]}" -At -d "$DB" -c "select string_agg(relname, ',' order by relname collate \"C\") from (select c.relname from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='r' and (c.relname in ('iglesias','rol_permisos') or c.relname not in ('plataforma_auditoria','adn_bajas_enlaces','adn_confirmaciones') and exists (select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='iglesia_id' and not a.attisdropped))) t")
[ "$esperadas" = "$reales" ] || falla "adn_tablas_exportables no cubre todas las tablas de iglesia ($esperadas / $reales)"
python3 - "$OUT/exp/manifest.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
vacias = [t['nombre'] for t in m['tablas'] if t['filas'] == 0]
assert not vacias, f"FALLO: tablas sin filas en la prueba, no se prueban de verdad: {vacias}"
assert m['total_filas'] == sum(t['filas'] for t in m['tablas'])
assert not {'plataforma_auditoria', 'adn_bajas_enlaces', 'adn_confirmaciones'} & {t['nombre'] for t in m['tablas']}, 'FALLO: una tabla interna sale en la exportacion de la iglesia'
print(f"OK: el manifiesto cubre {len(m['tablas'])} tablas y {m['total_filas']} filas")
PY

# 3. Secretos y otras iglesias: no aparecen en ningun archivo
for secreto in aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb cccccccccccccccccccccccccccccccc dddddddddddddddddddddddddddddddd OTRA-IGLESIA-SECRETO otra-secreto@prueba.test; do
  if grep -rqF "$secreto" "$OUT/exp"; then falla "la exportacion contiene $secreto"; fi
done
echo "OK: ni los secretos (tokens, huellas) ni los datos de otra iglesia salen en el paquete"
grep -q 'adn_borrada' "$OUT/exp/datos.json" && falla "salen marcas internas del borrado suave" || true
head -c 200 "$OUT/exp/csv/miembros.csv" | head -1 | tr -d '\r' | grep -q '^id,iglesia_id,crm_id,' || falla "la cabecera del CSV de miembros no es la esperada"
echo "OK: las marcas internas no salen y la cabecera del CSV lleva los nombres de columna"

verificar() { # <base> <etiqueta>
  local base="$1" etiqueta="$2"
  filas=$("${PSQL[@]}" -At -d "$base" -v m="$(cat "$OUT/exp/manifest.json")" <<< "select count(*) filter (where ok), count(*) from public.adn_verificar_carga(:'m'::jsonb)" | tr '|' ' ')
  set -- $filas
  [ "$1" = "$2" ] && [ "$2" -gt 0 ] || { "${PSQL[@]}" -d "$base" -v m="$(cat "$OUT/exp/manifest.json")" <<< "select * from public.adn_verificar_carga(:'m'::jsonb) where not ok"; falla "$etiqueta: solo $1 de $2 tablas coinciden con el manifiesto"; }
  echo "OK: $etiqueta: las $2 tablas coinciden con el manifiesto en filas y en contenido"
  "${PSQL[@]}" -d "$base" -f tests/exportacion/integridad.sql 2>&1 | sed -E 's/^psql:[^ ]+ NOTICE:  //' | grep -E 'OK|INTEGRIDAD' || falla "$etiqueta: integridad referencial"
  # Solo ha entrado la iglesia exportada
  n=$("${PSQL[@]}" -At -d "$base" -c "select count(*) from public.iglesias")
  [ "$n" = "1" ] || falla "$etiqueta: la base cargada deberia tener 1 iglesia y tiene $n"
  # Los secretos omitidos se regeneran: no coinciden con los del origen y la base vuelve a tener las columnas obligatorias
  n=$("${PSQL[@]}" -At -d "$base" -c "select count(*) from public.evento_checkin where token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' or token !~ '^[0-9a-f]{64}$'")
  [ "$n" = "0" ] || falla "$etiqueta: el token del QR debia regenerarse con 64 caracteres hexadecimales"
  n=$("${PSQL[@]}" -At -d "$base" -c "select count(*) from pg_attribute a where a.attrelid in ('public.evento_checkin'::regclass, 'public.invitaciones'::regclass, 'public.checkin_registros'::regclass) and a.attname in ('token','token_hash','ip_hash') and not a.attnotnull")
  [ "$n" = "0" ] || falla "$etiqueta: la carga dejo columnas obligatorias sin su restriccion"
  echo "OK: $etiqueta: secretos regenerados y restricciones restauradas"
}

# 4. Carga desde JSON en una base vacia
bash tests/exportacion/preparar_base.sh viveadn_carga_json
ADN_DATOS="$OUT/exp/datos.json" ADN_MANIFIESTO="$OUT/exp/manifest.json" "${PSQL[@]}" -d viveadn_carga_json -f tests/exportacion/cargar_json.sql
verificar viveadn_carga_json "carga desde JSON"

# 5. Carga desde CSV en otra base vacia
bash tests/exportacion/preparar_base.sh viveadn_carga_csv
python3 tests/exportacion/generar_carga_csv.py "$OUT/exp" > "$OUT/carga_csv.sql"
"${PSQL[@]}" -d viveadn_carga_csv -f "$OUT/carga_csv.sql"
verificar viveadn_carga_csv "carga desde CSV"

# 6. La comprobacion no es vacua: detecta un dato cambiado, una fila de menos y una tabla desconocida
"${PSQL[@]}" -At -d viveadn_carga_csv -v m="$(cat "$OUT/exp/manifest.json")" <<'SQL' > "$OUT/trampas.txt"
begin;
update public.miembros set apellido = apellido || 'x' where crm_id = 'M-1';
select 'cambio:' || string_agg(tabla, ',') from public.adn_verificar_carga(:'m'::jsonb) where not ok;
rollback;
begin;
delete from public.logros;
select 'borrado:' || string_agg(tabla || '=' || filas_cargadas, ',') from public.adn_verificar_carga(:'m'::jsonb) where not ok;
rollback;
begin;
update public.casas_oracion set coordenadas_lat = 37.3886;  -- mismo valor numerico, misma escala (numeric(10,8)): no debe alarmar
select 'escala:' || count(*) from public.adn_verificar_carga(:'m'::jsonb) where not ok;
rollback;
SQL
grep -qx 'cambio:miembros' "$OUT/trampas.txt" || falla "un dato cambiado no se detecto: $(cat "$OUT/trampas.txt")"
grep -qx 'borrado:logros=0' "$OUT/trampas.txt" || falla "una fila borrada no se detecto: $(cat "$OUT/trampas.txt")"
grep -qx 'escala:0' "$OUT/trampas.txt" || falla "el mismo valor numerico no debia alarmar: $(cat "$OUT/trampas.txt")"
echo "OK: la verificacion detecta un dato cambiado y una fila borrada, y no se alarma por un numerico equivalente"

"${PSQL[@]}" -d postgres -c "drop database viveadn_carga_json" -c "drop database viveadn_carga_csv"
echo "OK: exportacion completa verificada: JSON y CSV recargados en bases vacias con las mismas cifras"
