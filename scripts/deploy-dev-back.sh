#!/usr/bin/env bash
#
# Deploy del BACKEND al entorno de desarrollo.
#
# Lo ejecuta el workflow `deploy-dev.yml` de `dolynation-atl-back` por SSH.
# Vive en el repo `infra` (no en el repo que resetea), así que el
# `git reset --hard` no sobrescribe este script mientras corre.
#
# El directorio por defecto es /srv/doly/dev/ en el servidor de despliegue.
#
# Flujo: pull de `develop` → `npm ci` si cambió el lock → `docker restart`
# → healthcheck. El contenedor corre en watch y lee su propio `.env` montado,
# por eso basta el restart para recargar código y variables.
set -euo pipefail

ORG_DIR="${ORG_DIR:-/srv/doly/dev}"
REPO="${REPO:-$ORG_DIR/dolynation-atl-back}"
CONTAINER="${CONTAINER:-doly-dev-backend}"
HEALTH_URL="${HEALTH_URL:-http://localhost:57011/api/v1/health/ready}"
LOCK_STAMP="${LOCK_STAMP:-/tmp/doly-dev-backend-lock}"
BRANCH="${BRANCH:-develop}"

log() { echo "[deploy-dev-back] $*"; }

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

# Asegura que el contenedor exista y esté arriba antes de operarlo.
if ! docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; then
  log "El contenedor no está corriendo: docker start"
  docker start "$CONTAINER" >/dev/null
fi

# Reinstala dependencias solo si cambió el lock. En el primer deploy no hay
# stamp previo: el propio contenedor instala al arrancar (ver docker-compose.dev.yml).
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

# La API expone la version y el commit del build que corre. En desarrollo no
# se usa una imagen con ARG GIT_COMMIT (el contenedor corre el codigo montado),
# asi que se inyectan aqui en el `.env` que el contenedor ya lee.
#
# - GIT_COMMIT: el SHA exacto que quedo desplegado.
# - APP_VERSION: la version declarada en el package.json de ese commit, que es
#   la que release-please mantiene al dia en `develop`.
#
# Se leen del codigo ya desplegado, no del remoto, para que coincidan con lo
# que esta corriendo de verdad. La version se lee dentro del contenedor: el
# host de despliegue no tiene node instalado.
#
# El `.env` lo regenera el workflow justo antes de llamar a este script, asi
# que se le anaden estas dos lineas al final (el archivo es del usuario
# `ddeploy`, que es quien ejecuta el script).
GIT_COMMIT_SHA="$(git rev-parse HEAD)"
APP_VERSION_VALUE="$(docker exec "$CONTAINER" node -p "require('/app/package.json').version" 2>/dev/null || echo '')"

if [ -n "$APP_VERSION_VALUE" ]; then
  log "Inyectando GIT_COMMIT=$GIT_COMMIT_SHA APP_VERSION=$APP_VERSION_VALUE"
  printf 'GIT_COMMIT=%s\nAPP_VERSION=%s\n' "$GIT_COMMIT_SHA" "$APP_VERSION_VALUE" >> "$REPO/.env"
else
  log "No se pudo leer la version del package.json: se deja la que hubiera"
fi

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
