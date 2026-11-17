#!/usr/bin/env bash
# Regenera supabase/paquete-traspaso y DEMUESTRA en local que sirve: monta el estado actual del real (migraciones hasta la última que tiene) con datos sintéticos,
# aplica el paquete compilado y comprueba que el resultado es idéntico (esquema y datos) a aplicar las migraciones originales sin tocar; aplica la verificación;
# aplica la reversión y comprueba que se vuelve exactamente al estado de partida. Solo local: crea y borra las bases tr_*.
# Uso (como el usuario postgres): SALIDA=/ruta scripts/entorno/generar-traspaso.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
SAL="${SALIDA:-supabase/paquete-traspaso}"
BASE=20261106011008
TMP=$(mktemp -d)
export PGOPTIONS="-c search_path=public,extensions"
trap 'rm -rf "$TMP"; for d in tr_base tr_cad tr_tra tr_sem; do psql -q -d postgres -c "drop database if exists $d" >/dev/null 2>&1 || true; done' EXIT
q() { psql -q -X -v ON_ERROR_STOP=1 "$@"; }
dumpear() { pg_dump -s --no-owner -d "$1" | grep -v '^\\\(un\)\?restrict' > "$2"; }
# Huella de los datos: tabla, número de filas y hash de las filas sin las columnas de fecha ni los ids (los ids aleatorios no se pueden comparar)
datos_hash() { q -At -d "$1" <<'SQL'
select tablename || '|' || (xpath('/row/h/text()', query_to_xml(format($f$select coalesce(md5(string_agg(x, '|' order by x)), '') h from (
  select (select jsonb_object_agg(key, value order by key) from jsonb_each(to_jsonb(t)) where key !~ '(_at|_en|^fecha.*|created.*|updated.*|desde|hasta|^id|_id)$')::text as x from public.%I t) s$f$, tablename), false, true, '')))[1]::text
from pg_tables where schemaname = 'public' order by 1;
SQL
}

echo "1/7 Estado actual del real (hasta $BASE) con datos sintéticos"
bash scripts/entorno/traspaso_base.sh tr_base "$BASE" >/dev/null
q -d tr_base -f scripts/entorno/traspaso_fixture.sql
dumpear tr_base "$TMP/base.sql"; datos_hash tr_base > "$TMP/base.datos"

echo "2/7 Cadena completa SIN compilar (referencia)"
q -d postgres -c "create database tr_cad template tr_base" >/dev/null
for m in supabase/migrations/*.sql; do v=$(basename "$m" | cut -c1-14); [[ "$v" > "$BASE" ]] || continue; q -d tr_cad -f "$m" >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; echo "FALLA $m"; exit 1; }; done
(echo "set search_path = pg_catalog;"; cat scripts/entorno/huellas.sql) | psql -X -q -At -F'|' -d tr_cad > "$TMP/esperados.txt"
dumpear tr_cad "$TMP/cad.sql"; datos_hash tr_cad > "$TMP/cad.datos"

echo "3/7 Compilar el paquete de traspaso"
mkdir -p "$SAL"
node scripts/entorno/generar-traspaso.mts --salida "$SAL" --esperados "$TMP/esperados.txt"

echo "4/7 Aplicar el paquete compilado sobre el estado del real"
q -d postgres -c "create database tr_tra template tr_base" >/dev/null
for f in "$SAL"/[0-9][0-9]_*.sql; do
  case "$f" in *verificacion*|*registro_migraciones*) continue ;; esac
  q -d tr_tra -f "$f" >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; echo "FALLA $f"; exit 1; }
done
echo "   cada archivo del paquete pesa como mucho 20.000 bytes: $(wc -c "$SAL"/[0-9][0-9]_*.sql "$SAL"/reversion/*.sql "$SAL"/despues/*.sql "$SAL"/sembrar_iglesias_prueba.sql | grep -v total | sort -rn | head -1)"
for f in "$SAL"/[0-9][0-9]_*.sql "$SAL"/reversion/*.sql "$SAL"/despues/*.sql "$SAL"/sembrar_iglesias_prueba.sql; do [ "$(wc -c < "$f")" -le 20000 ] || { echo "FALLA: $f pesa más de 20.000 bytes"; exit 1; }; done
echo "5/7 Verificación del paquete y equivalencia con la cadena sin compilar"
v=$(q -At -F'|' -d tr_tra -f "$SAL"/[0-9][0-9]_verificacion.sql)
echo "$v" | grep -q '^zz_todo_ok|||t$' || { echo "$v" | awk -F'|' '$4 != "t"'; echo "FALLA la verificación del paquete"; exit 1; }
echo "   verificación: $(echo "$v" | grep -vc '^zz_todo_ok') comprobaciones, todas ok"
dumpear tr_tra "$TMP/tra.sql"; datos_hash tr_tra > "$TMP/tra.datos"
# Cada tramo se puede repetir sin error y sin cambiar nada; y no se puede saltar un tramo
for f in "$SAL"/[0-9][0-9]_tramo_*.sql "$SAL"/[0-9][0-9]_DROP_HAROLD*.sql; do q -d tr_tra -f "$f" >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; echo "FALLA al repetir $f"; exit 1; }; done
dumpear tr_tra "$TMP/repetido.sql"; diff -q "$TMP/tra.sql" "$TMP/repetido.sql" >/dev/null || { echo "FALLA: repetir los tramos cambia el esquema"; exit 1; }
echo "   repetir todos los tramos y DROP_HAROLD: sin error y sin cambios"
q -d postgres -c "create database tr_sem template tr_base" >/dev/null
if q -d tr_sem -f "$(ls "$SAL"/[0-9][0-9]_tramo_*.sql | sed -n 3p)" >/dev/null 2>"$TMP/err"; then echo "FALLA: un tramo se aplicó saltándose los anteriores"; exit 1; fi
grep -q "Falta aplicar antes el tramo" "$TMP/err" || { cat "$TMP/err"; echo "FALLA: mensaje inesperado al saltar un tramo"; exit 1; }
echo "   un tramo no se aplica si falta el anterior"
q -d postgres -c "drop database tr_sem" >/dev/null
diff -q "$TMP/cad.sql" "$TMP/tra.sql" >/dev/null || { diff "$TMP/cad.sql" "$TMP/tra.sql" | head -40; echo "FALLA: el esquema compilado difiere del de la cadena original"; exit 1; }
echo "   esquema idéntico al de aplicar las migraciones originales sin compilar"
diff -q "$TMP/cad.datos" "$TMP/tra.datos" >/dev/null || { diff "$TMP/cad.datos" "$TMP/tra.datos" | head -30; echo "FALLA: los datos difieren"; exit 1; }
echo "   datos idénticos (filas sin fechas ni ids) en $(wc -l < "$TMP/tra.datos") tablas"
# Los datos que ya había no se han tocado: las tablas de personas conservan exactamente sus filas
for t in iglesias miembros perfiles zonas casas_oracion asistencias eventos; do
  a=$(grep "^$t|" "$TMP/base.datos" | cut -d'|' -f2); b=$(grep "^$t|" "$TMP/tra.datos" | cut -d'|' -f2)
  n1=$(q -At -d tr_base -c "select count(*) from public.$t"); n2=$(q -At -d tr_tra -c "select count(*) from public.$t")
  [ "$n1" = "$n2" ] || { echo "FALLA: $t pasó de $n1 a $n2 filas"; exit 1; }
done
echo "   las filas de iglesias, personas, zonas, casas, asistencias y eventos siguen siendo las mismas"

# La siembra de iglesias de demostración corre sobre el real ya traspasado, sin tocar las iglesias que hay (una copia aparte, para no alterar la prueba de reversión)
q -d postgres -c "create database tr_sem template tr_tra" >/dev/null
q -d tr_sem -f "$SAL"/sembrar_iglesias_prueba.sql >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; echo "FALLA la siembra de demostraciones"; exit 1; }
[ "$(q -At -d tr_sem -c "select count(*) from public.iglesias where es_demo and slug like 'prueba-%'")" -ge 6 ] || { echo "FALLA: la siembra no creó las iglesias de demostración"; exit 1; }
[ "$(q -At -d tr_sem -c "select count(*) from public.iglesias where slug in ('fixture-real','fixture-demo','fixture-alias','fixture-receso','casa-reino') and es_demo = (slug in ('fixture-demo','fixture-receso'))")" = 5 ] || { echo "FALLA: la siembra tocó las iglesias que ya había"; exit 1; }
echo "   siembra de demostraciones: crea las suyas (es_demo) y no toca las existentes"
# El registro de migraciones es un paso aparte: se prueba en una base que imite supabase_migrations
q -d tr_tra -c "create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text, created_by text, idempotency_key text, rollback text[])" >/dev/null
for i in 1 2; do q -d tr_tra -f "$SAL"/[0-9][0-9]_registro_migraciones.sql >/dev/null; done
[ "$(q -At -d tr_tra -c "select count(*) from supabase_migrations.schema_migrations")" = "$(ls supabase/migrations | awk '{print substr($0,1,14)}' | awk -v b=$BASE '$0>b' | wc -l)" ] || { echo "FALLA: el registro de migraciones no tiene todas las versiones (o no es repetible)"; exit 1; }
echo "   registro de migraciones: todas las versiones, repetible sin duplicar"
q -d tr_tra -c "drop schema supabase_migrations cascade" >/dev/null

echo "6/7 Ninguna orden destructiva en los archivos de aplicación (salvo DROP_HAROLD)"
for f in "$SAL"/[0-9][0-9]_*.sql; do
  case "$f" in *DROP_HAROLD*) continue ;; esac
  if grep -iEq '\bdrop\b|\bdelete[[:space:]]+from\b|\btruncate\b' "$f"; then grep -inE '\bdrop\b|\bdelete[[:space:]]+from\b|\btruncate\b' "$f" | head; echo "FALLA: $f contiene una orden destructiva"; exit 1; fi
done
echo "   limpio"

echo "7/7 Reversión: se vuelve exactamente al estado del real"
for f in "$SAL"/reversion/R*.sql; do q -d tr_tra -f "$f" >/dev/null 2>"$TMP/err" || { cat "$TMP/err"; echo "FALLA $f"; exit 1; }; done
dumpear tr_tra "$TMP/rev.sql"; datos_hash tr_tra > "$TMP/rev.datos"
diff -q "$TMP/base.sql" "$TMP/rev.sql" >/dev/null || { diff "$TMP/base.sql" "$TMP/rev.sql" | head -40; echo "FALLA: la reversión no deja el esquema como estaba"; exit 1; }
echo "   esquema idéntico al de partida"
diff -q "$TMP/base.datos" "$TMP/rev.datos" >/dev/null || { diff "$TMP/base.datos" "$TMP/rev.datos" | head -30; echo "FALLA: la reversión no deja los datos como estaban"; exit 1; }
echo "   datos idénticos a los de partida"
(cd "$SAL" && sha256sum -c --quiet HUELLAS.sha256 2>&1 | grep -v 'improperly' | head -3) || true
echo "OK: paquete de traspaso verificado en $SAL"
