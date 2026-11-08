#!/usr/bin/env bash
#
# Smoke test: verifica que un ambiente desplegado responde lo que debe.
#
# Se ejecuta DESPUES del despliegue y falla si algo no cuadra: un smoke test
# que no puede fallar no sirve de nada.
#
# Solo comprueba lo mecanico (que responde, que devuelve 200, que la version
# es la del manifiesto). Lo que no se puede automatizar (que la lectura
# generada tenga sentido, que el diseno se vea bien) lo verifica una persona
# con el checklist de salida.
#
# Uso: smoke-test.sh <url-base-api> <url-base-frontend> <version-esperada>
set -uo pipefail

API="${1:?falta la URL de la API}"
WEB="${2:?falta la URL del frontend}"
EXPECTED_VERSION="${3:?falta la version esperada}"

PASS=0
FAIL=0

log() { echo "[smoke] $*"; }

ok() {
  PASS=$((PASS + 1))
  echo "  OK    $1"
}

ko() {
  FAIL=$((FAIL + 1))
  echo "  FALLA $1"
  [ -n "${2:-}" ] && echo "        $2"
}

# --- API: codigo HTTP esperado ---
check_status() {
  local path="$1" expected="$2" label="$3" method="${4:-GET}" body="${5:-}"
  local out status payload

  if [ "$method" = "POST" ]; then
    out="$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
      -d "$body" --max-time 20 "$API$path" 2>&1)"
  else
    out="$(curl -s -w '\n%{http_code}' --max-time 20 "$API$path" 2>&1)"
  fi

  status="$(printf '%s' "$out" | tail -n1)"
  payload="$(printf '%s' "$out" | sed '$d')"

  if [ "$status" = "$expected" ]; then
    ok "$label ($status)"
  else
    ko "$label" "esperado $expected, recibido $status"
  fi

  printf '%s' "$payload"
}

echo "== API =="
check_status "/api/v1/health/live" "200" "GET /health/live" >/dev/null
check_status "/api/v1/health/ready" "200" "GET /health/ready" >/dev/null

# --- La version desplegada tiene que ser la del manifiesto ---
VERSION_BODY="$(check_status "/api/v1/version" "200" "GET /version")"
ACTUAL_VERSION="$(printf '%s' "$VERSION_BODY" \
  | grep -oE '"appVersion"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 | cut -d'"' -f4)"

if [ -z "$ACTUAL_VERSION" ]; then
  ko "la version desplegada se puede leer" "no se encontro appVersion en la respuesta"
elif [ "$ACTUAL_VERSION" = "$EXPECTED_VERSION" ]; then
  ok "version desplegada = $ACTUAL_VERSION"
else
  ko "version desplegada" "esperada $EXPECTED_VERSION, recibida $ACTUAL_VERSION"
fi

# --- La cabecera X-App-Version tiene que venir en toda respuesta ---
HEADER="$(curl -s -D - -o /dev/null --max-time 20 "$API/api/v1/health/live" 2>&1 \
  | grep -i '^x-app-version:' | tr -d '\r' | awk '{print $2}')"

if [ -n "$HEADER" ]; then
  ok "cabecera X-App-Version ($HEADER)"
else
  ko "cabecera X-App-Version" "no vino en la respuesta"
fi

# --- Autenticacion: register + login + me ---
EMAIL="smoke-$(date +%s)@example.com"
PASSWORD="SmokeTest1234!"

REGISTER="$(check_status "/api/v1/auth/register" "201" "POST /auth/register" POST \
  "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Smoke Test\"}")"

LOGIN="$(check_status "/api/v1/auth/login" "200" "POST /auth/login" POST \
  "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"

TOKEN="$(printf '%s' "$LOGIN" | grep -oE '"accessToken"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -1 | cut -d'"' -f4)"

if [ -n "$TOKEN" ]; then
  ok "el login devuelve access token"

  ME="$(curl -s -w '\n%{http_code}' --max-time 20 \
    -H "Authorization: Bearer $TOKEN" "$API/api/v1/auth/me" 2>&1)"
  ME_STATUS="$(printf '%s' "$ME" | tail -n1)"

  if [ "$ME_STATUS" = "200" ]; then
    ok "GET /auth/me con token (200)"
  else
    ko "GET /auth/me con token" "recibido $ME_STATUS"
  fi
else
  ko "el login devuelve access token" "no se encontro accessToken en la respuesta"
fi

# --- Frontend ---
echo
echo "== Frontend =="
# Solo se comprueban las rutas que existen hoy. `/login` y `/register` estan
# pendientes de construccion (front#12 y el resto del sprint 3): incluirlas
# aqui haria que el smoke test fallara siempre por un motivo que no es del
# despliegue.
for path in "/"; do
  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$WEB$path" 2>&1)"
  if [ "$status" = "200" ]; then
    ok "GET $path (200)"
  else
    ko "GET $path" "recibido $status"
  fi
done

# El proxy de la API tiene que funcionar: es lo que permite que el
# navegador hable con el backend sin CORS ni preflight.
PROXY_STATUS="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
  "$WEB/api/v1/health/live" 2>&1)"
if [ "$PROXY_STATUS" = "200" ]; then
  ok "proxy /api/v1/health/live desde el frontend (200)"
else
  ko "proxy /api/v1/health/live desde el frontend" "recibido $PROXY_STATUS"
fi

echo
log "resultado: $PASS correctos, $FAIL fallidos"

if [ "$FAIL" -gt 0 ]; then
  log "FALLO: el despliegue no cumple el contrato"
  exit 1
fi

log "OK: el despliegue cumple el contrato"
