#!/usr/bin/env bash
# Fase 2: metricas_op72 con el método de cada proceso. Con todo en OP72 el resultado es EXACTAMENTE el de antes (se compara el jsonb entero con datos
# variados), con otro método usa su plazo y su objetivo de primer contacto, y la reversión devuelve la función anterior con el esquema idéntico.
# Uso: bash tests/adn_seguimiento_metricas.sh [base_temporal]
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${1:-adn_metricas_t}
PSQL=(psql -q -v ON_ERROR_STOP=1)
MIG=20261111330000_adn_seguimiento_metricas
volcado() { pg_dump -s --no-owner -d "$DB" | grep -vE '^\\(un)?restrict '; }
falla() { echo "FALLO: $*"; "${PSQL[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; exit 1; }
# Las métricas se piden como una persona con sesión de la iglesia (la función comprueba módulo y permiso)
metricas_crudas() { "${PSQL[@]}" -d $DB -At <<'SQL'
select set_config('request.jwt.claim.sub', 'ae400000-0000-0000-0000-000000000001', false);
set role authenticated;
select (public.metricas_op72(now() - interval '60 days'))::jsonb - 'desde';
SQL
}
metricas() { metricas_crudas | tail -1; }
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
# Solo las migraciones anteriores a la que se prueba: las posteriores pueden depender de ella
for m in migrations/*.sql; do [[ "$m" > "migrations/$MIG.sql" || "$m" == "migrations/$MIG.sql" ]] && continue; "${PSQL[@]}" -d $DB -f "$m" > /dev/null; done
"${PSQL[@]}" -d $DB <<'SQL'
insert into auth.users (id) values ('ae400000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('ae410000-0000-0000-0000-00000000000a', 'Prueba Met', 'prueba-met', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values ('ae400000-0000-0000-0000-000000000001', 'ae410000-0000-0000-0000-00000000000a', 'P', 'M', 'pm@met.test', 'propietario', true);
insert into public.casas_oracion (id, iglesia_id, codigo_zona, nombre, pais, ciudad, direccion) values ('ae420000-0000-0000-0000-0000000000c1', 'ae410000-0000-0000-0000-00000000000a', 'ZN-900002', 'Casa M', 'ES', 'Sevilla', 'Calle 1');
insert into public.miembros (id, iglesia_id, nombre, apellido) select ('ae430000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'ae410000-0000-0000-0000-00000000000a', 'M' || n, 'Prueba' from generate_series(1, 14) n;
-- Procesos variados: abiertos de varias edades, completados dentro y fuera de plazo, con y sin primer contacto dentro de las 24 horas
insert into public.consolidaciones (id, iglesia_id, miembro_id, consolidador_id, casa_oracion_id, fecha_conversion, primer_contacto_fecha, completado, completado_at)
select ('ae440000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'ae410000-0000-0000-0000-00000000000a', ('ae430000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n % 2 = 0 then 'ae400000-0000-0000-0000-000000000001'::uuid end, case when n % 3 = 0 then 'ae420000-0000-0000-0000-0000000000c1'::uuid end,
       now() - (h || ' hours')::interval,
       case when n in (1, 3, 5, 7, 9, 11) then now() - (h || ' hours')::interval + (c || ' hours')::interval end,
       n in (2, 4, 8, 12), null
  from unnest(array[5, 20, 30, 50, 70, 75, 100, 120, 150, 200, 300, 500, 40, 60]) with ordinality t(h, n),
       lateral (select (array[2, 10, 23, 25, 30, 48])[(n % 6) + 1] c) k;
update public.consolidaciones set completado_at = fecha_conversion + (case when id::text like '%02' or id::text like '%08' then interval '60 hours' else interval '90 hours' end) where completado;
SQL
volcado > /tmp/adn_met_antes.$$.sql
M0=$(metricas)
[ "$(echo "$M0" | grep -c total)" = "1" ] || falla "no se pudieron pedir las métricas de partida: $M0"

"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
M1=$(metricas)
[ "$M0" = "$M1" ] || { echo "antes: $M0"; echo "después: $M1"; falla "con todo en OP72 las métricas cambian"; }
echo "OK: con todos los procesos en OP72 las métricas son EXACTAMENTE las de antes (jsonb completo, 14 procesos variados)"

# Con otro método: plazo de 168 h y primer contacto en 72 h (Seguimiento simple) para los procesos pares
"${PSQL[@]}" -d $DB -c "update public.consolidaciones set metodo_id = '5e000000-0000-4000-8000-000000000001' where right(id::text, 2)::int % 2 = 0" >/dev/null
M2=$(metricas)
[ "$M2" != "$M1" ] || falla "con otro método las métricas deberían cambiar"
v1=$(echo "$M1" | python3 -c "import json,sys; print(json.load(sys.stdin)['vencidos'])")
v2=$(echo "$M2" | python3 -c "import json,sys; print(json.load(sys.stdin)['vencidos'])")
[ "$v2" -lt "$v1" ] || falla "con plazo de 168 h debe haber menos vencidos que con 72 h ($v2 frente a $v1)"
echo "OK: con Seguimiento simple (plazo de 168 h) hay menos procesos vencidos ($v2 frente a $v1) y las métricas usan los números del método"
"${PSQL[@]}" -d $DB -c "update public.consolidaciones set metodo_id = '5e000000-0000-4000-8000-000000000072'" >/dev/null

# Reversión: función anterior y esquema idéntico
"${PSQL[@]}" -d $DB -f "reversiones/$MIG.down.sql" > /dev/null
volcado > /tmp/adn_met_despues.$$.sql
diff -q /tmp/adn_met_antes.$$.sql /tmp/adn_met_despues.$$.sql >/dev/null || { diff /tmp/adn_met_antes.$$.sql /tmp/adn_met_despues.$$.sql | head -20; falla "la reversión no deja el esquema como estaba"; }
echo "OK: tras revertir, el esquema es idéntico al de antes de aplicar"
[ "$(metricas)" = "$M0" ] || falla "con la función anterior restaurada las métricas no coinciden con las de partida"
echo "OK: con la función anterior restaurada las métricas vuelven a ser las de partida"
rm -f /tmp/adn_met_*.$$.sql
"${PSQL[@]}" -d postgres -c "drop database $DB"
