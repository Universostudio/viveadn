#!/usr/bin/env bash
# Concurrencia del motor de formacion: dos avances simultaneos que completan un programa dejan la inscripcion completada.
# Cada transaccion ve solo su propio avance y los ya confirmados; sin un cerrojo ninguna veria el del otro y la inscripcion
# se quedaria en curso con todas las lecciones hechas. Usa conexiones reales: sus datos se confirman y se borran al terminar.
# Uso: bash formacion_concurrencia.sh <base>
set -euo pipefail
DB="${1:-viveadn_pruebas}"
PSQL=(psql -q -At -v ON_ERROR_STOP=1 -d "$DB")
IGL=0f1000cc-0000-0000-0000-0000000000cc
limpiar() { "${PSQL[@]}" -c "delete from public.iglesias where id = '$IGL'" >/dev/null 2>&1 || true; }
trap limpiar EXIT

if "${PSQL[@]}" -c "select 1 from public.iglesias where slug not like 'prueba-%' limit 1" | grep -q 1; then
  echo "FALLO: esta prueba no se ejecuta en una base con iglesias reales"; exit 1
fi

"${PSQL[@]}" <<SQL
insert into public.iglesias (id, nombre, slug, pais, ciudad, plan) values ('$IGL', 'Prueba Formacion Concurrente', 'prueba-formacion-concurrente', 'ES', 'Sevilla', 'premium');
insert into public.miembros (id, iglesia_id, nombre, apellido) values ('0f1000cc-0000-0000-0000-00000000000a', '$IGL', 'Alumno', 'Concurrente');
insert into public.programas_formacion (id, iglesia_id, nombre) values ('0f1000cc-0000-0000-0000-00000000000b', '$IGL', 'Programa');
insert into public.programa_lecciones (id, iglesia_id, programa_id, orden, titulo) values
  ('0f1000cc-0000-0000-0000-0000000000a1', '$IGL', '0f1000cc-0000-0000-0000-00000000000b', 1, 'L1'),
  ('0f1000cc-0000-0000-0000-0000000000a2', '$IGL', '0f1000cc-0000-0000-0000-00000000000b', 2, 'L2'),
  ('0f1000cc-0000-0000-0000-0000000000a3', '$IGL', '0f1000cc-0000-0000-0000-00000000000b', 3, 'L3');
insert into public.inscripciones_formacion (id, iglesia_id, programa_id, miembro_id) values
  ('0f1000cc-0000-0000-0000-0000000000c1', '$IGL', '0f1000cc-0000-0000-0000-00000000000b', '0f1000cc-0000-0000-0000-00000000000a');
insert into public.avance_formacion (iglesia_id, programa_id, inscripcion_id, leccion_id) values
  ('$IGL', '0f1000cc-0000-0000-0000-00000000000b', '0f1000cc-0000-0000-0000-0000000000c1', '0f1000cc-0000-0000-0000-0000000000a1');
SQL

# Las dos ultimas lecciones a la vez; la pausa dentro de cada transaccion obliga a que se solapen
for L in a2 a3; do
  ( "${PSQL[@]}" >/dev/null <<SQL
begin;
insert into public.avance_formacion (iglesia_id, programa_id, inscripcion_id, leccion_id)
  values ('$IGL', '0f1000cc-0000-0000-0000-00000000000b', '0f1000cc-0000-0000-0000-0000000000c1', '0f1000cc-0000-0000-0000-0000000000$L');
select pg_sleep(1.5);
commit;
SQL
  ) &
done
wait
E1="$("${PSQL[@]}" -c "select estado || '|' || (completado_en is not null) from public.inscripciones_formacion where id = '0f1000cc-0000-0000-0000-0000000000c1'")"
N="$("${PSQL[@]}" -c "select count(*) from public.avance_formacion where inscripcion_id = '0f1000cc-0000-0000-0000-0000000000c1'")"
if [ "$N" != "3" ]; then echo "FALLO: se esperaban 3 avances y hay $N"; exit 1; fi
if [ "$E1" != "completado|true" ]; then echo "FALLO: con las 3 lecciones hechas la inscripcion quedo en '$E1' (esperado completado|true)"; exit 1; fi
echo "OK: dos avances simultaneos que completan el programa dejan la inscripcion completada"
