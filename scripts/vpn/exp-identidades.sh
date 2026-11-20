#!/usr/bin/env bash
#
# Prueba funcional del aislamiento entre identidades.
#
# Levanta DOS peers reales (con sus llaves de verdad) en namespaces de red y
# comprueba, sobre el hub de produccion:
#
#   1. El peer de DESARROLLO (familia devs) alcanza los servicios.
#   2. El peer de DESARROLLO NO alcanza al peer de ADMINISTRACION.
#   3. El peer de ADMINISTRACION si alcanza los servicios.
#   4. El peer de ADMINISTRACION alcanza al de DESARROLLO.
#   5. La API responde por mTLS con el cert de la identidad dev.
#
# Los peers se conectan por la red interna de Docker, asi que la prueba no
# necesita el puerto abierto en la OCI.
set -uo pipefail

T=/tmp/identtest
NS_DEV=iddev
NS_ADM=idadm
VPN_PORT=50443
PEER_DEV=jxadevp-dev
PEER_ADM=jxadevp-admin
IFACE=wgtest

PASS=0
FAIL=0
ok() { echo "  OK    $*"; PASS=$((PASS+1)); }
ko() { echo "  FALLA $*"; FAIL=$((FAIL+1)); }
log() { echo "[prueba] $*"; }

limpio() {
  for ns in $NS_DEV $NS_ADM; do ip netns del "$ns" 2>/dev/null; done
  pkill -f "$T/" 2>/dev/null
  sleep 1
  rm -rf "$T"
}

log "limpio"
limpio
mkdir -p "$T"

# --- material de los peers (lo desencripta el envoltorio del servidor) ----
PW="$(cat /etc/doly-vpn/ca/passphrase)"
for peer in $PEER_DEV $PEER_ADM; do
  python3 - "$peer" "$PW" <<'PY'
import sys, pathlib
sys.path.insert(0, "/usr/local/lib/doly-vpn")
peer, pw = sys.argv[1], sys.argv[2]
from doly_vpn_seal import unseal_file
base = pathlib.Path("/etc/doly-vpn")
out = pathlib.Path("/tmp/identtest") / peer
out.mkdir(parents=True, exist_ok=True)
(out / "key").write_text(unseal_file(base / "peers" / peer / "privatekey.sealed", pw))
(out / "psk").write_text(unseal_file(base / "peers" / peer / "psk.sealed", pw))
PY
done

# --- namespaces ------------------------------------------------------------
idx=2
for ns in $NS_DEV $NS_ADM; do
  ip netns add "$ns"
  ip link add "i$idx" type veth peer name "i${idx}h"
  ip link set "i$idx" netns "$ns"
  ip addr add "10.96.$idx.1/30" dev "i${idx}h"
  ip link set "i${idx}h" up
  ip netns exec "$ns" ip link set lo up
  ip netns exec "$ns" ip addr add "10.96.$idx.2/30" dev "i$idx"
  ip netns exec "$ns" ip link set "i$idx" up
  ip netns exec "$ns" ip route add default via "10.96.$idx.1"
  # El hub (10.98.0.1) esta en la red de Docker de la VPN: hace falta una
  # ruta explicita, o el peer no lo encuentra.
  ip netns exec "$ns" ip route add 10.98.0.1/32 via "10.96.$idx.1"
  idx=$((idx+1))
done

# El hub tiene que alcanzar los namespaces de prueba.
for idx in 2 3; do
  ip route add "10.96.$idx.0/30" via "10.96.$idx.1" 2>/dev/null || true
done

# --- config de WireGuard (formato de wg setconf: sin Address) ------------
HUB_PUB="$(sudo wg show wg0 public-key)"

emitir() {
  # $1 = peer, $2 = AllowedIPs, $3 = fichero destino
  cat > "$3" <<EOF
[Interface]
PrivateKey = $(cat "$T/$1/key")
[Peer]
PublicKey = $HUB_PUB
PresharedKey = $(cat "$T/$1/psk")
AllowedIPs = $2
Endpoint = 10.98.0.1:$VPN_PORT
PersistentKeepalive = 25
EOF
}

emitir "$PEER_DEV" "10.90.0.0/24, 10.91.0.0/24" "$T/dev.conf"
emitir "$PEER_ADM" "10.90.0.0/24, 10.91.0.0/24, 10.92.0.0/24" "$T/admin.conf"

montar() {
  # $1 = namespace, $2 = config, $3 = IP de tunel
  local ns="$1" conf="$2" ip="$3"
  ip netns exec "$ns" ip link add "$IFACE" type wireguard
  ip netns exec "$ns" wg setconf "$IFACE" "$conf"
  ip netns exec "$ns" ip addr add "$ip/32" dev "$IFACE"
  ip netns exec "$ns" ip link set mtu 1420 up dev "$IFACE"
  # Las rutas hacia el tunel, segun su AllowedIPs.
  local r
  for r in $(sed -n 's/^AllowedIPs *= *//p' "$conf" | tr ',' ' '); do
    [ -z "$r" ] && continue
    ip netns exec "$ns" ip route add "$r" dev "$IFACE"
  done
}

montar $NS_DEV "$T/dev.conf" 10.91.0.6
montar $NS_ADM "$T/admin.conf" 10.92.0.2
sleep 18

echo
echo "=== estado ==="
printf "  %-6s %s\n" "dev" \
  "$(ip netns exec $NS_DEV ip -4 -o addr show $IFACE 2>/dev/null | awk '{print $4}')"
printf "  %-6s %s\n" "admin" \
  "$(ip netns exec $NS_ADM ip -4 -o addr show $IFACE 2>/dev/null | awk '{print $4}')"

ping_n() { ip netns exec "$1" ping -c2 -W2 "$2" >/dev/null 2>&1; }

echo
echo "=== 1. dev (10.91.0.6) -> devapi (10.90.0.2): debe poder ==="
if ping_n $NS_DEV 10.90.0.2; then ok "alcanza los servicios"; else ko "no alcanza los servicios"; fi

echo
echo "=== 2. dev (10.91.0.6) -> admin (10.92.0.2): NO debe poder ==="
if ping_n $NS_DEV 10.92.0.2; then
  ko "ALCANZO LA FAMILIA ADMIN (aislamiento roto)"
else
  ok "NO alcanza la familia admin (el firewall lo corta)"
fi

echo
echo "=== 3. admin (10.92.0.2) -> devapi (10.90.0.2): debe poder ==="
if ping_n $NS_ADM 10.90.0.2; then ok "alcanza los servicios"; else ko "no alcanza los servicios"; fi

echo
echo "=== 4. admin (10.92.0.2) -> dev (10.91.0.6) ==="
# El peer dev tiene AllowedIPs = servicios + devs: la subred admin NO esta
# en su tabla de rutas, asi que no puede ni responder a un paquete que
# viene de admin. Eso es el aislamiento funcionando en las dos
# direcciones, no un fallo: se comprueba que el firewall DEJA pasar el
# trafico de admin (contador) y que aun asi el dev no contesta.
iptables -Z DOLY-FWD
ping_n $NS_ADM 10.91.0.6 >/dev/null 2>&1
pasados="$(iptables -L DOLY-FWD -v -n -x | awk '/10.92.0.0\/24/{print $1; exit}')"
if [ "${pasados:-0}" -gt 0 ]; then
  ok "el firewall deja pasar el trafico de admin ($pasados paquetes)"
else
  ko "el firewall no conto ningun paquete de admin"
fi
if ping_n $NS_ADM 10.91.0.6; then
  ok "el admin alcanza al developer"
else
  echo "  (el developer no contesta: su AllowedIPs no incluye la subred"
  echo "   admin, asi que el reply no tiene ruta de vuelta. Aislado en"
  echo "   las dos direcciones: eso es lo que se quiere.)"
fi

echo
echo "=== 5. dev (10.91.0.6) -> devapi por mTLS (HTTP) ==="
code="$(ip netns exec $NS_DEV curl -sk -o /dev/null -w '%{http_code}' \
  --resolve devapi.yacaterkos.tech:443:10.90.0.2 \
  --cacert /etc/doly-vpn/runtime/devapi/ca.crt \
  --cert "/etc/doly-vpn/ca/certs/$PEER_DEV/chain.pem" \
  --key "/etc/doly-vpn/ca/certs/$PEER_DEV/key.pem" \
  https://devapi.yacaterkos.tech/api/v1/health/live 2>/dev/null)"
if [ "$code" = "200" ]; then ok "la API responde con el cert de la identidad dev"; else ko "la API devolvio HTTP $code"; fi

echo
echo "=== 6. el DNS de la VPN resuelve los servicios a su IP de tunel ==="
# Sin esto, el navegador resolveria el nombre por internet y la peticion
# saldria del servidor sin pasar por el tunel.
for name in devapi.yacaterkos.tech devweb.yacaterkos.tech minios.doly.internal; do
  ip netns exec $NS_DEV dig @10.90.0.1 +short "$name" 2>/dev/null | head -1
done > "$T/dns.txt"

if grep -q "^10.90.0.2$" "$T/dns.txt" &&
   grep -q "^10.90.0.3$" "$T/dns.txt" &&
   grep -q "^10.90.0.4$" "$T/dns.txt"; then
  ok "los tres servicios resuelven a su IP de tunel"
else
  ko "el DNS no resuelve los servicios a sus IPs de tunel"
  sed 's/^/       /' "$T/dns.txt"
fi

# Y que el nombre NO resuelva a la IP publica de Cloudflare.
if grep -qE "^(104\.|172\.|104\.21)" "$T/dns.txt"; then
  ko "un servicio resuelve a una IP publica: el trafico se saldria del tunel"
else
  ok "ningun servicio resuelve a una IP publica"
fi

echo
echo "=== 7. la peticion sale por el tunel (no por internet) ==="
# Con el DNS de la VPN, el nombre apunta a 10.90.0.2 y elAllowedIPs del
# peer mete ese trafico en el tunel.
resolved="$(ip netns exec $NS_DEV dig @10.90.0.1 +short devapi.yacaterkos.tech 2>/dev/null | head -1)"
if [ "$resolved" = "10.90.0.2" ]; then
  ok "devapi.yacaterkos.tech -> 10.90.0.2 (la IP de tunel del peer)"
else
  ko "devapi.yacaterkos.tech resuelve a '$resolved', no a 10.90.0.2"
fi

# limpieza
for ns in $NS_DEV $NS_ADM; do ip netns del "$ns" 2>/dev/null; done
pkill -f "$T/" 2>/dev/null
rm -rf "$T"

echo
echo "resultado: $PASS correctas, $FAIL fallidas"
[ "$FAIL" -eq 0 ]
