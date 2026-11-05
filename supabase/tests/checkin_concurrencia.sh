#!/usr/bin/env bash
# Concurrencia del registro por QR: con muchas peticiones simultaneas al mismo evento, el tope de
# registros, el limite por dispositivo y la deteccion de duplicados deben cumplirse igual que en serie.
# Usa varias conexiones reales, asi que sus datos se confirman en la base y se borran al terminar.
# Uso: bash checkin_concurrencia.sh <base>   (con PGHOST, PGPORT, PGUSER, PGPASSWORD si hacen falta)
set -euo pipefail
DB="${1:-viveadn_pruebas}"
PSQL=(psql -q -At -v ON_ERROR_STOP=1 -d "$DB")
IGL=1a000000-0000-0000-0000-0000000000cc
TMP="$(mktemp -d)"
limpiar() { "${PSQL[@]}" -c "delete from public.iglesias where id = '$IGL'" >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap limpiar EXIT

# Seguridad: solo en una base de pruebas
if "${PSQL[@]}" -c "select 1 from public.iglesias where slug not like 'prueba-%' limit 1" | grep -q 1; then
  echo "FALLO: esta prueba no se ejecuta en una base con iglesias reales"; exit 1
fi

"${PSQL[@]}" <<SQL
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('$IGL', 'Prueba Concurrencia', 'prueba-concurrencia', 'ES', 'Sevilla', 'premium');
insert into public.eventos (id, iglesia_id, titulo, inicia_en) values
  ('4a000000-0000-0000-0000-0000000000c1', '$IGL', 'Mismo dispositivo', now() + interval '1 hour'),
  ('4a000000-0000-0000-0000-0000000000c2', '$IGL', 'Con tope', now() + interval '1 hour'),
  ('4a000000-0000-0000-0000-0000000000c3', '$IGL', 'Duplicados', now() + interval '1 hour');
insert into public.evento_checkin (iglesia_id, evento_id, max_registros, token) values
  ('$IGL', '4a000000-0000-0000-0000-0000000000c1', 300, repeat('1', 64)),
  ('$IGL', '4a000000-0000-0000-0000-0000000000c2', 6, repeat('2', 64)),
  ('$IGL', '4a000000-0000-0000-0000-0000000000c3', 300, repeat('3', 64));
SQL

# lanza N conexiones a la vez; cada una llama a registrar_checkin con lo que genere la expresion
lanzar() { # $1 = prefijo del resultado, $2 = N, $3 = token, $4 = expresion SQL de los argumentos (usa $i)
  local i
  for i in $(seq 1 "$2"); do
    ( "${PSQL[@]}" -c "select public.registrar_checkin('$3', ${4//\$i/$i})" > "$TMP/$1_$i" ) &
  done
  wait
}
contar() { cat "$TMP/$1"_* | sort | uniq -c | tr -s ' ' | sed 's/^ //' | tr '\n' ';'; }
esperar() { # $1 = texto contado, $2 = esperado, $3 = mensaje
  if [ "$1" != "$2" ]; then echo "FALLO: $3 (esperado '$2', obtenido '$1')"; exit 1; fi
  echo "OK: $3"
}

# 1. Veinte peticiones a la vez desde el mismo dispositivo: solo 5 pueden pasar
lanzar a 20 "$(printf '1%.0s' $(seq 1 64))" "'Nombre'||\$i, 'Conc', 'c'||\$i||'@x.test', '+3466000'||lpad(\$i::text, 4, '0'), 'ip-unica'"
esperar "$(grep -c '^ok_nuevo$' "$TMP"/a_* | awk -F: '{s+=$2} END {print s}')" "5" "20 peticiones simultaneas del mismo dispositivo: solo 5 registros"
esperar "$("${PSQL[@]}" -c "select count(*) from public.checkin_registros where evento_id = '4a000000-0000-0000-0000-0000000000c1'")" "5" "y solo 5 filas de registro guardadas"

# 2. Treinta peticiones a la vez de dispositivos distintos con tope de 6: solo 6 pueden pasar
lanzar b 30 "$(printf '2%.0s' $(seq 1 64))" "'Tope'||\$i, 'Conc', 't'||\$i||'@x.test', '+3467000'||lpad(\$i::text, 4, '0'), 'ip-'||\$i"
esperar "$(grep -c '^ok_nuevo$' "$TMP"/b_* | awk -F: '{s+=$2} END {print s}')" "6" "30 peticiones simultaneas con tope de 6: solo 6 registros"
esperar "$("${PSQL[@]}" -c "select count(*) from public.asistencia_evento where evento_id = '4a000000-0000-0000-0000-0000000000c2'")" "6" "y el tope no se supera en la asistencia"

# 3. Quince peticiones a la vez de la misma persona (mismo correo): un solo miembro y un solo seguimiento
lanzar c 15 "$(printf '3%.0s' $(seq 1 64))" "'Misma', 'Persona', 'misma@x.test', '+34 688 000 111', 'ip-d'||\$i"
esperar "$("${PSQL[@]}" -c "select count(*) from public.miembros where iglesia_id = '$IGL' and email = 'misma@x.test'")" "1" "15 peticiones simultaneas de la misma persona: un solo miembro"
esperar "$("${PSQL[@]}" -c "select count(*) from public.consolidaciones c join public.miembros m on m.id = c.miembro_id where m.email = 'misma@x.test'")" "1" "y un solo seguimiento OP72"
echo "OK: concurrencia del registro por QR"
