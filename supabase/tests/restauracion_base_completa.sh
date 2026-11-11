#!/usr/bin/env bash
# Ensayo de restauracion de la BASE COMPLETA, en local: vuelca una base con datos sinteticos, la restaura en una base vacia
# y demuestra que el esquema es identico y que cada tabla (public, auth, storage) tiene las mismas filas con el mismo
# contenido. Es el guion de docs/RESTAURACION.md, apartado 3, con pg_dump/pg_restore en lugar del panel de la plataforma.
# Crea y borra viveadn_rest_origen y viveadn_rest_destino. Nunca apuntar a produccion.
set -euo pipefail
cd "$(dirname "$0")/.."
ORIGEN=viveadn_rest_origen
DESTINO=viveadn_rest_destino
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"; psql -q -d postgres -c "drop database if exists $ORIGEN" -c "drop database if exists $DESTINO" >/dev/null 2>&1 || true' EXIT
PSQL=(psql -q -v ON_ERROR_STOP=1)
falla() { echo "FALLO: $*"; exit 1; }
# pg_dump 16 añade un token aleatorio (\restrict) en cada volcado: se filtra para poder comparar
esquema() { pg_dump -s --no-owner -d "$1" | grep -vE '^\\(un)?restrict '; }

# Huella de cada tabla: filas y md5 del contenido ordenado, para public, auth y storage
HUELLAS="
create or replace function pg_temp.huellas() returns table (tabla text, filas bigint, md5 text) language plpgsql as \$f\$
declare r record; n bigint; h text;
begin
  for r in select c.oid::regclass::text as t from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where c.relkind = 'r' and s.nspname in ('public', 'auth', 'storage') order by 1 loop
    execute format('select count(*), coalesce(md5(string_agg(x::text, ''|'' order by x::text)), ''-'') from %s x', r.t) into n, h;
    tabla := r.t; filas := n; md5 := h; return next;
  end loop;
end \$f\$;
select tabla || ' ' || filas || ' ' || md5 from pg_temp.huellas() order by 1;
"
secuencias="select schemaname || '.' || sequencename || ' ' || coalesce(last_value::text, 'sin_uso') from pg_sequences where schemaname in ('public', 'auth', 'storage') order by 1"

# 1. Origen: esquema, catalogo, migraciones y una iglesia sintetica con filas en todas las tablas
"${PSQL[@]}" -d postgres -c "drop database if exists $ORIGEN" -c "drop database if exists $DESTINO" -c "create database $ORIGEN"
"${PSQL[@]}" -d $ORIGEN -c "alter database $ORIGEN set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $ORIGEN -f tests/stub_supabase.sql
"${PSQL[@]}" -d $ORIGEN -f schema/esquema_completo.sql
"${PSQL[@]}" -d $ORIGEN -f schema/seed.sql
for m in migrations/*.sql; do "${PSQL[@]}" -d $ORIGEN -f "$m" > /dev/null; done
"${PSQL[@]}" -d $ORIGEN -At -v salida="$OUT/paquete.json" -v conservar=1 -f tests/exportacion/origen.sql
"${PSQL[@]}" -d $ORIGEN -At -c "insert into storage.buckets (id, name, public) values ('prueba-rest', 'prueba-rest', false) on conflict do nothing" > /dev/null
n_origen=$("${PSQL[@]}" -At -d $ORIGEN -c "select count(*) from public.miembros")
[ "$n_origen" -gt 0 ] || falla "el origen no tiene datos"

# 2. Copia: formato personalizado, con esquema, datos, permisos y secuencias (es lo que hace una copia logica completa)
pg_dump -Fc --no-owner -d $ORIGEN -f "$OUT/base.dump"
echo "OK: copia hecha ($(du -k "$OUT/base.dump" | cut -f1) KB)"

# 3. Restauracion en una base vacia, sin ningun script previo: solo existen los roles del servidor
"${PSQL[@]}" -d postgres -c "create database $DESTINO"
pg_restore --no-owner --exit-on-error -d $DESTINO "$OUT/base.dump"
echo "OK: restauracion terminada sin errores"

# 4. Comparacion
esquema $ORIGEN > "$OUT/esq_origen.sql"; esquema $DESTINO > "$OUT/esq_destino.sql"
diff -u "$OUT/esq_origen.sql" "$OUT/esq_destino.sql" > "$OUT/esq.diff" || { head -30 "$OUT/esq.diff"; falla "el esquema restaurado no es identico"; }
echo "OK: el esquema restaurado es identico al original"
"${PSQL[@]}" -At -d $ORIGEN  -c "$HUELLAS" > "$OUT/h_origen.txt"
"${PSQL[@]}" -At -d $DESTINO -c "$HUELLAS" > "$OUT/h_destino.txt"
diff -u "$OUT/h_origen.txt" "$OUT/h_destino.txt" > "$OUT/h.diff" || { head -30 "$OUT/h.diff"; falla "alguna tabla restaurada difiere"; }
tablas=$(wc -l < "$OUT/h_origen.txt"); filas=$(awk '{s += $2} END {print s}' "$OUT/h_origen.txt")
[ "$tablas" -ge 40 ] && [ "$filas" -ge 300 ] || falla "la comparacion es demasiado pequena ($tablas tablas, $filas filas)"
echo "OK: las $tablas tablas tienen las mismas filas y el mismo contenido ($filas filas)"
diff <("${PSQL[@]}" -At -d $ORIGEN -c "$secuencias") <("${PSQL[@]}" -At -d $DESTINO -c "$secuencias") > /dev/null || falla "las secuencias no coinciden: las nuevas filas chocarian con las restauradas"
echo "OK: las secuencias de identidad continuan donde estaban"

# 5. La base restaurada funciona: exporta la misma iglesia con las mismas huellas, y la seguridad por filas sigue activa
"${PSQL[@]}" -d $DESTINO -At -c "select public.adn_exportar_paquete('ea100000-0000-0000-0000-00000000000a') -> 'manifiesto' ->> 'total_filas'" > "$OUT/tf_destino.txt"
python3 - "$OUT/paquete.json" "$OUT/tf_destino.txt" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))['manifiesto']['total_filas']
b = int(open(sys.argv[2]).read().strip())
assert a == b, f'la exportacion de la base restaurada tiene {b} filas y la original {a}'
print(f'OK: la base restaurada exporta la iglesia de prueba con las mismas {a} filas')
PY
rls=$("${PSQL[@]}" -At -d $DESTINO -c "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity")
rls0=$("${PSQL[@]}" -At -d $ORIGEN  -c "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity")
[ "$rls" = "$rls0" ] || falla "la restauracion cambio las tablas sin seguridad por filas ($rls0 -> $rls)"
echo "OK: la seguridad por filas y los permisos se restauran como estaban ($rls tablas sin ella, las mismas que en el origen)"

# 6. La comparacion no es vacua: detecta una fila borrada y un dato cambiado en la base restaurada
"${PSQL[@]}" -d $DESTINO -At -c "update public.miembros set nombre = nombre || 'X' where id = (select id from public.miembros order by id limit 1)" > /dev/null
"${PSQL[@]}" -At -d $DESTINO -c "$HUELLAS" > "$OUT/h_mut.txt"
diff -q "$OUT/h_origen.txt" "$OUT/h_mut.txt" > /dev/null && falla "un dato cambiado no se detecto" || echo "OK: la comparacion detecta un dato cambiado"
"${PSQL[@]}" -d $DESTINO -At -c "update public.miembros set nombre = left(nombre, -1) where nombre like '%X'" > /dev/null
"${PSQL[@]}" -d $DESTINO -At -c "delete from public.adn_consentimiento_evidencias" > /dev/null
"${PSQL[@]}" -At -d $DESTINO -c "$HUELLAS" > "$OUT/h_mut2.txt"
diff -q "$OUT/h_origen.txt" "$OUT/h_mut2.txt" > /dev/null && falla "una fila borrada no se detecto" || echo "OK: la comparacion detecta filas borradas"
echo "OK: ensayo de restauracion de la base completa terminado"
