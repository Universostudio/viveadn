#!/usr/bin/env bash
# Concurrencia del tope de miembros del plan: con muchas altas simultaneas, la iglesia nunca supera su limite.
# Usa varias conexiones reales, asi que sus datos se confirman en la base y se borran al terminar.
# Uso: bash limites_concurrencia.sh <base>   (con PGHOST, PGPORT, PGUSER, PGPASSWORD si hacen falta)
set -euo pipefail
DB="${1:-viveadn_pruebas}"
PSQL=(psql -q -At -v ON_ERROR_STOP=1 -d "$DB")
IGL=5e000000-0000-0000-0000-0000000000cc
limpiar() { "${PSQL[@]}" -c "delete from public.iglesias where id = '$IGL'" >/dev/null 2>&1 || true; }
trap limpiar EXIT

if "${PSQL[@]}" -c "select 1 from public.iglesias where slug not like 'prueba-%' limit 1" | grep -q 1; then
  echo "FALLO: esta prueba no se ejecuta en una base con iglesias reales"; exit 1
fi

"${PSQL[@]}" <<SQL
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('$IGL', 'Prueba Tope Concurrente', 'prueba-tope-concurrente', 'ES', 'Sevilla', 'semilla');
insert into public.miembros (iglesia_id, nombre, apellido) select '$IGL', 'Previo' || g, 'Prueba' from generate_series(1, 45) g;
SQL

# Veinte altas a la vez con solo cinco plazas libres (Semilla: 50)
for i in $(seq 1 20); do
  ( "${PSQL[@]}" -c "insert into public.miembros (iglesia_id, nombre, apellido) values ('$IGL', 'Conc$i', 'Prueba')" >/dev/null 2>&1 || true ) &
done
wait
N="$("${PSQL[@]}" -c "select count(*) from public.miembros where iglesia_id = '$IGL'")"
if [ "$N" != "50" ]; then echo "FALLO: 20 altas simultaneas con 5 plazas libres dejaron $N miembros (esperado 50)"; exit 1; fi
echo "OK: 20 altas simultaneas con 5 plazas libres: la iglesia queda en 50"
