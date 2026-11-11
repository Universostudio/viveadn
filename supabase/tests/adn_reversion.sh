#!/usr/bin/env bash
# Demuestra que las reversiones de las migraciones adn_* (ciclo de vida y exportacion) dejan el esquema identico
# al anterior, no pierden datos de negocio y que las migraciones se pueden volver a aplicar.
# Usa su propia base desechable. Nunca apuntar a produccion.
set -euo pipefail
cd "$(dirname "$0")/.."
DB=viveadn_reversion
# Migraciones adn_* en el orden en que se aplican; se revierten en el orden contrario
VERSIONES=(20261111120000_adn_ciclo_vida 20261111130000_adn_exportacion 20261111140000_adn_importar_contactos 20261111150000_adn_informes 20261111160000_adn_comunicacion 20261111170000_adn_panel_inicio 20261111180000_adn_descargas_informe 20261111190000_adn_consentimiento 20261111200000_adn_consentimiento_auditoria 20261111210000_adn_consentimiento_evidencia 20261111220000_adn_checkin_canales 20261111230000_adn_doble_confirmacion 20261111240000_adn_purga_estado 20261111250000_adn_purgas_libro 20261111260000_adn_exportacion_paginada 20261111270000_adn_autoservicio_datos 20261111280000_adn_envios_topes)
subir()   { for v in "${VERSIONES[@]}"; do "${PSQL[@]}" -d $DB -f "migrations/$v.sql"; done; }
bajar()   { for ((i=${#VERSIONES[@]}-1; i>=0; i--)); do "${PSQL[@]}" -d $DB -f "reversiones/${VERSIONES[$i]}.down.sql"; done; }
es_adn()  { for v in "${VERSIONES[@]}"; do [ "$1" = "migrations/$v.sql" ] && return 0; done; return 1; }
PSQL=(psql -q -v ON_ERROR_STOP=1)
# pg_dump 16 añade un token aleatorio (\restrict) en cada volcado: se filtra para poder comparar
volcado() { pg_dump -s --no-owner -d "$DB" | grep -vE '^\\(un)?restrict '; }

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d $DB -c "alter database $DB set search_path = \"\$user\", public, extensions"
"${PSQL[@]}" -d $DB -f tests/stub_supabase.sql
"${PSQL[@]}" -d $DB -f schema/esquema_completo.sql
"${PSQL[@]}" -d $DB -f schema/seed.sql
for m in migrations/*.sql; do
  es_adn "$m" && continue
  "${PSQL[@]}" -d $DB -f "$m" > /dev/null
done
volcado > /tmp/adn_antes.$$.sql

# Aplicar, usarla y revertir
subir
"${PSQL[@]}" -d $DB <<'SQL'
insert into auth.users (id) values ('ae000000-0000-0000-0000-000000000001');
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values
  ('ae100000-0000-0000-0000-00000000000a', 'Prueba Reversion', 'prueba-reversion', 'ES', 'Sevilla', 'premium');
insert into public.miembros (iglesia_id, nombre, apellido) values ('ae100000-0000-0000-0000-00000000000a', 'M', 'R');
select public.adn_borrar_suave('ae100000-0000-0000-0000-00000000000a', null, 'prueba de reversion');
select (public.adn_exportar_paquete('ae100000-0000-0000-0000-00000000000a') -> 'manifiesto' ->> 'total_filas')::int > 0 as exporta;
insert into public.adn_miembro_contactos (iglesia_id, miembro_id, tipo, valor) select iglesia_id, id, 'correo', 'extra@prueba.test' from public.miembros;
insert into public.adn_mensajes (iglesia_id, clave, canal, segmento, texto, total, enviados, omitidos) values ('ae100000-0000-0000-0000-00000000000a', gen_random_uuid(), 'whatsapp', 'todos', 'x', 0, 0, 0);
insert into public.adn_comunicacion_bajas (iglesia_id, miembro_id, canal) select iglesia_id, id, 'email' from public.miembros;
select public.adn_panel_inicio() is not null as panel;
insert into public.adn_consentimientos (iglesia_id, miembro_id, canal, estado, origen) select iglesia_id, id, 'email', 'suscrito', 'prueba' from public.miembros;
insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, finalidad, texto_version, texto_hash, origen) select iglesia_id, id, 'checkin', 'checkin', 'v1', (select texto_hash from public.adn_consentimiento_textos where finalidad = 'checkin' and version = 'v1' and idioma = 'es'), 'qr' from public.miembros;
insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, finalidad, texto_version, texto_hash, aplicado, origen) select iglesia_id, id, 'checkin', 'email', 'checkin_email', 'v2', (select texto_hash from public.adn_consentimiento_textos where finalidad = 'checkin_email' and idioma = 'es'), true, 'qr' from public.miembros;
insert into public.adn_confirmaciones (iglesia_id, miembro_id, canal, destino, idioma, estado, token_hash, expira_en) select iglesia_id, id, 'email', 'zz@prueba.test', 'es', 'pendiente', repeat('d', 64), now() + interval '3 days' from public.miembros;
insert into public.adn_consentimiento_evidencias (iglesia_id, miembro_id, tipo, canal, aplicado, origen) select iglesia_id, id, 'confirmacion', 'email', true, 'qr_confirmado' from public.miembros;
insert into public.adn_informe_descargas (iglesia_id, usuario_id, informe, filas) select id, gen_random_uuid(), 'miembros', 1 from public.iglesias;
SQL
bajar
volcado > /tmp/adn_despues.$$.sql

if ! diff -u /tmp/adn_antes.$$.sql /tmp/adn_despues.$$.sql > /tmp/adn_diff.$$.txt; then
  echo "FALLO: la reversion no deja el esquema como estaba:"; head -40 /tmp/adn_diff.$$.txt; exit 1
fi
echo "OK: tras revertir las migraciones adn_*, el esquema es identico al de antes"

# Los datos de negocio sobreviven y la iglesia en borrado suave queda protegida por el mecanismo anterior
res=$("${PSQL[@]}" -d $DB -At -c "select etapa || ',' || (borrado_programado_en is not null) || ',' || (select count(*) from public.miembros) from public.iglesias where slug = 'prueba-reversion'")
[ "$res" = "suspendida,true,1" ] || { echo "FALLO: se esperaba suspendida,true,1 y salio $res"; exit 1; }
echo "OK: la reversion conserva la iglesia, sus miembros y su plazo de borrado"

# Reaplicar las migraciones sobre lo revertido
subir
bajar
volcado > /tmp/adn_despues2.$$.sql
diff -q /tmp/adn_antes.$$.sql /tmp/adn_despues2.$$.sql > /dev/null || { echo "FALLO: aplicar, revertir y volver a aplicar no es idempotente"; exit 1; }
echo "OK: aplicar, revertir y volver a aplicar y revertir termina siempre en el mismo esquema"
rm -f /tmp/adn_*.$$.*
"${PSQL[@]}" -d postgres -c "drop database $DB"
