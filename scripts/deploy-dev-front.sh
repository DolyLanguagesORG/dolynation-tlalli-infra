#!/usr/bin/env bash
#
# Deploy del FRONTEND al entorno de desarrollo.
#
# Lo ejecuta el workflow `deploy-dev.yml` de `dolynation-tonatiuh-front` por SSH.
# Vive en el repo `infra` (no en el repo que resetea) para evitar que el
# `git reset --hard` sobrescriba este script mientras corre.
#
# Flujo: pull de `develop` → `npm ci` si cambió el lock → `docker restart`
# → healthcheck. El contenedor corre `next dev` en watch y lee su `.env`
# montado, por eso basta el restart.
set -euo pipefail

ORG_DIR="${ORG_DIR:-/home/mishistema/projects/DolyLanguagesORG}"
REPO="${REPO:-$ORG_DIR/dolynation-tonatiuh-front}"
CONTAINER="${CONTAINER:-doly-dev-frontend}"
HEALTH_URL="${HEALTH_URL:-http://localhost:57012/}"
LOCK_STAMP="${LOCK_STAMP:-/tmp/doly-dev-frontend-lock}"
BRANCH="${BRANCH:-develop}"

log() { echo "[deploy-dev-front] $*"; }

log "Pull de '$BRANCH' en $REPO"
cd "$REPO"
git fetch --prune origin

LOCAL="$(git rev-parse "$BRANCH")"
REMOTE="$(git rev-parse "origin/$BRANCH")"
if [ "$LOCAL" != "$REMOTE" ]; then
  git reset --hard "origin/$BRANCH"
  git clean -fdq
  log "Actualizado $LOCAL -> $REMOTE"
else
  log "Sin cambios nuevos ($LOCAL)"
fi

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
  log "El contenedor no está corriendo: docker start"
  docker start "$CONTAINER" >/dev/null
fi

LOCK_HASH="$(git log -1 --format=%H -- package-lock.json)"
PREV_HASH="$(cat "$LOCK_STAMP" 2>/dev/null || true)"
if [ -z "$PREV_HASH" ]; then
  log "Primer deploy: el contenedor instala dependencias al arrancar"
elif [ "$LOCK_HASH" != "$PREV_HASH" ]; then
  log "package-lock cambió: npm ci dentro del contenedor"
  docker exec "$CONTAINER" npm ci --no-audit --no-fund
else
  log "package-lock sin cambios: no se reinstala"
fi
echo "$LOCK_HASH" > "$LOCK_STAMP"

log "Reiniciando $CONTAINER"
docker restart "$CONTAINER"

log "Healthcheck $HEALTH_URL"
for i in $(seq 1 20); do
  sleep 3
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    log "OK tras $((i * 3))s"
    exit 0
  fi
done

log "ERROR: healthcheck falló tras 60s"
docker logs --tail 40 "$CONTAINER" 2>&1 || true
exit 1
