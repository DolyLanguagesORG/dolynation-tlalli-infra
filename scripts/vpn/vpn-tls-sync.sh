#!/usr/bin/env bash
# Sincroniza el certificado TLS de Let's Encrypt hacia el runtime de devapi y
# devweb (desreferenciando los enlaces simbolicos de certbot porque el contenedor
# solo monta /etc/doly-vpn/runtime/<svc>) y recarga nginx si estan corriendo.
set -euo pipefail

LE_DIR="/etc/letsencrypt/live/doly-vpn-dev"
RUNTIME_DIR="/etc/doly-vpn/runtime"
FULLCHAIN="$LE_DIR/fullchain.pem"
PRIVKEY="$LE_DIR/privkey.pem"

if [ ! -r "$FULLCHAIN" ] || [ ! -r "$PRIVKEY" ]; then
  echo "ERROR: falta $FULLCHAIN o $PRIVKEY" >&2
  exit 1
fi

for svc in devapi devweb devsite; do
  target="$RUNTIME_DIR/$svc"
  install -d -m 0700 -o root -g root "$target"
  install -m 0644 -o root -g root "$FULLCHAIN" "$target/server.crt"
  install -m 0600 -o root -g root "$PRIVKEY" "$target/server.key"
  echo "[vpn-tls-sync] actualizado $target/server.crt y server.key"

  if docker ps --format '{{.Names}}' | grep -qx "doly-vpn-$svc"; then
    docker exec "doly-vpn-$svc" nginx -s reload
    echo "[vpn-tls-sync] recargado nginx en doly-vpn-$svc"
  fi
done
