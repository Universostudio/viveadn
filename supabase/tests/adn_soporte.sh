#!/usr/bin/env bash
# Soporte: reversión de 20261111350000_adn_soporte con datos reales dentro. Revertir deja el esquema idéntico al anterior, no toca ninguna tabla anterior
# (iglesias, perfiles, consolidaciones conservan sus filas), borra solo lo del soporte, y aplicar, repetir y revertir termina en el mismo esquema.
# Uso: bash tests/adn_soporte.sh [base_temporal]
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${1:-adn_soporte_t}
PSQL=(psql -q -v ON_ERROR_STOP=1)
MIG=20261111350000_adn_soporte
volcado() { pg_dump -s --no-owner -d "$DB" | grep -vE '^\\(un)?restrict '; }
falla() { echo "FALLO: $*"; "${PSQL[@]}" -d postgres -c "drop database if exists $DB" >/dev/null 2>&1 || true; exit 1; }
sql() { "${PSQL[@]}" -d $DB -At -c "$1" | tail -1; }
"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
for m in migrations/*.sql; do [[ "$m" > "migrations/$MIG.sql" || "$m" == "migrations/$MIG.sql" ]] && continue; "${PSQL[@]}" -d $DB -f "$m" > /dev/null; done
"${PSQL[@]}" -d $DB <<'SQL'
insert into auth.users (id) values ('ae600000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('ae610000-0000-0000-0000-00000000000a', 'Prueba Soporte T', 'prueba-soporte-t', 'ES', 'Sevilla', 'premium');
insert into public.perfiles (id, iglesia_id, nombre, apellido, email, rol, activo) values ('ae600000-0000-0000-0000-000000000001', 'ae610000-0000-0000-0000-00000000000a', 'P', 'T', 'pt@soporte.test', 'propietario', true);
insert into public.miembros (id, iglesia_id, nombre, apellido) values ('ae630000-0000-0000-0000-000000000001', 'ae610000-0000-0000-0000-00000000000a', 'M', 'Uno');
SQL
volcado > /tmp/adn_sop_antes.$$.sql
FILAS0=$(sql "select (select count(*) from public.iglesias) || '/' || (select count(*) from public.perfiles) || '/' || (select count(*) from public.miembros)")

"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
# Con datos del soporte dentro: un ticket con mensaje, una novedad, un aviso con su entrega
"${PSQL[@]}" -d $DB <<'SQL'
insert into public.adn_tickets (iglesia_id, creado_por, asunto) values ('ae610000-0000-0000-0000-00000000000a', 'ae600000-0000-0000-0000-000000000001', 'Ticket de prueba');
insert into public.adn_ticket_mensajes (ticket_id, texto) select id, 'Hola' from public.adn_tickets;
insert into public.adn_novedades (version, titulo, texto) values ('1.0', 'Novedad', 'Texto');
insert into public.adn_avisos (id, tipo, titulo, texto) values ('ae640000-0000-0000-0000-000000000001', 'alerta', 'Aviso', 'Texto');
select public.adn_aviso_entregar('ae640000-0000-0000-0000-000000000001');
SQL
[ "$(sql "select (select count(*) from public.adn_tickets) || '/' || (select count(*) from public.adn_ticket_mensajes) || '/' || (select count(*) from public.adn_novedades) || '/' || (select count(*) from public.adn_avisos_entregas)")" = "1/1/1/1" ] || falla "no se pudieron crear los datos del soporte"
echo "OK: con la migración aplicada se crean tickets, mensajes, novedades y avisos con entrega"

"${PSQL[@]}" -d $DB -f "reversiones/$MIG.down.sql" > /dev/null
volcado > /tmp/adn_sop_despues.$$.sql
diff -q /tmp/adn_sop_antes.$$.sql /tmp/adn_sop_despues.$$.sql >/dev/null || { diff /tmp/adn_sop_antes.$$.sql /tmp/adn_sop_despues.$$.sql | head -20; falla "la reversión no deja el esquema como estaba"; }
echo "OK: tras revertir, el esquema es idéntico al de antes de aplicar"
[ "$(sql "select (select count(*) from public.iglesias) || '/' || (select count(*) from public.perfiles) || '/' || (select count(*) from public.miembros)")" = "$FILAS0" ] || falla "la reversión tocó filas de tablas anteriores"
[ "$(sql "select count(*) from pg_class where relname like 'adn\_ticket%' or relname like 'adn\_aviso%' or relname like 'adn\_novedades%'")" = "0" ] || falla "quedan objetos del soporte tras revertir"
echo "OK: tras revertir no queda nada del soporte y las tablas anteriores conservan sus filas"

"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null
"${PSQL[@]}" -d $DB -f "migrations/$MIG.sql" > /dev/null || falla "repetir la migración da error"
"${PSQL[@]}" -d $DB -f "reversiones/$MIG.down.sql" > /dev/null
volcado > /tmp/adn_sop_final.$$.sql
diff -q /tmp/adn_sop_antes.$$.sql /tmp/adn_sop_final.$$.sql >/dev/null || falla "tras aplicar, repetir y revertir el esquema no coincide"
echo "OK: aplicar, repetir y revertir termina siempre en el mismo esquema"
rm -f /tmp/adn_sop_*.$$.sql
"${PSQL[@]}" -d postgres -c "drop database $DB"
