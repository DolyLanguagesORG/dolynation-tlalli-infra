#!/usr/bin/env bash
#
# Resumen del estado del proyecto: una foto de "cómo vamos" que se puede
# regenerar cuando haga falta.
#
# Sale de la API de GitHub (releases, issues, runs) y del manifiesto de
# versiones. **No** necesita ningun secreto.
#
# Uso: scripts/status-summary.sh
#
# Para publicarlo como discussion, copia la salida en el cuerpo de la
# discussion (la categoria "General" del repo de docs).
set -uo pipefail

ORG="DolyLanguagesORG"
REPOS=("dolynation-atl-back" "dolynation-tonatiuh-front" "dolynation-tetl-landing" "dolynation-tlalli-infra" "dolynation-ehecatl-docs")

gh_json() { gh api "$@" 2>/dev/null; }

echo "## Estado del proyecto — $(date '+%d/%m/%Y %H:%M') UTC"
echo

echo "### Versiones publicadas"
for repo in "${REPOS[@]}"; do
  last=$(gh_json "repos/$ORG/$repo/releases?per_page=1" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(f\"{d[0]['tag_name']}  ({d[0]['published_at'][:10]})\" if d else 'sin releases')
except Exception:
    print('sin releases')
" 2>/dev/null)
  printf -- "- **%s**: %s\n" "$repo" "$last"
done
echo

echo "### Manifiesto de versiones (versions.yml, en el repo de infra)"
for repo in "${REPOS[@]}"; do
  # La version PUBLICADA de este repo (la de su ultima release) y la que
  # declara el manifiesto. Si no coinciden, el manifiesto va atrasado.
  v=$(gh_json "repos/$ORG/$repo/releases?per_page=1" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print(d[0]['tag_name'].lstrip('v') if d else '?')
except Exception:
    print('?')
" 2>/dev/null)
  v_repo=$(gh_json "repos/$ORG/dolynation-tlalli-infra/contents/versions.yml" | python3 -c "
import json,sys,base64,re
try:
    d=json.load(sys.stdin)
    t=base64.b64decode(d['content']).decode()
    m=re.search(r'^  %s:\n    version: (\S+)' % re.escape('$repo'), t, re.M)
    print(m.group(1) if m else '?')
except Exception:
    print('?')
" 2>/dev/null)
  if [ "$v" = "$v_repo" ]; then
    printf -- "- %s: %s (al dia)\n" "$repo" "$v_repo"
  else
    printf -- "- %s: %s (manifiesto: %s) <- DESFASADO\n" "$repo" "$v" "$v_repo"
  fi
done
echo
echo "### Issues abiertos por tipo"
for label in bug needs:decision type:gap; do
  n=0
  for repo in "${REPOS[@]}"; do
    c=$(gh_json "repos/$ORG/$repo/issues?state=open&labels=$label&per_page=100" | python3 -c "
import json,sys
try:
    print(len([i for i in json.load(sys.stdin) if 'pull_request' not in i]))
except Exception:
    print(0)
" 2>/dev/null)
    n=$((n + c))
  done
  case "$label" in
    bug) nombre="bugs abiertos" ;;
    needs:decision) nombre="esperan una decision del equipo" ;;
    type:gap) nombre="huecos de plan" ;;
  esac
  printf -- "- **%s**: %s (etiqueta \`%s\`)\n" "$nombre" "$n" "$label"
done
echo

echo "### Pull requests abiertos"
for repo in "${REPOS[@]}"; do
  n=$(gh_json "repos/$ORG/$repo/pulls?state=open&per_page=100" | python3 -c "
import json,sys
try:
    print(len(json.load(sys.stdin)))
except Exception:
    print(0)
" 2>/dev/null)
  printf -- "- %s: %s\n" "$repo" "$n"
done
echo

echo "### Ultimos runs (por repo)"
for repo in "${REPOS[@]}"; do
  printf -- "- **%s**\n" "$repo"
  gh_json "repos/$ORG/$repo/actions/runs?per_page=8" | python3 -c "
import json,sys
try:
    runs=json.load(sys.stdin)['workflow_runs']
    vistos=set()
    for r in runs:
        if r['name'] in vistos:
            continue
        vistos.add(r['name'])
        icon={'success':'ok','failure':'FALLO','cancelled':'cancelado','skipped':'omitido'}.get(r['conclusion'], r['conclusion'] or r['status'])
        print(f\"    - {r['name']}: {icon}\")
except Exception:
    print('    - (sin datos)')
" 2>/dev/null
done
echo

echo "### Ramas"
for repo in "${REPOS[@]}"; do
  n=$(gh_json "repos/$ORG/$repo/branches?per_page=100" | python3 -c "
import json,sys
try:
    bs=[b['name'] for b in json.load(sys.stdin) if b['name'] not in ('main','develop')]
    print(', '.join(bs) if bs else 'solo main y develop')
except Exception:
    print('?')
" 2>/dev/null)
  printf -- "- %s: %s\n" "$repo" "$n"
done
