#!/usr/bin/env bash
#
# Persistencia de la VPN de DolyNation en el servidor.
#
# Instala:
#   - la unidad de la VPN (hub + peers de servicio),
#   - un timer que actualiza los rangos de GitHub Actions y de Cloudflare
#     (los rangos de Actions cambian: si el set se queda viejo, el bot
#     se queda sin poder desplegar),
#   - la persistencia de las reglas de firewall al arrancar,
#   - el resolutor DNS de la VPN (dnsmasq), que devuelve la IP DE TUNEL de
#     los servicios: sin el, el equipo resolveria los nombres por internet
#     y la peticion saldria del servidor sin pasar por el tunel.
#
# Uso: vpn-install.sh
set -euo pipefail

VPN_DIR="/etc/doly-vpn"
UNIT="/etc/systemd/system/doly-vpn.service"
TIMER="/etc/systemd/system/doly-vpn-refresh.service"
TIMER_TIMER="/etc/systemd/system/doly-vpn-refresh.timer"
DNS_UNIT="/etc/systemd/system/doly-dns.service"
DNS_CONF="/etc/dnsmasq-vpn.conf"

log() { echo "[install] $*"; }

# --- La unidad principal ----------------------------------------------------
cat > "$UNIT" <<EOF
[Unit]
# El hub de la VPN y los peers de servicio. Se levantan despues de que
# Docker este listo (los peers son contenedores) y de las reglas de
# firewall (el hub necesita su puerto UDP abierto).
Description=VPN de DolyNation (hub WireGuard y peers de servicio)
Documentation=file:///etc/doly-vpn/README.md
After=docker.service network-online.target netfilter-persistent.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$VPN_DIR/vpn-up.sh start
ExecStop=$VPN_DIR/vpn-up.sh stop
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# --- El refresco de los rangos ----------------------------------------------
cat > "$TIMER" <<EOF
[Unit]
Description=Actualiza los rangos de IP de GitHub Actions y Cloudflare
After=network-online.target

[Service]
Type=oneshot
ExecStart=$VPN_DIR/vpn-firewall.sh apply
EOF

cat > "$TIMER_TIMER" <<EOF
[Unit]
Description=Actualiza los rangos de IP de GitHub Actions y Cloudflare

[Timer]
# Cada 6 horas: los rangos de Actions cambian sin avisar.
OnBootSec=5min
OnUnitActiveSec=6h
RandomizedDelaySec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

log "habilitando las unidades"
systemctl daemon-reload
systemctl enable doly-vpn.service >/dev/null 2>&1 || true
systemctl enable doly-vpn-refresh.timer >/dev/null 2>&1 || true
systemctl start doly-vpn-refresh.timer >/dev/null 2>&1 || true

# --- El resolutor DNS de la VPN ---------------------------------------------
# El hub resuelve los nombres de los servicios a sus IPs de tunel:
#   devapi.yacaterkos.tech -> 10.90.0.2
#   devweb.yacaterkos.tech -> 10.90.0.3
#   minios.doly.internal   -> 10.90.0.4
# El resto de nombres se resuelven como siempre.
#
# Sin esto, el navegador del equipo resolveria el nombre a la IP publica de
# Cloudflare y la peticion saldria por su conexion normal: la VPN no
# filtraria nada.
log "instalando el resolutor DNS de la VPN"
if ! dpkg -l dnsmasq >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dnsmasq >/dev/null
fi
# El paquete trae un servicio que tambien hace DHCP: no se quiere. Se
# deshabilita y se usa una unidad propia, con su configuracion.
systemctl disable --now dnsmasq.service >/dev/null 2>&1 || true
systemctl mask dnsmasq.service >/dev/null 2>&1 || true

install -m 0644 -o root -g root "$(dirname "$0")/dnsmasq-vpn.conf" "$DNS_CONF"
install -m 0644 -o root -g root "$(dirname "$0")/doly-dns.service" "$DNS_UNIT"
systemctl daemon-reload
systemctl enable --now doly-dns.service >/dev/null 2>&1 || true

log "habilitando la persistencia del firewall"
if ! dpkg -l netfilter-persistent >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq netfilter-persistent >/dev/null
fi
systemctl enable netfilter-persistent >/dev/null 2>&1 || true

# Las reglas actuales, guardadas para el arranque.
log "guardando las reglas de firewall"
netfilter-persistent save >/dev/null 2>&1 || true

log "listo"
systemctl list-timers --all --no-pager | grep doly-vpn || true
