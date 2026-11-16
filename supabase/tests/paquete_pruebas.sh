#!/usr/bin/env bash
# Prueba del paquete de aplicación (supabase/paquete-pruebas): (1) está al día con las fuentes, (2) aplicado con psql tal cual sobre una base vacía
# con un esquema auth mínimo, su verificación sale toda en verde, (3) el esquema resultante es idéntico al de montar-rama.sh y (4) el archivo 00
# se niega a tocar una base que ya tiene el esquema. Crea y borra las bases viveadn_paquete_a y viveadn_paquete_b. Solo local.
set -euo pipefail
cd "$(dirname "$0")/../.."
PAQ="${PAQUETE:-supabase/paquete-pruebas}"
A=viveadn_paquete_a; B=viveadn_paquete_b; C=viveadn_paquete_c
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; psql -q -d postgres -c "drop database if exists '$A'" -c "drop database if exists '$B'" -c "drop database if exists '$C'" >/dev/null 2>&1 || true' EXIT
falla() { echo "FALLO: $*"; exit 1; }

# 1. Al día: regenerar en una carpeta temporal y comparar con la versionada
node scripts/entorno/generar-paquete.mts --salida "$TMP/regenerado" --esperados "$PAQ/esperados.txt" >/dev/null
diff -r -x esperados.txt "$PAQ" "$TMP/regenerado" >/dev/null || falla "supabase/paquete-pruebas no está al día: ejecutar scripts/entorno/generar-paquete.sh"
echo "OK: el paquete está al día con las fuentes"
for f in "$PAQ"/*.sql; do [ "$(wc -c < "$f")" -le 100000 ] || falla "$f supera 100 KB"; done
echo "OK: ningún archivo supera 100 KB"
! grep -rqiE "service_role_key|eyJ[a-zA-Z0-9_-]{20,}|postgres(ql)?://[^ ]*:[^ ]*@" "$PAQ" || falla "el paquete contiene algo parecido a una clave"
echo "OK: el paquete no contiene claves"

# 2. Aplicado con psql tal cual, sin variables de sesión
psql -q -d postgres -c "drop database if exists $A" -c "drop database if exists $B" -c "create database $A" -c "create database $B" >/dev/null
psql -q -v ON_ERROR_STOP=1 -d $A -f supabase/tests/stub_supabase.sql >/dev/null
for f in "$PAQ"/0*.sql; do
  psql -q -X -v ON_ERROR_STOP=1 -d $A -f "$f" >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; falla "falló $f"; }
done
echo "OK: los archivos 00 a $(ls "$PAQ" | grep -c '^[0-9][0-9]_aplicar') se aplican sin error"
resultado=$(psql -q -X -At -F'|' -v ON_ERROR_STOP=1 -d $A -f "$PAQ/99_verificacion.sql")
echo "$resultado" | grep -q '^zz_todo_ok||' || falla "no sale la fila de resumen"
[ "$(echo "$resultado" | grep '^zz_todo_ok' | cut -d'|' -f4)" = "t" ] || { echo "$resultado" | awk -F'|' '$4 != "t"'; falla "la verificación no sale toda en verde"; }
echo "OK: la verificación sale toda en verde ($(echo "$resultado" | grep -vc '^zz_todo_ok') comprobaciones)"

# 3. Idéntico a montar-rama.sh
DATABASE_URL="postgresql:///$B" bash scripts/entorno/montar-rama.sh --rama-de-pruebas --con-stub >/dev/null
pg_dump -s --no-owner -d $A | grep -v '^\\\(un\)\?restrict' > "$TMP/a.sql"
pg_dump -s --no-owner -d $B | grep -v '^\\\(un\)\?restrict' > "$TMP/b.sql"
diff -q "$TMP/a.sql" "$TMP/b.sql" >/dev/null || { diff "$TMP/a.sql" "$TMP/b.sql" | head; falla "el esquema del paquete difiere del de montar-rama.sh"; }
echo "OK: el esquema del paquete es idéntico al de montar-rama.sh"

# 3 bis. Incremental: un proyecto con el paquete hasta la última migración ya aplicada (scripts/entorno/incremental.json) y el incremental encima
# queda idéntico al del paquete completo, y la verificación del incremental sale toda en verde (y detecta una función que falta)
DESDE=$(python3 -I -c "import json;print(json.load(open('scripts/entorno/incremental.json'))['desde'])")
[ -f "$PAQ/incremental/01_aplicar_incremental.sql" ] || falla "no hay archivo incremental en $PAQ/incremental"
psql -q -d postgres -c "drop database if exists $C" -c "create database $C" >/dev/null
psql -q -v ON_ERROR_STOP=1 -d $C -f supabase/tests/stub_supabase.sql >/dev/null
for f in "$PAQ"/0*.sql; do
  # El paquete completo ya incluye las migraciones nuevas: la base de partida se corta justo antes de la primera posterior a DESDE
  awk -v desde="$DESDE" '/^-- ===== migrations\// { if (substr($0, 21, 14) > desde) exit } { print }' "$f" > "$TMP/base.sql"
  psql -q -X -v ON_ERROR_STOP=1 -d $C -f "$TMP/base.sql" >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; falla "falló la base de partida con $f"; }
done
if psql -q -X -At -d $C -f "$PAQ/incremental/99_verificacion_incremental.sql" 2>/dev/null | grep -q '^zz_todo_ok|||t$'; then falla "la verificación del incremental sale en verde ANTES de aplicarlo"; fi
echo "OK: antes del incremental, su verificación no sale en verde"
psql -q -X -v ON_ERROR_STOP=1 -d $C -f "$PAQ/incremental/01_aplicar_incremental.sql" >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; falla "falló el incremental"; }
ri=$(psql -q -X -At -F'|' -v ON_ERROR_STOP=1 -d $C -f "$PAQ/incremental/99_verificacion_incremental.sql")
echo "$ri" | grep -q '^zz_todo_ok|||t$' || { echo "$ri" | awk -F'|' '$4 != "t"'; falla "la verificación del incremental no sale toda en verde"; }
echo "OK: el incremental se aplica y su verificación sale toda en verde ($(echo "$ri" | grep -vc '^zz_todo_ok') comprobaciones)"
pg_dump -s --no-owner -d $C | grep -v '^\\\(un\)\?restrict' > "$TMP/c.sql"
diff -q "$TMP/a.sql" "$TMP/c.sql" >/dev/null || { diff "$TMP/a.sql" "$TMP/c.sql" | head; falla "base parcial + incremental difiere del paquete completo"; }
echo "OK: base parcial más incremental es idéntica al paquete completo"
# Repetirlo no hace daño: las funciones se crean con «create or replace» y los permisos se repiten tal cual
psql -q -X -v ON_ERROR_STOP=1 -d $C -f "$PAQ/incremental/01_aplicar_incremental.sql" >/dev/null 2>&1 || falla "el incremental falla al repetirlo"
pg_dump -s --no-owner -d $C | grep -v '^\\\(un\)\?restrict' > "$TMP/c2.sql"
diff -q "$TMP/a.sql" "$TMP/c2.sql" >/dev/null || falla "repetir el incremental cambia el esquema"
echo "OK: repetir el incremental es inofensivo y no cambia el esquema"
# Se quita un objeto de lo que añade el incremental actual (el límite de tickets abiertos del soporte)
psql -q -X -d $C -c "drop trigger adn_tickets_limite on public.adn_tickets" >/dev/null
[ "$(psql -q -X -At -F'|' -d $C -f "$PAQ/incremental/99_verificacion_incremental.sql" | grep '^zz_todo_ok' | cut -d'|' -f4)" = "f" ] || falla "la verificación del incremental no detecta una función que falta"
echo "OK: la verificación del incremental detecta una función que falta"

# 4. El archivo 00 se niega a tocar una base con el esquema, y una sin Supabase
if psql -q -X -v ON_ERROR_STOP=1 -d $A -f "$PAQ/00_comprobar_base_vacia.sql" >/dev/null 2>"$TMP/err"; then falla "el archivo 00 acepta una base que ya tiene el esquema"; fi
grep -q "ya tiene el esquema" "$TMP/err" || falla "mensaje inesperado del archivo 00: $(cat "$TMP/err")"
echo "OK: el archivo 00 rechaza una base que ya tiene el esquema"
psql -q -d postgres -c "drop database if exists $B" -c "create database $B" >/dev/null
if psql -q -X -v ON_ERROR_STOP=1 -d $B -f "$PAQ/00_comprobar_base_vacia.sql" >/dev/null 2>"$TMP/err"; then falla "el archivo 00 acepta una base sin auth.users"; fi
grep -q "auth.users" "$TMP/err" || falla "mensaje inesperado: $(cat "$TMP/err")"
echo "OK: el archivo 00 rechaza una base que no es de Supabase"

# 4 bis. Funciones de borde y datos de demostración
python3 -I - "$PAQ/funciones.json" <<'PY' || falla "el manifiesto de funciones no coincide con los archivos"
import hashlib, json, os, sys
m = json.load(open(sys.argv[1]))['funciones']
base = os.path.join('supabase', 'functions')
en_disco = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))
if [f['nombre'] for f in m] != en_disco: sys.exit(f"funciones distintas: {[f['nombre'] for f in m]} frente a {en_disco}")
for f in m:
    ruta = os.path.join(base, f['nombre'])
    if sorted(a['ruta'] for a in f['archivos']) != sorted(x for x in os.listdir(ruta) if x.endswith('.ts')): sys.exit(f"archivos distintos en {f['nombre']}")
    if f['entrada'] not in [a['ruta'] for a in f['archivos']]: sys.exit(f"{f['nombre']} sin entrada")
    for a in f['archivos']:
        d = open(os.path.join(ruta, a['ruta']), 'rb').read()
        if hashlib.sha256(d).hexdigest() != a['sha256'] or len(d) != a['bytes']: sys.exit(f"sha256 o tamaño distinto en {f['nombre']}/{a['ruta']}")
sin = sorted(f['nombre'] for f in m if not f['verify_jwt'])
if sin != ['baja', 'confirmar-suscripcion', 'enviar-confirmaciones']: sys.exit(f"verify_jwt inesperado: {sin}")
print(len(m), 'funciones')
PY
echo "OK: el manifiesto de funciones coincide con los archivos (11 funciones, tres sin JWT)"
! grep -q '^\\' "$PAQ/datos_demo.sql" || falla "datos_demo.sql contiene órdenes de psql"
psql -q -X -d $A -c "insert into public.iglesias (nombre, slug, pais, ciudad, plan, es_demo) values ('Iglesia Demo', 'iglesia-demo', 'ES', 'Sevilla', 'premium', true)" >/dev/null
psql -q -X -v ON_ERROR_STOP=1 -d $A -f "$PAQ/datos_demo.sql" >/dev/null 2>&1 || falla "datos_demo.sql falla sobre una iglesia demo"
cifras=$(psql -q -X -At -d $A -c "select (select count(*) from public.miembros) || ',' || (select count(*) from public.zonas) || ',' || (select count(*) from public.casas_oracion)")
[ "$cifras" = "300,6,18" ] || falla "datos_demo.sql dejó $cifras en lugar de 300,6,18"
echo "OK: datos_demo.sql, sin psql y sin variables, crea 300 personas, 6 zonas y 18 casas"
if psql -q -X -v ON_ERROR_STOP=1 -d $A -f "$PAQ/datos_demo.sql" >/dev/null 2>&1; then falla "datos_demo.sql se puede aplicar dos veces"; fi
echo "OK: datos_demo.sql se niega a repetirse"
# Siembra de las iglesias de prueba: sin psql, seis filas en iglesias, más de 500 personas, contactos enmascarados y de un solo uso
! grep -q '^\\' "$PAQ/sembrar_iglesias_prueba.sql" || falla "sembrar_iglesias_prueba.sql contiene órdenes de psql"
psql -q -X -v ON_ERROR_STOP=1 -d $A -f "$PAQ/sembrar_iglesias_prueba.sql" >/dev/null 2>&1 || falla "sembrar_iglesias_prueba.sql falla"
cifras=$(psql -q -X -At -d $A -c "select count(*) || ',' || (select count(*) from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo and i.slug <> 'iglesia-demo') from public.iglesias where es_demo and slug <> 'iglesia-demo'")
[ "$cifras" = "6,36" ] || falla "la siembra dejó $cifras en lugar de 6,36"
malos=$(psql -q -X -At -d $A -c "select count(*) from public.miembros m join public.iglesias i on i.id = m.iglesia_id where i.es_demo and i.slug <> 'iglesia-demo' and ((m.email is not null and m.email !~ '@demo[.]invalid$') or m.telefono !~ '^[+]999 ')")
[ "$malos" = "0" ] || falla "la siembra dejó $malos contactos que no están enmascarados"
echo "OK: sembrar_iglesias_prueba.sql, sin psql, crea 6 iglesias de prueba con 36 personas sintéticas y contactos enmascarados"
if psql -q -X -v ON_ERROR_STOP=1 -d $A -f "$PAQ/sembrar_iglesias_prueba.sql" >/dev/null 2>&1; then falla "sembrar_iglesias_prueba.sql se puede aplicar dos veces"; fi
echo "OK: sembrar_iglesias_prueba.sql se niega a repetirse"

# 5. Una huella detecta un cambio: se quita una política y la verificación lo dice
psql -q -d $A -c "drop policy archivos_marca_leer on storage.objects"
r2=$(psql -q -X -At -F'|' -d $A -f "$PAQ/99_verificacion.sql")
[ "$(echo "$r2" | grep '^zz_todo_ok' | cut -d'|' -f4)" = "f" ] || falla "la verificación no detecta una política que falta"
echo "$r2" | grep -q '^b07_politicas_de_archivos_en_storage|.*|.*|f$' || falla "la huella b07 no marca la política que falta"
echo "OK: la verificación detecta una política que falta"
echo "OK: paquete de aplicación verificado"
