#!/usr/bin/env bash
#
# Firewall de DolyNation.
#
# Por que iptables y no una tabla nft nueva: este servidor usa iptables con
# backend nftables, y Docker gestiona sus propias cadenas (DOCKER-USER,
# DOCKER-FORWARD). Anadir una tabla nft aparte podria ordenar las reglas de
# forma impredecible respecto a las de Docker. Con una cadena propia
# (DOLY-IN / DOLY-FWD) y un salto explicito al principio de INPUT y FORWARD,
# el orden queda determinado y legible.
#
# El filtro tiene tres capas:
#
#   1. OCI (Security List)   que puertos del mundo llegan al servidor.
#                              Esa no se toca desde aqui.
#   2. Esta                  que pasa con lo que llega.
#   3. WireGuard             quien es cada peer (llave + PSK).
#
# Y un filtro propio de la VPN: las familias.
#
#   servicios  10.90.0.0/24   devapi, devweb, minios y el hub
#   devs       10.91.0.0/24   laptops del equipo
#   admin      10.92.0.0/24   administracion
#
# Cada familia es un dominio de confianza: dentro se hablan; hacia fuera
# solo por una regla explicita. Un developer no llega a la familia admin
# ni aunque tenga la llave de su peer: el firewall lo corta.
#
# Uso:
#   vpn-firewall.sh apply     aplica las reglas (idempotente)
#   vpn-firewall.sh show      las muestra
#   vpn-firewall.sh verify    comprueba que el estado es el esperado
#   vpn-firewall.sh backup    guarda una copia de las reglas actuales
set -euo pipefail

WG_PORT=50443
SSH_PORT=50022
OLD_SSH_PORT=22

# Bridge de Docker de la red de peers de la VPN.
VPN_BRIDGE="br-doly-vpn-net"

FAM_SERVICIOS="10.90.0.0/24"
FAM_DEVS="10.91.0.0/24"
FAM_ADMIN="10.92.0.0/24"

# Conjuntos de IPs que se actualizan solos.
SET_CF="cf_ranges"       # rangos de Cloudflare (el proxy publico)
SET_GH="gh_actions"      # runners de GitHub Actions (el bot de deploy)
CF_URL="https://www.cloudflare.com/ips-v4.txt"
GH_URL="https://api.github.com/meta"
STATE_DIR="/etc/doly-vpn/state"

# IPs autorizadas a entrar por SSH mientras la migracion al puerto nuevo no
# este cerrada. Se vacia cuando ya no hacen falta.
ADMIN_FALLBACK_IPS="/etc/doly-vpn/state/ssh-fallback-ips.txt"

ip4_list() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$' "$file" || true
}

fetch_list() {
  # $1 = url, $2 = fichero destino, $3 = comando que extrae las IPs
  local url="$1" dest="$2" extract="$3"
  if ! curl -sf --max-time 30 "$url" | eval "$extract" > "$dest.tmp" 2>/dev/null; then
    echo "AVISO: no se pudo actualizar $dest; se conserva la lista anterior" >&2
    rm -f "$dest.tmp"
    return 0
  fi
  if [ ! -s "$dest.tmp" ]; then
    echo "AVISO: $dest salio vacio; se conserva la lista anterior" >&2
    rm -f "$dest.tmp"
    return 0
  fi
  mv "$dest.tmp" "$dest"
  chmod 600 "$dest"
}

load_set() {
  # $1 = nombre del set, $2 = fichero con las IPs
  local set="$1" file="$2"
  ipset destroy "$set" 2>/dev/null || true
  ipset create "$set" hash:net family inet maxelem 65536 -exist
  local cidr
  while read -r cidr; do
    [ -z "$cidr" ] && continue
    ipset add "$set" "$cidr" -exist 2>/dev/null || true
  done < "$file"
}

apply() {
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  touch "$STATE_DIR/cf-ips.txt" "$STATE_DIR/gh-actions-ips.txt" "$ADMIN_FALLBACK_IPS"
  chmod 600 "$STATE_DIR"/*.txt "$ADMIN_FALLBACK_IPS"

  echo "== actualizando los rangos de Cloudflare =="
  fetch_list "$CF_URL" "$STATE_DIR/cf-ips.txt" "grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$'"
  echo "== actualizando los rangos de GitHub Actions =="
  fetch_list "$GH_URL" "$STATE_DIR/gh-actions-ips.txt" \
    "python3 -c 'import json,sys; print(\"\n\".join(json.load(sys.stdin).get(\"actions\",[])))'"
  load_set "$SET_CF" "$STATE_DIR/cf-ips.txt"
  load_set "$SET_GH" "$STATE_DIR/gh-actions-ips.txt"

  # --- cadenas propias ------------------------------------------------------
  iptables -N DOLY-IN 2>/dev/null || iptables -F DOLY-IN
  iptables -N DOLY-FWD 2>/dev/null || iptables -F DOLY-FWD

  # --- INPUT ---------------------------------------------------------------
  # Se anade regla por regla con `iptables -A`: un `iptables-restore` sin
  # --noflush podria dejar el INPUT vacio si algo falla a medio camino.
  ipt() { iptables "$@"; }

  ipt -A DOLY-IN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ipt -A DOLY-IN -i lo -j ACCEPT
  ipt -A DOLY-IN -p icmp -j ACCEPT

  # WireGuard: el puerto UDP del hub. Acepta de cualquier origen porque la
  # autenticacion la hace el protocolo (llave + PSK): un escaner que pruebe
  # el puerto no obtiene nada.
  ipt -A DOLY-IN -p udp --dport "$WG_PORT" -j ACCEPT

  # SSH: el bot de GitHub Actions (por su rango) y la familia admin (por la
  # VPN). Nada mas entra.
  ipt -A DOLY-IN -p tcp --dport "$SSH_PORT" -m set --match-set "$SET_GH" src -j ACCEPT
  ipt -A DOLY-IN -p tcp --dport "$SSH_PORT" -s "$FAM_ADMIN" -j ACCEPT

  # El puerto viejo: mientras la migracion no este cerrada, sigue abierto
  # para no cortar el deploy. Se cierra con `vpn-firewall.sh cerrar-22`.
  if [ "${CLOSE_OLD_SSH:-0}" = "1" ]; then
    while read -r cidr; do
      [ -z "$cidr" ] && continue
      ipt -A DOLY-IN -p tcp --dport "$OLD_SSH_PORT" -s "$cidr" -j ACCEPT
    done < "$ADMIN_FALLBACK_IPS"
    ipt -A DOLY-IN -p tcp --dport "$OLD_SSH_PORT" -j REJECT
  else
    ipt -A DOLY-IN -p tcp --dport "$OLD_SSH_PORT" -j ACCEPT
  fi

  # El proxy publico: solo Cloudflare. Asi el origen no se responde directo
  # desde internet, solo a traves del proxy.
  ipt -A DOLY-IN -p tcp --dport 443 -m set --match-set "$SET_CF" src -j ACCEPT
  ipt -A DOLY-IN -p tcp --dport 80 -m set --match-set "$SET_CF" src -j ACCEPT

  # Lo demas sigue su curso (las reglas de Oracle, que cierran el resto).
  ipt -A DOLY-IN -j RETURN

  # --- FORWARD --------------------------------------------------------------
  # Lo ya establecido (incluye las respuestas de la VPN).
  ipt -A DOLY-FWD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # El ORDEN importa: las reglas de familia van antes del accept generico.
  # Si el accept de wg0->wg0 estuviera primero, las familias no filtrarian
  # nada.

  # La administracion habla con todos.
  ipt -A DOLY-FWD -s "$FAM_ADMIN" -j ACCEPT

  # Los servicios: con servicios y developers, NUNCA con administracion.
  ipt -A DOLY-FWD -s "$FAM_SERVICIOS" -d "$FAM_ADMIN" -j DROP
  ipt -A DOLY-FWD -s "$FAM_SERVICIOS" -d "$FAM_DEVS" -j ACCEPT
  ipt -A DOLY-FWD -s "$FAM_SERVICIOS" -d "$FAM_SERVICIOS" -j ACCEPT

  # Los developers: con servicios y entre si, NUNCA con administracion.
  ipt -A DOLY-FWD -s "$FAM_DEVS" -d "$FAM_ADMIN" -j DROP
  ipt -A DOLY-FWD -s "$FAM_DEVS" -d "$FAM_SERVICIOS" -j ACCEPT
  ipt -A DOLY-FWD -s "$FAM_DEVS" -d "$FAM_DEVS" -j ACCEPT

  # El trafico entre peers de la VPN: el hub lo reenruta por la misma
  # interfaz. Un developer hacia un servicio entra por wg0 y sale por wg0.
  ipt -A DOLY-FWD -i wg0 -o wg0 -j ACCEPT

  # Los peers de servicio viven en contenedores: su trafico cifrado va del
  # hub al bridge de Docker (y al reves).
  ipt -A DOLY-FWD -i wg0 -o "$VPN_BRIDGE" -j ACCEPT
  ipt -A DOLY-FWD -i "$VPN_BRIDGE" -o wg0 -j ACCEPT

  # Lo demas lo decide Docker.
  ipt -A DOLY-FWD -j RETURN

  # Los saltos van al principio: antes que las reglas de Docker y de Oracle.
  iptables -C INPUT -j DOLY-IN 2>/dev/null || iptables -I INPUT 1 -j DOLY-IN
  iptables -C FORWARD -j DOLY-FWD 2>/dev/null || iptables -I FORWARD 1 -j DOLY-FWD

  # Persistencia: netfilter-persistent restaura esto al arrancar.
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
  fi

  echo "reglas aplicadas"
  echo "  WireGuard: udp/$WG_PORT"
  echo "  SSH: tcp/$SSH_PORT (Actions + familia admin)"
  echo "  Cloudflare: $(wc -l < "$STATE_DIR/cf-ips.txt" 2>/dev/null || echo 0) rangos"
  echo "  GitHub Actions: $(wc -l < "$STATE_DIR/gh-actions-ips.txt" 2>/dev/null || echo 0) rangos"
}

show() {
  iptables -S DOLY-IN
  echo
  iptables -S DOLY-FWD
  echo
  echo "sets:"
  ipset list "$SET_CF" | head -3
  ipset list "$SET_GH" | head -3
}

verify() {
  local fail=0
  check() {
    if "$@" >/dev/null 2>&1; then
      echo "  OK   $*"
    else
      echo "  FALLA  $*"
      fail=1
    fi
  }
  echo "== cadenas =="
  check iptables -S DOLY-IN
  check iptables -S DOLY-FWD
  check iptables -C INPUT -j DOLY-IN
  check iptables -C FORWARD -j DOLY-FWD
  echo "== reglas clave =="
  check iptables -C DOLY-IN -p udp --dport "$WG_PORT" -j ACCEPT
  check iptables -C DOLY-FWD -s "$FAM_DEVS" -d "$FAM_ADMIN" -j DROP
  check iptables -C DOLY-FWD -s "$FAM_SERVICIOS" -d "$FAM_ADMIN" -j DROP
  echo "== sets =="
  check ipset list "$SET_CF"
  check ipset list "$SET_GH"
  exit $fail
}

backup() {
  local f="/etc/doly-vpn/state/iptables-backup-$(date +%Y%m%d-%H%M%S).rules"
  iptables-save > "$f"
  chmod 600 "$f"
  echo "copia guardada en $f"
}

close_old_ssh() {
  export CLOSE_OLD_SSH=1
  apply
}

case "${1:-show}" in
  apply) apply ;;
  cerrar-22) close_old_ssh ;;
  show) show ;;
  verify) verify ;;
  backup) backup ;;
  *) echo "uso: $0 {apply|cerrar-22|show|verify|backup}" >&2; exit 1 ;;
esac
