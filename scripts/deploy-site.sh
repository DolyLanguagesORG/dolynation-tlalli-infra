#!/usr/bin/env bash
#
# Deploy de la LANDING a un ambiente (staging, rehearsal o produccion).
#
# A diferencia de `deploy-env.sh` (que despliega la APLICACION entera: base,
# backend y frontend), este script despliega SOLO la landing:
#
#   - lee la fila de la landing del manifiesto (`versions.yml`),
#   - baja la imagen por su SHA (inmutable),
#   - levanta el compose de la landing (`docker-compose.site.yml`).
#
# La aplicacion NO se toca: ni su base, ni su backend, ni su frontend. Ese es
# justo el punto de tener la landing en un compose aparte.
#
# El compose de la landing tiene su propio `COMPOSE_PROJECT_NAME`, asi que
# los ambientes no se mezclan.
#
# Uso:
#   COMPOSE_PROJECT_NAME=doly-site-staging \
#   LANDING_HOST_PORT=57023 \
#   bash scripts/deploy-site.sh
set -euo pipefail

ORG_DIR="${ORG_DIR:-/srv/doly}"
ENV_DIR="${ENV_DIR:-$ORG_DIR/$COMPOSE_PROJECT_NAME}"
MANIFEST="${MANIFEST:-$ORG_DIR/dolynation-tlalli-infra/versions.yml}"
REGISTRY="${REGISTRY:-ghcr.io}"
REPO_DIR="${REPO_DIR:-$ORG_DIR/dolynation-tlalli-infra}"

log() { echo "[deploy-site] $*"; }

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

LANDING_VERSION="$(manifest_value dolynation-tetl-landing version)"
LANDING_COMMIT="$(manifest_value dolynation-tetl-landing commit)"

if [ -z "$LANDING_VERSION" ]; then
  log "ERROR: el manifiesto no declara la version de la landing"
  log "  (la fila 'dolynation-tetl-landing' es obligatoria)"
  exit 1
fi

log "Manifiesto: landing=$LANDING_VERSION commit=${LANDING_COMMIT:-sin commit}"

# --- 2. Determinar la etiqueta de imagen ----------------------------------
# Por SHA (inmutable): el rollback es cambiar el SHA. La etiqueta por version
# tambien se publica, pero solo para leerla.
LANDING_TAG="${LANDING_TAG:-${LANDING_COMMIT:-$LANDING_VERSION}}"
LANDING_IMAGE="$REGISTRY/dolynation-tetl-landing:$LANDING_TAG"
log "Imagen landing: $LANDING_IMAGE"

# --- 3. Autenticar en GHCR ------------------------------------------------
if [ -n "${GHCR_TOKEN:-}" ]; then
  log "Autenticando en GHCR"
  echo "$GHCR_TOKEN" | docker login ghcr.io -u "${GHCR_USERNAME:-ddeploy}" --password-stdin >/dev/null
else
  log "Sin GHCR_TOKEN: se usan las imagenes publicas (o ya autenticadas)"
fi

# --- 4. Bajar la imagen ----------------------------------------------------
log "Descargando la imagen de la landing"
docker pull "$LANDING_IMAGE"

# --- 5. Levantar SOLO el servicio de la landing ----------------------------
cd "$REPO_DIR"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:?falta COMPOSE_PROJECT_NAME}"
export LANDING_TAG

log "Levantando la landing de $COMPOSE_PROJECT_NAME"
docker compose -f docker-compose.site.yml up -d --no-deps landing

# --- 6. Verificar ----------------------------------------------------------
log "Esperando a que la landing responda"
for i in $(seq 1 20); do
  sleep 3
  if curl -fsS "http://127.0.0.1:${LANDING_HOST_PORT:-57023}/" >/dev/null 2>&1; then
    log "OK tras $((i * 3))s"
    docker compose -f docker-compose.site.yml ps landing
    exit 0
  fi
done

log "ERROR: la landing no responde tras 60s"
docker compose -f docker-compose.site.yml logs --tail 40 landing 2>&1 || true
exit 1
