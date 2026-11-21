#!/usr/bin/env bash
#
# Arranque del peer de MinIO.
#
# MinIO expone la API S3 en 9000 y la consola en 9001. El peer los publica
# dentro de la VPN con nginx y mTLS por delante, igual que devapi y devweb.
#
# El usuario root y la contrasena NO vienen por defecto: los pone el
# compose, leidos de un fichero 600 que solo root lee.
set -euo pipefail

log() { echo "[peer:minios] $*"; }

if [ -z "${MINIO_ROOT_USER:-}" ] || [ -z "${MINIO_ROOT_PASSWORD:-}" ]; then
  log "ERROR: faltan MINIO_ROOT_USER o MINIO_ROOT_PASSWORD"
  exit 1
fi
if [ "${MINIO_ROOT_USER}" = "minioadmin" ] || [ "${MINIO_ROOT_PASSWORD}" = "minioadmin" ]; then
  log "ERROR: las credenciales por defecto de MinIO no se usan"
  exit 1
fi

# --- 1. La interfaz WireGuard ----------------------------------------------
if ip link show wg0 >/dev/null 2>&1; then
  log "la interfaz ya esta arriba"
else
  log "levantando la interfaz WireGuard"
  wg-quick up wg0
fi

# --- 2. Esperar al hub ----------------------------------------------------
for i in $(seq 1 30); do
  if wg show wg0 latest-handshakes 2>/dev/null | grep -qv '^0$'; then
    log "handshake con el hub OK"
    break
  fi
  [ "$i" = "30" ] && log "AVISO: todavia no hay handshake con el hub"
  sleep 2
done

# --- 3. MinIO en segundo plano --------------------------------------------
log "levantando MinIO"
# El contenedor corre como un usuario sin privilegios: MinIO no necesita root.
/usr/local/bin/minio server "${MINIO_VOLUMES:-/data}" \
  --address ":9000" \
  --console-address ":9001" \
  ${MINIO_OPTS:-} &
MINIO_PID=$!
trap 'kill "$MINIO_PID" 2>/dev/null || true' EXIT

sleep 3
if ! kill -0 "$MINIO_PID" 2>/dev/null; then
  log "ERROR: MinIO no arranco"
  exit 1
fi
log "MinIO escuchando en 9000 (S3) y 9001 (consola)"

# --- 4. nginx con mTLS por delante -----------------------------------------
TUNNEL_IP="$(ip -4 -o addr show wg0 | awk '{print $4}' | cut -d/ -f1)"
if [ -z "$TUNNEL_IP" ]; then
  log "ERROR: la interfaz wg0 no tiene direccion IPv4"
  exit 1
fi
log "IP de tunel: $TUNNEL_IP"

export TUNNEL_IP LISTEN_PORT="${LISTEN_PORT:-50090}" MTLS_VERIFY="${MTLS_VERIFY:-on}"
export APP_HOST="127.0.0.1"
export APP_PORT="9000"
# Solo se sustituyen las variables de DolyNation: envsubst tambien
# tocaria las de nginx ($host, $remote_addr...) y las dejaria vacias.
envsubst '${TUNNEL_IP} ${LISTEN_PORT} ${APP_HOST} ${APP_PORT} ${MTLS_VERIFY}' \
    < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
