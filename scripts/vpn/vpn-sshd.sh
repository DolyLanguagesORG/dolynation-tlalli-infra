#!/usr/bin/env bash
#
# Endurece el acceso SSH del servidor de DolyNation.
#
# Que cambia:
#   - El puerto de escucha pasa de 22 a 50022 (el 22 se queda abierto
#     mientras la migracion del bot no este hecha: sshd escucha en los dos).
#   - Root no puede entrar por SSH.
#   - Sin reenvio X11, sin forwarding de TCP/IP, sin display.
#   - MaxAuthTries bajo, para que un intento de fuerza bruta no pueda
#     probar muchas llaves.
#
# El deploy de GitHub Actions sigue entrando por el puerto que diga el
# secret DEPLOY_PORT: cambiar ese secret es lo que migra el bot, sin tocar
# ningun workflow.
#
# Uso: vpn-sshd.sh apply | show | verify
set -euo pipefail

NEW_PORT=50022
OLD_PORT=22
CONF="/etc/ssh/sshd_config.d/60-doly-vpn.conf"

apply() {
  echo "== configurando sshd =="

  # La configuracion va en un fichero aparte: /etc/ssh/sshd_config no se
  # toca, asi el fichero de la distribucion se puede actualizar sin
  # perder estos ajustes.
  cat > "$CONF" <<EOF
# Endurecimiento de SSH para DolyNation.
# Gestionado por vpn-sshd.sh: no editar a mano.

Port $NEW_PORT
Port $OLD_PORT

# Root no entra por SSH: se usa un usuario normal con sudo.
PermitRootLogin no

# Solo llave publica. Sin contrasenas, sin teclado interactivo.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

# Nada de forwarding ni de display: el servidor no es un puente.
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no

# Fuerza bruta: pocas tentativas y poco tiempo.
MaxAuthTries 3
MaxSessions 4
LoginGraceTime 20
PermitUserEnvironment no

# Solo estos usuarios pueden entrar.
AllowUsers ubuntu ddeploy

# Las llaves de los developers se revocan una por una en
# /home/ddeploy/.ssh/authorized_keys.
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
  chmod 644 "$CONF"

  echo "== validando la configuracion =="
  # Si la configuracion nueva estuviera mal, sshd no arranca y el servidor
  # se queda sin acceso. Se valida ANTES de reiniciar.
  if ! sshd -t 2>/tmp/sshd-test.err; then
    echo "ERROR: la configuracion de sshd no es valida:" >&2
    cat /tmp/sshd-test.err >&2
    echo "       no se reinicia nada; el servidor sigue con la config anterior" >&2
    exit 1
  fi
  rm -f /tmp/sshd-test.err

  echo "== desactivando ssh.socket =="
  # Con ssh.socket activo, systemd abre el 22 y arranca sshd por socket:
  # la directiva Port de sshd_config se ignora. Hay que desactivar el
  # socket para que sshd escuche en el puerto configurado.
  if systemctl is-enabled --quiet ssh.socket 2>/dev/null; then
    systemctl disable --now ssh.socket >/dev/null 2>&1 || true
    systemctl reset-failed ssh.socket >/dev/null 2>&1 || true
    echo "  ssh.socket desactivado"
  fi

  echo "== reiniciando sshd =="
  # Un reload no abre un puerto nuevo: hace falta reiniciar.
  systemctl restart ssh
  sleep 2
  systemctl is-active --quiet ssh && echo "  sshd activo" || {
    echo "ERROR: sshd no quedo activo" >&2
    exit 1
  }
}

show() {
  sudo sshd -T | grep -E "^(port|permitrootlogin|pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|x11forwarding|allowtcpforwarding|maxauthtries|maxsessions|allowusers|logingracetime|permituserenvironment|permittunnel|gatewayports) "
}

verify() {
  local fail=0
  # `sshd -T` sin privilegios no puede leer las host keys y sale vacio.
  SSHD_T="$(sudo sshd -T)"

  check() {
    # Comparacion exacta de la linea que devuelve `sshd -T`.
    # `allowusers` sale en una linea por usuario, asi que se busca el
    # prefijo del nombre.
    local valor="${2:-}"
    if [ -n "$valor" ]; then
      # Coincidencia por prefijo: "allowusers ubuntu" casa con la linea
      # "allowusers ubuntu ddeploy".
      if printf '%s\n' "$SSHD_T" | grep -qE "^$1 $valor( |$)"; then
        echo "  OK   $1 $valor"
        return
      fi
    elif printf '%s\n' "$SSHD_T" | grep -qxF "$1"; then
      echo "  OK   $1"
      return
    fi
    echo "  FALLA  $1 $valor"
    fail=1
  }
  echo "== configuracion efectiva =="
  check "port $NEW_PORT"
  check "port $OLD_PORT"
  check "permitrootlogin no"
  check "passwordauthentication no"
  check "kbdinteractiveauthentication no"
  check "pubkeyauthentication yes"
  check "x11forwarding no"
  check "allowtcpforwarding no"
  check "maxauthtries 3"
  check "allowusers" "ubuntu"
  check "allowusers" "ddeploy"
  echo "== escuchando =="
  ss -tln | grep -q ":$NEW_PORT" && echo "  OK   escucha en $NEW_PORT" \
    || { echo "  FALLA  no escucha en $NEW_PORT"; fail=1; }
  exit $fail
}

case "${1:-show}" in
  apply) apply ;;
  show) show ;;
  verify) verify ;;
  *) echo "uso: $0 {apply|show|verify}" >&2; exit 1 ;;
esac
