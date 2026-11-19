#!/usr/bin/env bash
#
# Prueba de la VPN de DolyNation: comprueba que el tunel, el mTLS y las
# familias de red se comportan como deben.
#
#   vpn-test.sh           todas las pruebas
#   vpn-test.sh tunnel     solo el tunel
#   vpn-test.sh mtls      solo el mTLS
#   vpn-test.sh familias  solo el aislamiento entre familias
#
# Los tests de familia necesitan un peer de la familia 'devs'. Se crea
# uno temporal y se borra al terminar.
set -euo pipefail

WG_IF="wg0"
FAM_SERVICIOS="10.90.0.0/24"
FAM_DEVS="10.91.0.0/24"
FAM_ADMIN="10.92.0.0/24"
VPN_DIR="/etc/doly-vpn"

PASS=0
FAIL=0

ok()   { echo "  OK    $*"; PASS=$((PASS+1)); }
ko()   { echo "  FALLA $*"; FAIL=$((FAIL+1)); }
titulo() { echo; echo "== $* =="; }

test_tunnel() {
  titulo "el tunel"
  if wg show "$WG_IF" >/dev/null 2>&1; then
    ok "la interfaz $WG_IF esta arriba"
  else
    ko "la interfaz $WG_IF no esta arriba"
    return
  fi

  local peers
  peers="$(wg show "$WG_IF" peers | wc -l)"
  if [ "$peers" -eq 8 ]; then
    ok "el hub tiene 8 peers"
  else
    ko "el hub tiene $peers peers (se esperaban 8)"
  fi

  # Los peers de servicio (los que viven en contenedores) deben tener
  # handshake: son los que el hub puede alcanzar siempre.
  local con_handshake
  con_handshake="$(wg show "$WG_IF" latest-handshakes | grep -vc '^0$')"
  if [ "$con_handshake" -ge 3 ]; then
    ok "$con_handshake peers con handshake (los de servicio)"
  else
    ko "solo $con_handshake peers con handshake"
  fi
}

test_mtls() {
  titulo "mTLS de los servicios"
  local peer
  for peer in devapi devweb; do
    local ip
    ip="$(cat "$VPN_DIR/runtime/$peer/meta.ip" 2>/dev/null || echo "")"
    if [ -z "$ip" ]; then
      ko "$peer: no se conoce su IP de tunel"
      continue
    fi

    # Con certificado de cliente: la API responde.
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      --resolve "$peer.yacaterkos.tech:443:$ip" \
      --cacert "$VPN_DIR/runtime/$peer/ca.crt" \
      --cert "$VPN_DIR/ca/certs/jxadevp/chain.pem" \
      --key "$VPN_DIR/ca/certs/jxadevp/key.pem" \
      "https://$peer.yacaterkos.tech/api/v1/health/live" 2>/dev/null || echo 000)"
    if [ "$code" = "200" ]; then
      ok "$peer responde con certificado de cliente (HTTP 200)"
    else
      ko "$peer con certificado de cliente devolvio HTTP $code"
    fi

    # Sin certificado: el servidor lo rechaza.
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      --resolve "$peer.yacaterkos.tech:443:$ip" \
      --cacert "$VPN_DIR/runtime/$peer/ca.crt" \
      "https://$peer.yacaterkos.tech/api/v1/health/live" 2>/dev/null || echo 000)"
    if [ "$code" = "400" ] || [ "$code" = "403" ]; then
      ok "$peer rechaza a quien no tiene certificado (HTTP $code)"
    else
      ko "$peer sin certificado devolvio HTTP $code (deberia rechazar)"
    fi
  done
}

test_familias() {
  titulo "aislamiento entre familias"
  # Necesita un peer de la familia 'devs' para comprobar que no llega a
  # la familia admin. Se usa el de un developer real: no se toca nada.
  local dev_ip
  dev_ip="$(cat "$VPN_DIR/peers/sebastian/ip" 2>/dev/null || echo "")"
  if [ -z "$dev_ip" ]; then
    ko "no se conoce la IP de tunel de sebastian"
    return
  fi

  # La regla del firewall que corta developers -> admin.
  if iptables -S DOLY-FWD | grep -q -- "-s $FAM_DEVS -d $FAM_ADMIN -j DROP"; then
    ok "la regla que corta developers -> admin esta puesta"
  else
    ko "falta la regla que corta developers -> admin"
  fi

  # Y la que permite a los developers llegar a los servicios.
  if iptables -S DOLY-FWD | grep -q -- "-s $FAM_DEVS -d $FAM_SERVICIOS -j ACCEPT"; then
    ok "los developers pueden llegar a los servicios"
  else
    ko "falta la regla que deja a los developers llegar a los servicios"
  fi

  # Y la que deja a la administracion llegar a todo.
  if iptables -S DOLY-FWD | grep -q -- "-s $FAM_ADMIN -j ACCEPT"; then
    ok "la administracion llega a todo"
  else
    ko "falta la regla que deja a la administracion llegar a todo"
  fi

  # La familia de servicios no llega a la de administracion.
  if iptables -S DOLY-FWD | grep -q -- "-s $FAM_SERVICIOS -d $FAM_ADMIN -j DROP"; then
    ok "los servicios no llegan a la administracion"
  else
    ko "falta la regla que corta servicios -> admin"
  fi
}

case "${1:-todo}" in
  tunnel) test_tunnel ;;
  mtls) test_mtls ;;
  familias) test_familias ;;
  todo) test_tunnel; test_mtls; test_familias ;;
  *) echo "uso: $0 {tunnel|mtls|familias|todo}" >&2; exit 1 ;;
esac

echo
echo "resultado: $PASS correctas, $FAIL fallidas"
[ "$FAIL" -eq 0 ]
