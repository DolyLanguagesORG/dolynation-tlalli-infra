#!/usr/bin/env bash
#
# Arranque de un peer de servicio de la VPN.
#
#   1. Levanta la interfaz WireGuard con la config del host.
#   2. Espera a que el hub responda (handshake).
#   3. Levanta nginx con mTLS: pide el certificado de cliente de la CA
#      interna y reenvia a la aplicacion.
#
# Variables de entorno (las pone el compose):
#   PEER_NAME     nombre del peer (devapi, devweb, minios)
#   APP_TARGET    host:port de la aplicacion a la que se reenvia
#   LISTEN_PORT   puerto que se escucha dentro del tunel
#   APP_CMD       opcional: comando de la aplicacion a correr en segundo
#                 plano (lo usa minios)
set -euo pipefail

PEER_NAME="${PEER_NAME:?falta PEER_NAME}"
APP_TARGET="${APP_TARGET:?falta APP_TARGET}"
LISTEN_PORT="${LISTEN_PORT:-443}"
MTLS_VERIFY="${MTLS_VERIFY:-on}"

log() { echo "[peer:$PEER_NAME] $*"; }

# --- 1. La interfaz WireGuard ----------------------------------------------
if ip link show wg0 >/dev/null 2>&1; then
  log "la interfaz ya esta arriba"
else
  log "levantando la interfaz WireGuard"
  wg-quick up wg0
fi

# --- 2. Esperar al hub ----------------------------------------------------
# Sin handshake no hay tunel: es mejor esperar que abrir un puerto que no
# lleva a ninguna parte. 30 intentos de 2 segundos.
for i in $(seq 1 30); do
  if wg show wg0 latest-handshakes 2>/dev/null | grep -qv '^0$'; then
    log "handshake con el hub OK"
    break
  fi
  if [ "$i" = "30" ]; then
    log "AVISO: todavia no hay handshake con el hub; se sigue adelante"
  fi
  sleep 2
done

# --- 3. La aplicacion (si la hay) ------------------------------------------
if [ -n "${APP_CMD:-}" ]; then
  log "levantando la aplicacion"
  # shellcheck disable=SC2086
  sh -c "$APP_CMD" &
  APP_PID=$!
  # Si la aplicacion muere, el contenedor tambien: un peer sin aplicacion
  # no sirve de nada.
  trap 'kill "$APP_PID" 2>/dev/null || true' EXIT
  sleep 2
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    log "ERROR: la aplicacion no arranco"
    exit 1
  fi
fi

# --- 4. nginx --------------------------------------------------------------
log "configurando nginx (mTLS=${MTLS_VERIFY} -> $APP_TARGET)"

# La IP de tunel es la direccion de la interfaz: ahi se escucha el puerto.
TUNNEL_IP="$(ip -4 -o addr show wg0 | awk '{print $4}' | cut -d/ -f1)"
if [ -z "$TUNNEL_IP" ]; then
  log "ERROR: la interfaz wg0 no tiene direccion IPv4"
  exit 1
fi
log "IP de tunel: $TUNNEL_IP"

# El upstream se separa en host y puerto: envsubst no maneja el ':' de
# `host:port` dentro de un valor de nginx.
export TUNNEL_IP LISTEN_PORT MTLS_VERIFY
export APP_HOST="${APP_TARGET%%:*}"
export APP_PORT="${APP_TARGET##*:}"
# Solo se sustituyen las variables de DolyNation: envsubst tambien
# tocaria las de nginx ($host, $remote_addr...) y las dejaria vacias.
envsubst '${TUNNEL_IP} ${LISTEN_PORT} ${APP_HOST} ${APP_PORT} ${MTLS_VERIFY}' \
    < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# nginx corre en primer plano para que el contenedor muera si el proceso
# principal (la VPN) muere.
exec nginx -g 'daemon off;'
