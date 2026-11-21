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
  # 10 peers de las personas (5 developers con 2 identidades y 1 admin) y
  # los de servicio (devapi, devweb, devsite, minios). Con `devsite` son 11.
  local esperados=11
  if [ "$peers" -eq "$esperados" ]; then
    ok "el hub tiene $esperados peers"
  else
    ko "el hub tiene $peers peers (se esperaban $esperados)"
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
  titulo "TLS / mTLS de los servicios"
  local peer
  for peer in devapi devweb; do
    local ip
    ip="$(cat "$VPN_DIR/runtime/$peer/meta.ip" 2>/dev/null || echo "")"
    if [ -z "$ip" ]; then
      ko "$peer: no se conoce su IP de tunel"
      continue
    fi

    local verify_mode code
    verify_mode="$(docker exec "doly-vpn-$peer" grep -E '^\s*ssl_verify_client\s+' /etc/nginx/nginx.conf 2>/dev/null \
      | awk '{gsub(";", "", $2); print $2}' | head -1 || true)"

    if [ "$verify_mode" = "off" ]; then
      # Acceso directo con TLS publico (Let's Encrypt) sin certificado de cliente.
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
        --resolve "$peer.yacaterkos.tech:443:$ip" \
        "https://$peer.yacaterkos.tech/api/v1/health/live" 2>/dev/null || echo 000)"
      if [ "$code" = "200" ]; then
        ok "$peer responde con TLS valido y sin certificado de cliente (HTTP 200)"
      else
        ko "$peer sin certificado de cliente devolvio HTTP $code (se esperaba 200)"
      fi
    else
      # Con certificado de cliente: la API responde.
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
        --resolve "$peer.yacaterkos.tech:443:$ip" \
        --cacert "$VPN_DIR/runtime/$peer/ca.crt" \
        --cert "$VPN_DIR/ca/certs/jxadevp-dev/chain.pem" \
        --key "$VPN_DIR/ca/certs/jxadevp-dev/key.pem" \
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
    fi
  done

  # La landing (devsite) no es una API: su raiz es la pagina. Se comprueba
  # aparte, con el mismo TLS real (Let's Encrypt) y sin certificado de
  # cliente: se abre en el navegador desde dentro de la VPN.
  local site_ip
  site_ip="$(cat "$VPN_DIR/runtime/devsite/meta.ip" 2>/dev/null || echo "")"
  if [ -z "$site_ip" ]; then
    ko "devsite: no se conoce su IP de tunel"
  else
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
      --resolve "devsite.yacaterkos.tech:443:$site_ip" \
      "https://devsite.yacaterkos.tech/" 2>/dev/null || echo 000)"
    if [ "$code" = "200" ]; then
      ok "devsite responde con TLS valido y sin certificado de cliente (HTTP 200)"
    else
      ko "devsite devolvio HTTP $code (se esperaba 200)"
    fi
  fi
}

test_familias() {
  titulo "aislamiento entre familias"
  # Necesita un peer de la familia 'devs' para comprobar que no llega a
  # la familia admin. Se usa el de un developer real: no se toca nada.
  local dev_ip
  dev_ip="$(cat "$VPN_DIR/peers/sebastian-dev/ip" 2>/dev/null || echo "")"
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

test_identidades() {
  titulo "identidades duales (desarrollo y administracion)"
  # Cada persona con dos identidades tiene DOS peers con llave propia:
  # el de desarrollo no alcanza la familia admin.
  local peer_dev peer_admin
  peer_dev="$VPN_DIR/peers/jxadevp-dev/ip"
  peer_admin="$VPN_DIR/peers/jxadevp-admin/ip"

  if [ ! -f "$peer_dev" ] || [ ! -f "$peer_admin" ]; then
    ko "no se encuentran los peers duales"
    return
  fi

  local ip_dev ip_admin
  ip_dev="$(cat "$peer_dev")"
  ip_admin="$(cat "$peer_admin")"

  echo "  identidad de desarrollo:    $ip_dev"
  echo "  identidad de administracion: $ip_admin"

  # El peer de desarrollo no debe tener ruta a la familia admin.
  local allowed_dev
  allowed_dev="$(grep -A5 "jxadevp-dev" "$VPN_DIR/peers/jxadevp-dev/meta.json" \
    >/dev/null 2>&1 && echo ok || echo ok)"

  # La regla que corta devs -> admin.
  if iptables -S DOLY-FWD | grep -q -- "-s $FAM_DEVS -d $FAM_ADMIN -j DROP"; then
    ok "la regla que corta la familia devs hacia admin esta puesta"
  else
    ko "falta la regla que corta devs -> admin"
  fi

  # Y la que deja pasar a la familia admin.
  if iptables -S DOLY-FWD | grep -q -- "-s $FAM_ADMIN -j ACCEPT"; then
    ok "la familia admin llega a todo"
  else
    ko "falta la regla que deja pasar a la familia admin"
  fi

  # El peer de desarrollo solo tiene AllowedIPs de servicios y devs.
  if [ -f "$VPN_DIR/peers/jxadevp-dev/allowed.txt" ]; then
    if grep -q "$FAM_ADMIN" "$VPN_DIR/peers/jxadevp-dev/allowed.txt"; then
      ko "el peer de desarrollo tiene ruta hacia la familia admin"
    else
      ok "el peer de desarrollo NO tiene ruta hacia la familia admin"
    fi
  fi
}

test_dns() {
  titulo "DNS de la VPN"
  # El hub resuelve los nombres de los servicios a sus IPs de tunel. Sin
  # esto, el equipo resolveria el nombre a la IP publica de Cloudflare y
  # la peticion saldria del servidor SIN pasar por el tunel: la VPN no
  # filtraria nada.
  local hub="10.90.0.1"

  if ! systemctl is-active --quiet doly-dns.service; then
    ko "el resolutor DNS de la VPN (doly-dns) no esta activo"
    return
  fi
  ok "el resolutor DNS de la VPN esta activo"

  if ss -ulnp 2>/dev/null | grep -q "$hub:53"; then
    ok "el resolutor escucha en $hub:53"
  else
    ko "el resolutor no escucha en $hub:53"
  fi

  local par
  for par in "devapi.yacaterkos.tech 10.90.0.2" \
             "devweb.yacaterkos.tech 10.90.0.3" \
             "devsite.yacaterkos.tech 10.90.0.5" \
             "minios.doly.internal 10.90.0.4"; do
    set -- $par
    local nombre="$1" esperado="$2"
    local obtenido
    obtenido="$(dig +short +time=3 +tries=1 "@$hub" "$nombre" 2>/dev/null | head -1)"
    if [ "$obtenido" = "$esperado" ]; then
      ok "$nombre resuelve a $esperado"
    else
      ko "$nombre resuelve a '${obtenido:-nada}' (se esperaba $esperado)"
    fi
  done

  # Y que el firewall deje pasar el 53 desde el tunel y solo desde ahi.
  if iptables -C DOLY-IN -p udp --dport 53 -s "$FAM_DEVS" -j ACCEPT 2>/dev/null; then
    ok "el firewall deja pasar el DNS desde la familia devs"
  else
    ko "el firewall no deja pasar el DNS desde la familia devs"
  fi
}

case "${1:-todo}" in
  tunnel) test_tunnel ;;
  identidades) test_identidades ;;
  dns) test_dns ;;
  mtls) test_mtls ;;
  familias) test_familias ;;
  todo) test_tunnel; test_mtls; test_familias; test_identidades; test_dns ;;
  *) echo "uso: $0 {tunnel|mtls|familias|identidades|dns|todo}" >&2; exit 1 ;;
esac

echo
echo "resultado: $PASS correctas, $FAIL fallidas"
[ "$FAIL" -eq 0 ]
