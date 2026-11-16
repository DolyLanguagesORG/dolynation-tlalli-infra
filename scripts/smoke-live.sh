#!/usr/bin/env bash
#
# Smoke contra el ambiente REAL de desarrollo: registra un usuario, elige
# plan, configura idiomas y categorias, y genera **una** lectura.
#
# POR QUE EXISTE
#
# Los e2e de los repositorios corren contra un API **mock**: verifican el
# contrato de la interfaz, pero no que el backend real, el proveedor de IA y
# la base de datos se hablen bien entre si. Ese es el hueco donde se colaron
# los 500 del schema y el 404 del badge de version.
#
# Este script cubre ese hueco, con el coste **acotado**: una lectura por
# corrida (1-3 llamadas al provider). Corre por la noche, no en cada push:
# consume cuota del tier gratis y depende de que el provider este disponible.
#
# Uso: smoke-live.sh <url-base-api>
#
# Devuelve 0 si la lectura se genero, 1 si no (con el motivo en pantalla).
set -uo pipefail

API="${1:?falta la URL base de la API}"
API="${API%/}"

EMAIL="smoke-live-$(date +%s)@example.com"
PASSWORD="SmokeLive1234!"

log() { echo "[smoke-live] $*"; }
ko() { echo "[smoke-live] FALLO: $*" >&2; exit 1; }

json() { python3 -c "import json,sys;d=json.load(sys.stdin);print(d$1)" 2>/dev/null; }

# ── 1. registro ──
log "registrando $EMAIL"
REG=$(curl -s --max-time 40 -X POST "$API/auth/register" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"fullName\":\"Smoke Live\",\"locale\":\"es\"}")
TOKEN=$(printf '%s' "$REG" | json "['data']['tokens']['accessToken']" || true)
[ -n "$TOKEN" ] || ko "no se pudo registrar: $(printf '%s' "$REG" | head -c 200)"

# ── 2. plan ──
log "eligiendo plan"
SUB=$(curl -s --max-time 40 -X POST "$API/user/subscription" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"tier":"dolly"}')
printf '%s' "$SUB" | grep -q '"hasSubscription":true' || ko "no se pudo elegir plan: $(printf '%s' "$SUB" | head -c 200)"

# ── 3. idiomas y categorias ──
log "configurando idiomas y categorias"
curl -s --max-time 40 -X PUT "$API/settings/languages" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"languages":["en"]}' | grep -q '"selected"' \
  || ko "no se pudieron configurar los idiomas"

curl -s --max-time 60 -X PUT "$API/settings/categories" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"categories":["Historia de Mexico","Tecnologia","Ciencia"]}' | grep -q '"selected"' \
  || ko "no se pudieron configurar las categorias"

# ── 4. LA lectura (la unica que consume cuota) ──
log "generando UNA lectura contra el provider real"
READING=$(curl -s --max-time 240 -X POST "$API/readings" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"category":"Historia de Mexico","difficulty":"medium","language":"en"}')

if printf '%s' "$READING" | grep -q '"title"'; then
  TITLE=$(printf '%s' "$READING" | json "['data']['title']")
  WORDS=$(printf '%s' "$READING" | json "['data']['wordCount']")
  log "OK: lectura generada en el ambiente real -> '$TITLE' ($WORDS palabras)"
  exit 0
fi

# ── 5. si falla: decir por que, no "algo fallo" ──
CODE=$(printf '%s' "$READING" | json "['error']['code']" || true)
DETAILS=$(printf '%s' "$READING" | json "['error']['details']" || true)
log "la lectura no se genero: $CODE $DETAILS"
case "$CODE" in
  AI_RATE_LIMITED)
    log "es la CUOTA del provider (429): no es un fallo del despliegue, es el tier gratis."
    ;;
  SERVICE_UNAVAILABLE)
    log "el provider no respondio. Mirar los fallos en GET /api/v1/admin/prompt-logs."
    ;;
esac
ko "la generacion de lectura fallo en el ambiente real"
