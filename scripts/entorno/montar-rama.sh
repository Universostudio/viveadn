#!/usr/bin/env bash
# Monta el esquema completo de Vive ADN en una base VACÍA de pruebas (una rama o un proyecto de Supabase creado para esto).
# Aplica, en el mismo orden que la batería local: esquema, catálogo y todas las migraciones de supabase/migrations.
# Reglas:
#  * Solo se ejecuta con la confirmación explícita --rama-de-pruebas.
#  * La cadena de conexión se lee de DATABASE_URL (del entorno de quien ejecuta); no se imprime ni se guarda en ningún archivo.
#  * Se niega a tocar una base que ya tenga el esquema: nunca reaplica ni borra nada. Para una base con datos no sirve.
#  * --con-stub es SOLO para una base local sin Supabase: crea un esquema auth mínimo. Se niega si ya existe auth.users.
# Uso: DATABASE_URL='postgresql://...' scripts/entorno/montar-rama.sh --rama-de-pruebas [--con-stub]
set -euo pipefail
cd "$(dirname "$0")/../../supabase"

[ "${1:-}" = "--rama-de-pruebas" ] || { echo "Falta la confirmación: --rama-de-pruebas (este script solo es para una base vacía de pruebas)." >&2; exit 2; }
CON_STUB=0; [ "${2:-}" = "--con-stub" ] && CON_STUB=1
: "${DATABASE_URL:?Falta DATABASE_URL en el entorno (cadena de conexión de la rama de pruebas)}"
PSQL=(psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1)
consulta() { "${PSQL[@]}" -tAc "$1"; }

[ "$(consulta "select to_regclass('public.iglesias') is not null")" = "f" ] \
  || { echo "La base ya tiene el esquema de Vive ADN: no se toca. Usa una rama o un proyecto vacío." >&2; exit 3; }

if [ "$CON_STUB" = 1 ]; then
  [ "$(consulta "select to_regclass('auth.users') is null")" = "t" ] \
    || { echo "--con-stub solo para una base sin Supabase: aquí ya existe auth.users." >&2; exit 3; }
  echo "Esquema auth mínimo (solo local)"; "${PSQL[@]}" -f tests/stub_supabase.sql
else
  [ "$(consulta "select to_regclass('auth.users') is not null")" = "t" ] \
    || { echo "No existe auth.users: esto no parece una base de Supabase. En local, usa --con-stub." >&2; exit 3; }
fi

echo "Esquema completo"; "${PSQL[@]}" -f schema/esquema_completo.sql
echo "Catálogo";          "${PSQL[@]}" -f schema/seed.sql
n=0
for m in migrations/*.sql; do
  echo "Migración $(basename "$m")"; "${PSQL[@]}" -f "$m"; n=$((n + 1))
done

tablas=$(consulta "select count(*) from pg_tables where schemaname = 'public'")
funciones=$(consulta "select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname in ('public','private')")
echo
echo "Listo: $n migraciones, $tablas tablas en public, $funciones funciones en public y private."
echo "Siguiente: crear el administrador de la plataforma y desplegar las funciones (docs/PUESTA-EN-MARCHA.md, pasos 4 y 5)."
