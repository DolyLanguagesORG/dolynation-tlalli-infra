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

# Los resultados van a **stderr**: asi `check_status` se puede usar con
# `> /dev/null` (para descartar el cuerpo) sin tragarse el "OK" de la
# comprobacion. Antes, el `> /dev/null` se comia el mensaje y el smoke test
# reportaba 5 correctos sin dejar claro cuales eran.
log() { echo "[smoke] $*" >&2; }

ok() {
  PASS=$((PASS + 1))
  echo "  OK    $1" >&2
}

ko() {
  FAIL=$((FAIL + 1))
  echo "  FALLA $1" >&2
  [ -n "${2:-}" ] && echo "        $2" >&2
}

# --- API: codigo HTTP esperado ---
# Imprime el cuerpo en stdout y deja el codigo HTTP en LAST_STATUS.
LAST_STATUS=""
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
  LAST_STATUS="$status"

  if [ "$status" = "$expected" ]; then
    ok "$label ($status)"
  else
    ko "$label" "esperado $expected, recibido $status"
  fi

  printf '%s' "$payload"
}

# --- API: llamada POST que devuelve "<status>|<cuerpo>" ---
api_post() {
  local path="$1" body="$2" out
  out="$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d "$body" --max-time 20 "$API$path" 2>&1)"
  printf '%s|%s' "$(printf '%s' "$out" | tail -n1)" "$(printf '%s' "$out" | sed '$d')"
}

echo "== API ==" >&2
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

# --- Seguridad anti-bot (Turnstile) y autenticacion -------------------------
# Si el ambiente tiene Turnstile activo (staging/prod), /auth/register y
# /auth/login DEBEN rechazar peticiones sin token (400 CAPTCHA_REQUIRED).
# Comprobar ese rechazo verifica que la proteccion anti-bot esta activa de
# verdad, igual que EMAIL_VERIFICATION_REQUIRED verifica el bloqueo de login.
CAPTCHA_OUT="$(curl -s -w '\n%{http_code}' --max-time 20 "$API/api/v1/security/captcha/config" 2>&1)"
CAPTCHA_STATUS="$(printf '%s' "$CAPTCHA_OUT" | tail -n1)"
CAPTCHA_BODY="$(printf '%s' "$CAPTCHA_OUT" | sed '$d')"
CAPTCHA_ENABLED="false"
if [ "$CAPTCHA_STATUS" = "200" ]; then
  CAPTCHA_ENABLED="$(printf '%s' "$CAPTCHA_BODY" \
    | grep -oE '"enabled"[[:space:]]*:[[:space:]]*(true|false)' \
    | head -1 | grep -oE '(true|false)$' || echo "false")"
fi

EMAIL="smoke-$(date +%s)@example.com"
PASSWORD="SmokeTest1234!"

if [ "$CAPTCHA_ENABLED" = "true" ]; then
  if printf '%s' "$CAPTCHA_BODY" | grep -qE '"provider"[[:space:]]*:[[:space:]]*"turnstile"' \
    && printf '%s' "$CAPTCHA_BODY" | grep -qE '"siteKey"[[:space:]]*:[[:space:]]*"[^"]+"'; then
    ok "GET /security/captcha/config (turnstile activo)"
  else
    ko "GET /security/captcha/config" "Turnstile activo sin provider/siteKey validos"
  fi

  REGISTER="$(api_post "/api/v1/auth/register" \
    "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Smoke Test\"}")"
  REG_STATUS="${REGISTER%%|*}"
  REG_BODY="${REGISTER#*|}"

  if [ "$REG_STATUS" = "400" ] && printf '%s' "$REG_BODY" | grep -q 'CAPTCHA_REQUIRED'; then
    ok "POST /auth/register sin captcha rechazado (400 CAPTCHA_REQUIRED)"
  else
    ko "POST /auth/register sin captcha" "esperado 400 CAPTCHA_REQUIRED, recibido $REG_STATUS"
  fi

  LOGIN="$(api_post "/api/v1/auth/login" "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
  LOG_STATUS="${LOGIN%%|*}"
  LOG_BODY="${LOGIN#*|}"

  if [ "$LOG_STATUS" = "400" ] && printf '%s' "$LOG_BODY" | grep -q 'CAPTCHA_REQUIRED'; then
    ok "POST /auth/login sin captcha rechazado (400 CAPTCHA_REQUIRED)"
  else
    ko "POST /auth/login sin captcha" "esperado 400 CAPTCHA_REQUIRED, recibido $LOG_STATUS"
  fi
else
  REGISTER="$(api_post "/api/v1/auth/register" \
    "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Smoke Test\"}")"
  REG_STATUS="${REGISTER%%|*}"
  REG_BODY="${REGISTER#*|}"

  if [ "$REG_STATUS" = "201" ]; then
    ok "POST /auth/register (201)"
  else
    ko "POST /auth/register" "esperado 201, recibido $REG_STATUS"
  fi

  # ¿Este ambiente exige confirmar el correo antes de poder entrar? En rehearsal
  # y en produccion si (`EMAIL_VERIFICATION_REQUIRED=true`). Entonces el login
  # NO devuelve token hasta que el correo este verificado: y eso tambien es
  # parte del contrato que hay que comprobar.
  REQUIRES_VERIFICATION="$(printf '%s' "$REG_BODY" \
    | grep -oE '"emailVerificationRequired"[[:space:]]*:[[:space:]]*(true|false)' \
    | head -1 | grep -oE '(true|false)$' || true)"

  LOGIN="$(api_post "/api/v1/auth/login" "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
  LOG_STATUS="${LOGIN%%|*}"
  LOG_BODY="${LOGIN#*|}"

  if [ "$REQUIRES_VERIFICATION" = "true" ]; then
    # Sin verificar: el login tiene que RECHAZAR, no devolver token.
    if printf '%s' "$LOG_BODY" | grep -q 'AUTH_EMAIL_NOT_VERIFIED'; then
      ok "login sin correo verificado rechazado (AUTH_EMAIL_NOT_VERIFIED, $LOG_STATUS)"
    else
      ko "login sin correo verificado" "se esperaba AUTH_EMAIL_NOT_VERIFIED, recibido $LOG_STATUS"
    fi
  else
    TOKEN="$(printf '%s' "$LOG_BODY" | grep -oE '"accessToken"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | cut -d'"' -f4)"

    if [ "$LOG_STATUS" = "200" ] && [ -n "$TOKEN" ]; then
      ok "el login devuelve access token"

      ME="$(curl -s -w '\n%{http_code}' --max-time 20 \
        -H "Authorization: Bearer $TOKEN" "$API/api/v1/auth/me" 2>&1)"
      ME_STATUS="$(printf '%s' "$ME" | tail -n1)"

      case "$ME_STATUS" in
        200)
          ok "GET /auth/me con token (200)"
          ;;
        403)
          # El token es valido (si no lo fuera, seria 401), pero el usuario que
          # acaba de registrarse no tiene plan de suscripcion y el backend
          # responde SUBSCRIPTION_REQUIRED. Tambien es parte del contrato.
          if printf '%s' "$ME" | grep -q 'SUBSCRIPTION_REQUIRED'; then
            ok "GET /auth/me con token (403 SUBSCRIPTION_REQUIRED: el usuario no tiene plan)"
          else
            ko "GET /auth/me con token" "recibido $ME_STATUS"
          fi
          ;;
        *)
          ko "GET /auth/me con token" "recibido $ME_STATUS"
          ;;
      esac
    else
      ko "el login devuelve access token" "recibido $LOG_STATUS"
    fi
  fi
fi

# --- Frontend ---
echo >&2
echo "== Frontend ==" >&2
# `/` es una ruta protegida: el proxy del frontend (proxy.ts) la redirige a
# `/login` (307) cuando no hay sesion. Un 200 tambien vale (si el ambiente
# deja pasar la peticion), pero un 307 tiene que ser a `/login`: eso es
# justamente la proteccion funcionando.
for path in "/"; do
  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$WEB$path" 2>&1)"
  case "$status" in
    200)
      ok "GET $path (200)"
      ;;
    307)
      location="$(curl -s -o /dev/null -D - --max-time 20 "$WEB$path" 2>&1 \
        | grep -i '^location:' | tr -d '\r' | awk '{print $2}')"
      case "$location" in
        */login*) ok "GET $path (307 -> /login, ruta protegida)" ;;
        *) ko "GET $path" "307 a '$location' (se esperaba /login)" ;;
      esac
      ;;
    *)
      ko "GET $path" "recibido $status"
      ;;
  esac
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

echo >&2
log "resultado: $PASS correctos, $FAIL fallidos"

if [ "$FAIL" -gt 0 ]; then
  log "FALLO: el despliegue no cumple el contrato"
  exit 1
fi

log "OK: el despliegue cumple el contrato"
