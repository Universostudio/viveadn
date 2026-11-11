#!/usr/bin/env bash
# Prueba de volumen de la exportacion con datos sinteticos: una iglesia con N personas y unas nueve filas por persona
# (contacto, tres consentimientos, cuatro asistencias). Mide, sobre la misma base, la exportacion de una sola respuesta
# (adn_exportar_paquete) y la exportacion por paginas: tiempo, tamano y pico de memoria del proceso que lee el resultado.
# Uso: exportacion_volumen.sh <personas> [filas_por_pagina]
# Nunca apuntar a produccion: crea y borra la base viveadn_volumen. Los datos son inventados (sin nombres ni correos reales).
set -euo pipefail
cd "$(dirname "$0")/../.."
N="$1"
LIM="${2:-1000}"
DB=viveadn_volumen
IGLESIA=ea100000-0000-0000-0000-0000000000aa
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
PSQL=(psql -X -q -v ON_ERROR_STOP=1)
[[ "$N" =~ ^[0-9]+$ ]] || { echo "personas debe ser un numero"; exit 2; }

bash tests/exportacion/preparar_base.sh "$DB"
t0=$(date +%s.%N)
"${PSQL[@]}" -d "$DB" <<SQL
set session_replication_role = replica;
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('$IGLESIA', 'Iglesia de volumen', 'prueba-volumen', 'ES', 'Sevilla', 'premium');
insert into public.zonas (id, iglesia_id, codigo, nombre) values ('ea200000-0000-0000-0000-0000000000aa', '$IGLESIA', 'Z1', 'Zona');
insert into public.casas_oracion (id, iglesia_id, zona_id, codigo_zona, nombre, pais, ciudad, direccion, activa)
  select ('ea300000-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid, '$IGLESIA', 'ea200000-0000-0000-0000-0000000000aa', 'ZN-' || (200000 + g), 'Casa ' || g, 'ES', 'Sevilla', 'Calle ' || g, true
  from generate_series(1, greatest($N / 50, 1)) g;
insert into public.miembros (id, iglesia_id, crm_id, nombre, apellido, email, telefono, fecha_nacimiento, casa_oracion_id, notas, nivel_compromiso, activo)
  select ('ea400000-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid, '$IGLESIA', 'VOL-' || g, 'Persona' || g, 'Sintetica, "' || g || '"',
         'p' || g || '@volumen.test', '+34600' || lpad(g::text, 6, '0'), date '1960-01-01' + (g % 20000),
         ('ea300000-0000-0000-0000-' || lpad(to_hex(1 + g % greatest($N / 50, 1)), 12, '0'))::uuid,
         case when g % 7 = 0 then E'Nota con salto\r\nde linea, y coma' end, 'nuevo', true
  from generate_series(1, $N) g;
insert into public.adn_miembro_contactos (iglesia_id, miembro_id, tipo, valor)
  select '$IGLESIA', ('ea400000-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid, 'correo', 'alt' || g || '@volumen.test' from generate_series(1, $N) g;
insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen)
  select '$IGLESIA', ('ea400000-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid, c, 'sin_dato', 'volumen'
  from generate_series(1, $N) g, unnest(array['email','sms','whatsapp']) c;
insert into public.asistencias (iglesia_id, casa_oracion_id, miembro_id, fecha, presente)
  select '$IGLESIA', ('ea300000-0000-0000-0000-' || lpad(to_hex(1 + g % greatest($N / 50, 1)), 12, '0'))::uuid,
         ('ea400000-0000-0000-0000-' || lpad(to_hex(g), 12, '0'))::uuid, date '2026-01-01' + s, (g + s) % 5 <> 0
  from generate_series(1, $N) g, generate_series(0, 3) s;
reset session_replication_role;
analyze;
SQL
t1=$(date +%s.%N)
echo "datos sinteticos: $N personas, $("${PSQL[@]}" -At -d "$DB" -c "select count(*) from public.miembros") miembros, preparados en $(printf '%.0f' "$(echo "$t1 - $t0" | bc)") s"

echo "--- antes: una sola respuesta (adn_exportar_paquete)"
set +e
python3 -I - "$DB" "$IGLESIA" "$OUT/paquete.json" <<'PY' 2> "$OUT/err.txt"
import resource, subprocess, sys, time
db, ig, salida = sys.argv[1:4]
t = time.time()
with open(salida, 'wb') as f:
    r = subprocess.run(['psql', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', f"select public.adn_exportar_paquete('{ig}')"], stdout=f, stderr=subprocess.PIPE)
print(f"tiempo {time.time() - t:.1f} s, memoria maxima del cliente psql {resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024:.0f} MB")
if r.returncode: print(r.stderr.decode()[:300], file=sys.stderr)
sys.exit(r.returncode)
PY
estado=$?
set -e
cat "$OUT/err.txt" | tail -3
echo "estado=$estado, tamano de la respuesta: $(stat -c %s "$OUT/paquete.json" 2>/dev/null || echo 0) bytes"
rm -f "$OUT/paquete.json"

echo "--- despues: por paginas de $LIM filas"
PGDATABASE="$DB" node --max-old-space-size=2048 tests/exportacion/exportar_paginado.mts "$DB" "$IGLESIA" "$OUT/paginado.zip" "$LIM"
echo "tamano del ZIP: $(stat -c %s "$OUT/paginado.zip") bytes"
python3 -I - "$OUT/paginado.zip" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
bad = z.testzip()
sys.exit(f"FALLO: ZIP corrupto: {bad}") if bad else print(f"OK: ZIP integro, {len(z.namelist())} archivos")
PY
