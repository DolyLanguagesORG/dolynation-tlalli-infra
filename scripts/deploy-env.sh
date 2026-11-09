#!/usr/bin/env bash
#
# Despliega un entorno (staging / produccion / rehearsal) desde el manifiesto
# de versiones.
#
# El manifiesto (`versions.yml`) dice que version de cada repositorio compone
# la aplicacion publicada. Este script lo lee y despliega **exactamente esas**:
# baja las imagenes ya construidas, nunca compila en el servidor.
#
# Por que imagenes y no codigo:
#   - Si dos maquinas compilaran el mismo commit, no serian el mismo binario.
#   - Una imagen es inmutable: se sabe exactamente que corre, y se puede
#     volver atras a la anterior.
#
# Variables de entorno:
#   COMPOSE_PROJECT_NAME  nombre del proyecto (doly-staging / doly-prod / ...)
#   ORG_DIR               directorio del repo de infra en el servidor
#   IMAGE_TAG             etiqueta de la imagen (SHA o version). Por defecto,
#                         la del backend segun el manifiesto.
#   DB_HOST_PORT / BACKEND_HOST_PORT / FRONTEND_HOST_PORT  puertos en el host
#
# Ver operations/PLAN-DE-DESPLIEGUE.md.
set -euo pipefail

ORG_DIR="${ORG_DIR:-/srv/doly/staging}"
PROJECT="${COMPOSE_PROJECT_NAME:-doly-staging}"
REPO="$ORG_DIR/dolynation-tlalli-infra"
COMPOSE_FILE="$REPO/docker-compose.env.yml"
MANIFEST="$REPO/versions.yml"
REGISTRY="ghcr.io/dolylanguagesorg"

log() { echo "[deploy-env] $*"; }

cd "$REPO"

# --- 1. Leer el manifiesto -------------------------------------------------
if [ ! -f "$MANIFEST" ]; then
  log "ERROR: no existe el manifiesto $MANIFEST"
  exit 1
fi

manifest_value() {
  # manifest_value <repo> <campo>  ->  version | tag | commit
  local repo="$1" field="$2"
  awk -v repo="$repo" -v field="$field" '
    $1 == repo ":" { in_repo = 1; next }
    in_repo && /^[a-z]/ { in_repo = 0 }
    in_repo && $1 == field ":" {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      print $2
      exit
    }
  ' "$MANIFEST"
}

APP_VERSION="$(grep -E '^app_version:' "$MANIFEST" | head -1 | cut -d: -f2 | tr -d ' \042\047')"
BACKEND_VERSION="$(manifest_value dolynation-atl-back version)"
BACKEND_COMMIT="$(manifest_value dolynation-atl-back commit)"
FRONTEND_VERSION="$(manifest_value dolynation-tonatiuh-front version)"
FRONTEND_COMMIT="$(manifest_value dolynation-tonatiuh-front commit)"

if [ -z "$BACKEND_VERSION" ] || [ -z "$FRONTEND_VERSION" ]; then
  log "ERROR: el manifiesto no declara las versiones de back y front"
  log "  back=$BACKEND_VERSION front=$FRONTEND_VERSION"
  exit 1
fi

log "Manifiesto: app=$APP_VERSION back=$BACKEND_VERSION front=$FRONTEND_VERSION"

# --- 2. Determinar las etiquetas de imagen --------------------------------
# Las DOS imagenes se despliegan por SHA (inmutable): asi se sabe exactamente
# que corre y el rollback es cambiar el SHA. La etiqueta por version tambien
# se publica, pero solo para leerla; si se desplegara por ahi, una
# reconstruccion posterior moveria la version y el rollback dejaria de ser
# exacto.
BACKEND_TAG="${IMAGE_TAG:-${BACKEND_COMMIT:-$BACKEND_VERSION}}"
FRONTEND_TAG="${FRONTEND_TAG:-${FRONTEND_COMMIT:-$FRONTEND_VERSION}}"

BACKEND_IMAGE="$REGISTRY/dolynation-atl-back:$BACKEND_TAG"
FRONTEND_IMAGE="$REGISTRY/dolynation-tonatiuh-front:$FRONTEND_TAG"

log "Imagen backend:  $BACKEND_IMAGE"
log "Imagen frontend: $FRONTEND_IMAGE"

# --- 3. Autenticar en GHCR ------------------------------------------------
if [ -n "${GHCR_TOKEN:-}" ]; then
  log "Autenticando en GHCR"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USERNAME:-ddeploy}" --password-stdin >/dev/null
else
  log "Sin GHCR_TOKEN: se usan las imagenes publicas (o ya autenticadas)"
fi

# --- 4. Bajar las imagenes ------------------------------------------------
log "Descargando imagenes"
docker pull "$BACKEND_IMAGE"
docker pull "$FRONTEND_IMAGE"

# --- 5. Levantar el stack -------------------------------------------------
export COMPOSE_PROJECT_NAME="$PROJECT"
export BACKEND_TAG
export FRONTEND_TAG

log "Levantando el stack ($PROJECT)"
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# --- 6. Healthcheck -------------------------------------------------------
HEALTH_URL="${HEALTH_URL:-http://localhost:${BACKEND_HOST_PORT:-57021}/api/v1/health/ready}"

log "Healthcheck $HEALTH_URL"
for i in $(seq 1 30); do
  sleep 3
  if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
    log "OK tras $((i * 3))s"
    log "Estado:"
    docker compose -f "$COMPOSE_FILE" ps --format "  {{.Name}}  {{.Status}}" 2>/dev/null || true
    exit 0
  fi
done

log "ERROR: el healthcheck fallo tras 90s"
docker compose -f "$COMPOSE_FILE" ps 2>&1 || true
docker compose -f "$COMPOSE_FILE" logs --tail 40 backend 2>&1 || true
exit 1
