#!/usr/bin/env bash
#
# Levanta la VPN de DolyNation en el servidor.
#
# El hub es este servidor. Cada peer tiene su propia llave y su propio PSK:
# el hub no comparte llave con nadie, y cada peer se puede revocar sin tocar
# a los demas.
#
# Familias (cada una es un dominio de confianza):
#   servicios  10.90.0.0/24   devapi, devweb, minios
#   devs       10.91.0.0/24   laptops del equipo
#   admin      10.92.0.0/24   administracion
#
# Uso:
#   vpn-up.sh start     levanta el hub y sus servicios
#   vpn-up.sh stop      los baja
#   vpn-up.sh status    muestra el estado
#   vpn-up.sh logs      el log del hub
set -euo pipefail

VPN_DIR="/etc/doly-vpn"
RUNTIME="$VPN_DIR/runtime"
WG_IF="wg0"
WG_PORT=50443
STATE="$VPN_DIR/state"

log() { echo "[vpn] $*"; }

ensure_wg_config() {
  # El config con el material en claro lo escribe doly-vpn.py (render).
  # Aqui solo se comprueba que exista.
  if [ ! -f /etc/wireguard/wg0.conf ]; then
    log "ERROR: falta /etc/wireguard/wg0.conf"
    log "       ejecuta: sudo doly-vpn-run render"
    exit 1
  fi
  chmod 600 /etc/wireguard/wg0.conf
}

ensure_firewall() {
  if ! iptables -S DOLY-IN >/dev/null 2>&1; then
    log "aplicando el firewall"
    "$VPN_DIR/vpn-firewall.sh" apply
  fi
}

start_hub() {
  ensure_wg_config
  ensure_firewall

  if ip link show "$WG_IF" >/dev/null 2>&1; then
    log "el hub ya esta arriba"
  else
    log "levantando $WG_IF"
    wg-quick up "$WG_IF"
  fi

  # El reenvio entre peers lo necesita el hub.
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  # Persistencia: que el hub levante solo al reiniciar el servidor.
  if [ ! -f /etc/systemd/system/wg-quick@wg0.service ] && \
     [ ! -L /etc/systemd/system/wg-quick@wg0.service ]; then
    log "habilitando wg-quick@wg0"
    systemctl enable "wg-quick@$WG_IF" >/dev/null 2>&1 || true
  fi
}

start_services() {
  # Los peers de servicio (devapi, devweb, minios) corren como contenedores:
  # cada uno con su propia interfaz WireGuard y su propia identidad.
  for svc in devapi devweb minios; do
    if docker ps --format '{{.Names}}' | grep -qx "doly-vpn-$svc"; then
      log "$svc ya esta corriendo"
      continue
    fi
    log "levantando el peer $svc"
    docker compose -f "$VPN_DIR/docker-compose.vpn.yml" up -d "$svc" 2>&1 | tail -2
  done
}

start() {
  start_hub
  start_services
  log "VPN lista"
}

stop() {
  log "bajando los peers de servicio"
  docker compose -f "$VPN_DIR/docker-compose.vpn.yml" down 2>/dev/null || true
  log "bajando el hub"
  wg-quick down "$WG_IF" 2>/dev/null || true
}

status() {
  echo "== hub =="
  wg show 2>/dev/null || echo "  (el hub no esta arriba)"
  echo
  echo "== peers =="
  for svc in devapi devweb minios; do
    printf "  %-8s " "$svc"
    docker ps --format '{{.Names}}\t{{.Status}}' | grep -F "doly-vpn-$svc" || echo "parado"
  done
  echo
  echo "== firewall =="
  "$VPN_DIR/vpn-firewall.sh" verify || true
}

case "${1:-status}" in
  start) start ;;
  stop) stop ;;
  status) status ;;
  logs) journalctl -u "wg-quick@$WG_IF" -n 50 --no-pager ;;
  *) echo "uso: $0 {start|stop|status|logs}" >&2; exit 1 ;;
esac
