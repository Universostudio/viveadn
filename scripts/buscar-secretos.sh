#!/usr/bin/env bash
# Busca secretos en todo el historial de git (todas las ramas) y en los archivos actuales. Solo imprime el tipo de
# patron y el numero de coincidencias, nunca el valor. Sale con error si encuentra algo.
# Uso: scripts/buscar-secretos.sh
set -uo pipefail
cd "$(dirname "$0")/.."
declare -A PATRONES=(
  [jwt]='eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'
  [stripe_live]='sk_live_[A-Za-z0-9]{10,}'
  [stripe_restringida]='rk_live_[A-Za-z0-9]{10,}'
  [clave_privada]='-----BEGIN [A-Z ]*PRIVATE KEY-----'
  [token_github]='gh[pousr]_[A-Za-z0-9]{30,}'
  [token_slack]='xox[abprs]-[A-Za-z0-9-]{10,}'
  [aws]='AKIA[0-9A-Z]{16}'
  [supabase_secreta]='sb_secret_[A-Za-z0-9_-]{10,}'
)
fallo=0
historial=$(git log --all -p --no-color 2>/dev/null)
for nombre in "${!PATRONES[@]}"; do
  n=$(printf '%s' "$historial" | grep -cE -e "${PATRONES[$nombre]}")
  actual=$(git grep -IcE -e "${PATRONES[$nombre]}" -- . 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
  echo "$nombre: historial=$n archivos_actuales=$actual"
  if [ "${n:-0}" -gt 0 ] || [ "${actual:-0}" -gt 0 ]; then fallo=1; fi
done
# Archivos .env que nunca deben estar en el historial
envs=$(git log --all --name-only --pretty=format: | grep -E '(^|/)\.env($|\.)' | grep -v '\.env\.example$' | sort -u | wc -l)
echo "archivos .env en el historial (salvo .env.example): $envs"
[ "$envs" -gt 0 ] && fallo=1
commits=$(git rev-list --all --count)
[ "$fallo" -eq 0 ] && echo "OK: ninguna coincidencia en $commits commits" || echo "FALLO: hay coincidencias; revisalas y rota la credencial"
exit $fallo
