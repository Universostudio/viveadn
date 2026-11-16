#!/usr/bin/env bash
# Método de seguimiento configurable, fase 1, con datos que YA existen antes de aplicar: ningún proceso cambia de fecha, de color ni de resultado,
# todos pasan a OP72, y la reversión deja el esquema idéntico sin tocar los datos. Uso: bash tests/adn_seguimiento_metodos.sh [base_temporal]
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${1:-adn_seguimiento_t}
PSQL=(psql -q -v ON_ERROR_STOP=1)
MIG=20261111320000_adn_seguimiento_metodos
volcado() { pg_dump -s --no-owner -d "$DB" | grep -vE '^\\(un)?restrict '; }
falla() { echo "FALLO: $*"; "${PSQL[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; exit 1; }
huella() { "${PSQL[@]}" -d $DB -At -c "select md5(string_agg(id::text || '|' || estado_alerta || '|' || fecha_limite::text || '|' || completado::text || '|' || coalesce(completado_at::text, '') || '|' || coalesce(resultado, '') || '|' || coalesce(notas, ''), ';' order by id)) from public.consolidaciones"; }
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
for m in migrations/*.sql; do [ "$m" = "migrations/$MIG.sql" ] && continue; "${PSQL[@]}" -d $DB -f "$m" > /dev/null; done
"${PSQL[@]}" -d $DB <<'SQL'
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('ae300000-0000-0000-0000-00000000000a', 'Prueba Seg', 'prueba-seg', 'ES', 'Sevilla', 'premium');
insert into public.miembros (id, iglesia_id, nombre, apellido) select ('ae310000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'ae300000-0000-0000-0000-00000000000a', 'M' || n, 'Prueba' from generate_series(1, 12) n;
-- Procesos de muchas edades (lejos de los bordes de 24, 48 y 72 horas para que el paso del tiempo no los cambie), uno completado y uno con resultado y notas
insert into public.consolidaciones (id, iglesia_id, miembro_id, fecha_conversion, completado, resultado, notas)
select ('ae320000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'ae300000-0000-0000-0000-00000000000a', ('ae310000-0000-0000-0000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       now() - (h || ' hours')::interval, n = 9, case when n = 9 then 'en_celula' end, case when n = 10 then 'nota previa' end
  from unnest(array[1, 6, 12, 20, 30, 40, 55, 65, 80, 100, 150, 400]) with ordinality as t(h, n);
SQL
volcado > /tmp/adn_seg_antes.$$.sql
H0=$(huella)
[ "$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.consolidaciones")" = "12" ] || falla "se esperaban 12 procesos de partida"

"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
[ "$("${PSQL[@]}" -d $DB -At -c "select count(*) from public.consolidaciones where metodo_id = '5e000000-0000-4000-8000-000000000072'")" = "12" ] || falla "todos los procesos existentes deben pasar a OP72"
echo "OK: los 12 procesos que ya existían pasan a OP72"
[ "$(huella)" = "$H0" ] || falla "algún proceso cambió de color, fecha o resultado al aplicar la migración"
echo "OK: ningún proceso cambia de color, de fecha límite, de cierre ni de resultado al aplicar"
"${PSQL[@]}" -d $DB -c "update public.consolidaciones set notas = notas where id <> 'ae320000-0000-0000-0000-000000000010'" > /dev/null
[ "$(huella)" = "$H0" ] || falla "al reescribir cada proceso, el disparador nuevo da otro color o fecha que el antiguo"
echo "OK: el disparador nuevo, al reescribir cada proceso, da el mismo color y la misma fecha que el antiguo"
est=$("${PSQL[@]}" -d $DB -At -c "select string_agg(estado, ',' order by fecha_conversion desc) from public.adn_seguimiento_estado where not completado")
[ "$est" = "verde,verde,verde,verde,amarillo,amarillo,naranja,naranja,rojo,rojo,rojo" ] || falla "la vista de estado da otro color que el de siempre: $est"
echo "OK: la vista de estado calcula el mismo color de siempre en las 11 edades abiertas"

# Reversión: esquema idéntico y datos intactos
"${PSQL[@]}" -d $DB -f "reversiones/$MIG.down.sql" > /dev/null
volcado > /tmp/adn_seg_despues.$$.sql
diff -q /tmp/adn_seg_antes.$$.sql /tmp/adn_seg_despues.$$.sql >/dev/null || { diff /tmp/adn_seg_antes.$$.sql /tmp/adn_seg_despues.$$.sql | head -20; falla "la reversión no deja el esquema como estaba"; }
echo "OK: tras revertir, el esquema es idéntico al de antes de aplicar"
[ "$(huella)" = "$H0" ] || falla "la reversión tocó los datos de consolidaciones"
echo "OK: la reversión no toca ningún dato de consolidaciones"
"${PSQL[@]}" -d $DB -c "update public.consolidaciones set notas = notas where id <> 'ae320000-0000-0000-0000-000000000010'" > /dev/null
[ "$(huella)" = "$H0" ] || falla "con el disparador antiguo restaurado, reescribir cambia los datos"
echo "OK: con el disparador antiguo restaurado todo sigue igual"
# Aplicar de nuevo tras revertir
"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
[ "$(huella)" = "$H0" ] || falla "al aplicar otra vez cambió algún dato"
echo "OK: aplicar, revertir y volver a aplicar deja los datos intactos"
rm -f /tmp/adn_seg_*.$$.sql
"${PSQL[@]}" -d postgres -c "drop database $DB"
