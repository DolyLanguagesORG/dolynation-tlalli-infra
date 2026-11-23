#!/usr/bin/env bash
#
# Instalador de la VPN de DolyNation.
#
# Deja todo listo para empezar a programar:
#   1. instala WireGuard si falta,
#   2. copia tu configuracion a /etc/wireguard/,
#   3. conecta la VPN y comprueba que funciona,
#   4. dice que falta, si falta algo.
#
# Para `devapi` y `devweb` solo hace falta el `.conf`: usan HTTPS real con
# certificado de Let's Encrypt y no piden certificado de cliente. La CA
# interna y el `.p12` solo hacen falta para MinIO.
#
# Uso:
#   ./instalar.sh              # instala y comprueba
#   ./instalar.sh --sin-check  # instala sin conectar
#
# Se puede relanzar las veces que haga falta: no rompe nada.
set -uo pipefail

CARPETA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { echo "  $*"; }
aviso() { echo "  ! $*"; }
error() { echo "  x $*" >&2; }

es_root() { [ "$(id -u)" = "0" ]; }
sudo_c() { if es_root; then "$@"; else sudo "$@"; fi; }

# --- 0. Que configs hay ----------------------------------------------------
CONFIGS=()
for f in "$CARPETA"/wg-*.conf "$CARPETA"/wg0.conf; do
  [ -f "$f" ] && CONFIGS+=("$f")
done

if [ "${#CONFIGS[@]}" -eq 0 ]; then
  error "no hay ningun .conf de WireGuard en $CARPETA"
  exit 1
fi

echo
echo "=============================================="
echo " VPN de DolyNation - instalador"
echo "=============================================="
echo
echo "  Configuraciones encontradas:"
for f in "${CONFIGS[@]}"; do
  echo "    - $(basename "$f")"
done
echo

# --- Como se va a conectar -------------------------------------------------
# NetworkManager (el icono de red del escritorio) y wg-quick (la terminal)
# son dos caminos. Si el sistema usa NetworkManager, se usa el: gestiona el
# DNS de la VPN sin necesidad de `resolvconf` y se conecta desde el panel.
USA_NM=0
if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager 2>/dev/null; then
  USA_NM=1
fi

if [ "$USA_NM" = "1" ]; then
  echo "== NetworkManager detectado: se conecta desde el icono de red =="
else
  echo "== se usara wg-quick (la terminal) =="
fi

# --- 1. WireGuard ----------------------------------------------------------
if ! command -v wg-quick >/dev/null 2>&1; then
  echo "== instalando WireGuard =="
  if command -v apt-get >/dev/null 2>&1; then
    sudo_c apt-get update -qq && sudo_c apt-get install -y -qq wireguard
  elif command -v dnf >/dev/null 2>&1; then
    sudo_c dnf install -y -q wireguard-tools
  elif command -v pacman >/dev/null 2>&1; then
    sudo_c pacman -S --needed --noconfirm wireguard-tools
  else
    aviso "no se como instalar WireGuard en este sistema: instalalo a mano"
  fi
fi
command -v wg-quick >/dev/null 2>&1 \
  && info "WireGuard: $(wg --version 2>/dev/null | head -1)" \
  || aviso "WireGuard sigue sin instalarse"

# --- 2. El resolvedor de DNS ya no hace falta ---------------------------
# El config no lleva linea `DNS =`: los nombres de los servicios resuelven
# por el DNS publico a la IP de tunel, y el trafico entra por el tunel
# porque esa IP esta en el AllowedIPs del peer. Asi que no hay que instalar
# nada mas que WireGuard.

# --- 2b. NetworkManager y systemd-resolved ---------------------------------
# Con systemd-resolved, NetworkManager tiene que ser el que le pase el DNS
# de la VPN al resolved. Si no, cada uno quiere escribir /etc/resolv.conf y
# el nombre no resuelve.
if [ "$USA_NM" = "1" ] && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
  CONF_NM="/etc/NetworkManager/conf.d/00-dns.conf"
  if ! grep -q "dns=systemd-resolved" "$CONF_NM" 2>/dev/null; then
    echo "== configurando NetworkManager para que use systemd-resolved =="
    sudo_c mkdir -p /etc/NetworkManager/conf.d
    printf '[main]\ndns=systemd-resolved\nsystemd-resolved=true\n' \
      | sudo_c tee "$CONF_NM" >/dev/null
    sudo_c systemctl restart NetworkManager
    sleep 6
    info "NetworkManager reiniciado"
  fi
fi

# --- 3. Configuraciones ----------------------------------------------------
echo "== copiando las configuraciones a /etc/wireguard =="
sudo_c mkdir -p /etc/wireguard
for f in "${CONFIGS[@]}"; do
  base="$(basename "$f")"
  sudo_c cp "$f" "/etc/wireguard/$base"
  sudo_c chmod 600 "/etc/wireguard/$base"
  info "/etc/wireguard/$base"
done

# --- 4. La CA (solo hace falta para MinIO) --------------------------------
if [ -f "$CARPETA/ca.crt" ]; then
  echo "== instalando la CA (solo hace falta para MinIO) =="
  if command -v update-ca-certificates >/dev/null 2>&1; then
    sudo_c cp "$CARPETA/ca.crt" /usr/local/share/ca-certificates/doly-vpn.crt
    sudo_c update-ca-certificates >/dev/null 2>&1
    info "instalada en el almacen del sistema"
  elif command -v trust >/dev/null 2>&1; then
    # Arch: p11-kit
    sudo_c trust anchor --store "$CARPETA/ca.crt" >/dev/null 2>&1 \
      && info "instalada con p11-kit (trust)" \
      || aviso "no se pudo instalar la CA con 'trust'"
  elif command -v security >/dev/null 2>&1; then
    sudo_c security add-trusted-cert -d -r trustRoot \
      -k /Library/Keychains/System.keychain "$CARPETA/ca.crt" >/dev/null 2>&1
    info "instalada en el llavero del sistema"
  else
    aviso "para MinIO: instala a mano ca.crt en el almacen de confianza"
  fi
fi

# --- 5. Conectar y comprobar ----------------------------------------------
if [ "${1:-}" = "--sin-check" ]; then
  echo
  echo "Instalado. Ya puedes conectarte."
  exit 0
fi

echo
echo "== conectando y comprobando =="

conectar() {
  # $1 = si hay que informar de los fallos
  local avisar="${1:-}"
  local base f
  for f in "${CONFIGS[@]}"; do
    base="$(basename "$f" .conf)"
    echo
    echo "  -- $base --"

    if [ "$USA_NM" = "1" ]; then
      if ! nmcli connection show "$base" >/dev/null 2>&1; then
        # Se importa desde la CARPETA del paquete, no desde /etc/wireguard:
        # ese directorio es 700 (solo root) y `nmcli connection import` se
        # ejecuta como usuario normal, asi que no podria leerlo.
        # NetworkManager guarda su propia copia de la llave en
        # /etc/NetworkManager/system-connections (600, solo root).
        if ! nmcli connection import type wireguard file "$f" >/dev/null 2>&1; then
          aviso "no se pudo crear la conexion de red"
          nmcli connection import type wireguard file "$f" 2>&1 | tail -2 | sed 's/^/      /'
          continue
        fi
        # El dominio "~." hace que TODAS las consultas vayan al DNS de la
        # VPN. Sin el, el resolved sigue preguntando al DNS global y
        # `devapi.dolynation.app` no resuelve a la IP de tunel.
        nmcli connection modify "$base" ipv4.dns-priority -50 ipv4.dns-search "~." \
          >/dev/null 2>&1
      fi
      nmcli connection up "$base" >/dev/null 2>&1 \
        || aviso "no se pudo conectar"
    else
      sudo_c wg-quick down "$base" >/dev/null 2>&1
      sudo_c wg-quick up "$base" >/dev/null 2>&1 \
        || { aviso "no se pudo levantar '$base'"; sudo_c wg-quick up "$base" 2>&1 | tail -4 | sed 's/^/      /'; }
    fi

    sleep 8
    local hs
    hs="$(sudo_c wg show "$base" latest-handshakes 2>/dev/null | awk '{print $2}')"
    if [ -n "$hs" ] && [ "$hs" != "0" ]; then
      info "conectado (handshake hecho)"
    else
      aviso "sin handshake: el puerto udp/58376 no esta abierto en el servidor"
    fi
  done
}

comprobar_dns() {
  getent ahostsv4 devapi.dolynation.app 2>/dev/null | head -1 | awk '{print $1}'
}

conectar

RESUELTO="$(comprobar_dns)"
if [ "$RESUELTO" != "10.90.0.2" ] && [ "$USA_NM" = "1" ]; then
  # NetworkManager lee su configuracion (si usa systemd-resolved) al
  # arrancar: si el fichero se creo despues, no lo sabe. Se reinicia y se
  # reintenta una vez.
  echo
  aviso "el DNS no se aplica todavia: reiniciando NetworkManager"
  sudo_c systemctl restart NetworkManager
  sleep 10
  conectar
  RESUELTO="$(comprobar_dns)"
fi

fallos=0
echo
if [ "$RESUELTO" = "10.90.0.2" ]; then
  info "el DNS resuelve devapi a 10.90.0.2 (correcto)"
else
  aviso "devapi.dolynation.app resuelve a '${RESUELTO:-nada}' (se espera 10.90.0.2)"
  fallos=$((fallos+1))
fi

echo
echo "=============================================="
if [ "$fallos" -eq 0 ]; then
  echo " Listo. Ya puedes programar."
else
  echo " Listo con avisos (arriba esta lo que quedo pendiente)."
fi
echo
if [ "$USA_NM" = "1" ]; then
  echo " Conectarte y desconectarte:"
  for f in "${CONFIGS[@]}"; do
    base="$(basename "$f" .conf)"
    echo "   nmcli connection up $base      # conectar"
    echo "   nmcli connection down $base    # desconectar"
  done
  echo
  echo " O desde el icono de red del escritorio."
else
  echo " Conectarte y desconectarte:"
  for f in "${CONFIGS[@]}"; do
    base="$(basename "$f" .conf)"
    echo "   sudo wg-quick up $base      # conectar"
    echo "   sudo wg-quick down $base    # desconectar"
    echo "   sudo wg show $base          # ver el estado"
  done
fi
echo
echo " Abre https://devplay.dolynation.app o https://devapi.dolynation.app en el navegador."
echo "=============================================="

exit 0
