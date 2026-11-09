#!/usr/bin/env bash
#
# Guard single-flight de las ramas `rc-*`.
#
# Solo puede existir UNA rc a la vez en todo el proyecto. Si ya hay otra con
# otro nombre, este script falla con un mensaje claro: sin esto, una rc
# abandonada bloquearía el ciclo sin que nadie lo notara, y dos combinaciones
# de versiones distintas podrían llegar a producción a la vez.
#
# Corre en el runner de GitHub Actions, no en el servidor: los repos son
# públicos y las ramas se consultan con `git ls-remote`, sin SSH ni secrets.
# Así el guard funciona igual en los cuatro repos, incluso en el de
# documentación, que no tiene credenciales de despliegue.
#
# Uso: release-guard.sh <nombre-de-la-rc>
set -euo pipefail

BRANCH="${1:?falta el nombre de la rc}"
ORG="${ORG:-DolyLanguagesORG}"
REPOS="${REPOS:-dolynation-atl-back dolynation-tonatiuh-front dolynation-tlalli-infra dolynation-ehecatl-docs}"

log() { echo "[release-guard] $*"; }

current="$(
  for repo in $REPOS; do
    git ls-remote --heads "https://github.com/$ORG/$repo" 'refs/heads/rc-*' 2>/dev/null \
      | awk '{print $2}' \
      | sed 's#^refs/heads/##'
  done | sort -u
)"

# La propia rc no cuenta: es la que se está creando.
others="$(printf '%s\n' "$current" | grep -Fxv "$BRANCH" | grep -v '^$' || true)"

if [ -z "$others" ]; then
  log "OK: no hay otra rc. Se puede continuar con '$BRANCH'."
  exit 0
fi

log "ERROR: ya hay otra rc en curso:"
printf '%s\n' "$others" | sed 's/^/  - /'
log ""
log "Consolida esa rc (PR hacia main, merge y borrado de la rama) antes de"
log "iniciar '$BRANCH'. Solo puede haber una rc a la vez."
exit 1
