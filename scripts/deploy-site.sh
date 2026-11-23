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

ORG_DIR="${ORG_DIR:-/srv/doly/staging}"
ENV_DIR="${ENV_DIR:-$ORG_DIR/$COMPOSE_PROJECT_NAME}"
# El manifiesto DEL SITIO, no el de la aplicacion: la landing es un producto
# aparte, con su propia linea de releases. Publicarla no toca ni una linea
# del manifiesto de la app.
REPO_DIR="${REPO_DIR:-$ORG_DIR/dolynation-tlalli-infra}"
MANIFEST="${MANIFEST:-$REPO_DIR/versions-site.yml}"
REGISTRY="${REGISTRY:-ghcr.io/dolylanguagesorg}"

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
export LANDING_HOST_PORT="${LANDING_HOST_PORT:-57023}"
export LANDING_TAG
export APP_BASE_URL="${APP_BASE_URL:-}"

log "Levantando la landing de $COMPOSE_PROJECT_NAME"
docker compose -f docker-compose.site.yml up -d --no-deps landing

# --- 6. Verificar ----------------------------------------------------------
log "Esperando a que la landing responda"
for i in $(seq 1 20); do
  sleep 3
  if curl -fsS "http://127.0.0.1:${LANDING_HOST_PORT:-57023}/" >/dev/null 2>&1; then
    log "OK tras $((i * 3))s"
    docker compose -f docker-compose.site.yml ps landing
    break
  fi
  if [ "$i" = "20" ]; then
    log "ERROR: la landing no responde tras 60s"
    docker compose -f docker-compose.site.yml logs --tail 40 landing 2>&1 || true
    exit 1
  fi
done

# --- 7. Smoke test: el CONTRATO del sitio, no que "haya algo" --------------
# Un despliegue que no comprueba nada es un despliegue a ciegas. El smoke
# falla si el sitio no cumple lo que promete (pagina con contenido, assets,
# cache, cabeceras).
SMOKE="$REPO_DIR/scripts/smoke-site.sh"
if [ -x "$SMOKE" ]; then
  log "Smoke test del sitio"
  bash "$SMOKE" "http://127.0.0.1:${LANDING_HOST_PORT:-57023}" "$LANDING_VERSION" \
    || { log "ERROR: el sitio no cumple el contrato"; exit 1; }
else
  log "AVISO: no esta $SMOKE: el despliegue se da por bueno sin smoke"
fi

exit 0
