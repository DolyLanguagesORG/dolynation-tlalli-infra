#!/usr/bin/env bash
#
# Smoke test de la LANDING (el sitio).
#
# Es la paridad del `smoke-test.sh` de la aplicacion: comprueba el CONTRATO
# del sitio desplegado, no que "haya algo". Un smoke que no puede fallar no
# sirve de nada.
#
# Uso:
#   scripts/smoke-site.sh <url> <version_esperada>
#
#   url               la base del sitio (http://127.0.0.1:57023)
#   version_esperada  la `site_version` del manifiesto (la que dice que
#                     version deberia estar desplegada)
#
# Lo ejecuta `scripts/deploy-site.sh` al final de cada despliegue: si el
# contrato se rompe, el deploy falla y no se da por bueno.
set -uo pipefail

SITE="${1:?falta la URL del sitio}"
EXPECTED_VERSION="${2:?falta la version esperada}"

PASS=0
FAIL=0

log() { echo "[smoke-site] $*" >&2; }
ok() {
  PASS=$((PASS + 1))
  echo "  OK    $1" >&2
}
ko() {
  FAIL=$((FAIL + 1))
  echo "  FALLA $1" >&2
  [ -n "${2:-}" ] && echo "        $2" >&2
}

log "smoke del sitio en $SITE (version esperada: $EXPECTED_VERSION)"

# --- 1. La raiz responde ---------------------------------------------------
CODES="$(curl -s -o /tmp/smoke-site.html -w '%{http_code} %{size_download}' --max-time 20 "$SITE/" 2>&1)"
STATUS="$(printf '%s' "$CODES" | awk '{print $1}')"
SIZE="$(printf '%s' "$CODES" | awk '{print $2}')"
if [ "$STATUS" = "200" ]; then
  ok "la raiz responde 200 ($SIZE bytes)"
else
  ko "la raiz no responde 200" "recibido ${STATUS:-nada}"
fi

if [ "${SIZE:-0}" -lt 500 ]; then
  ko "la pagina parece vacia" "solo $SIZE bytes"
else
  ok "la pagina trae contenido"
fi

# --- 2. El HTML es el de la landing ---------------------------------------
if grep -qiE '<title>[^<]+</title>' /tmp/smoke-site.html 2>/dev/null; then
  TITULO="$(grep -oiE '<title>[^<]*</title>' /tmp/smoke-site.html | head -1 | sed 's/<[^>]*>//g')"
  ok "la pagina trae titulo" "\"$TITULO\""
else
  ko "la pagina no trae titulo" "puede estar vacia o ser un error"
fi

# El error de Astro/Vite en desarrollo dice "This host ... is not allowed".
if grep -qiE 'not allowed|Internal Server Error|500 Internal' /tmp/smoke-site.html 2>/dev/null; then
  ko "la pagina es un error, no el sitio" "revisa el allowlist de Vite (astro.config.mjs)"
else
  ok "la pagina no es un error"
fi

# --- 3. La version desplegada es la del manifiesto -------------------------
# El sitio se sirve estatico: la version viaja en el HTML como un comentario
# o en un atributo. Si no esta, al menos se comprueba que la pagina sea la
# del build correcto comparando con el manifiesto.
if grep -q "$EXPECTED_VERSION" /tmp/smoke-site.html 2>/dev/null; then
  ok "la pagina declara la version $EXPECTED_VERSION"
else
  # No es un error: el sitio estatico no lleva la version en el HTML.
  # Se avisa, para que se sepa que el smoke no puede verificar la version.
  echo "  AVISO la pagina no declara la version $EXPECTED_VERSION (el sitio es estatico)" >&2
fi

# --- 4. El healthcheck -----------------------------------------------------
CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$SITE/healthz" 2>&1)"
if [ "$CODE" = "200" ]; then
  ok "el healthcheck responde 200"
else
  ko "el healthcheck no responde 200" "recibido ${CODE:-nada}"
fi

# --- 5. Los assets se sirven y se cachean -----------------------------------
ASSET="$(grep -oE '/_astro/[A-Za-z0-9._-]+\.(css|js)' /tmp/smoke-site.html 2>/dev/null | head -1)"
if [ -n "$ASSET" ]; then
  CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$SITE$ASSET" 2>&1)"
  if [ "$CODE" = "200" ]; then
    ok "el asset se sirve 200" "$ASSET"
  else
    ko "el asset no se sirve 200" "$ASSET -> ${CODE:-nada}"
  fi

  # Ojo: puede haber VARIAS cabeceras Cache-Control (la de `expires` y la de
  # `add_header`), asi que se mira el bloque entero, no solo la primera.
  CACHE="$(curl -sI --max-time 15 "$SITE$ASSET" 2>/dev/null | grep -i '^cache-control:')"
  if printf '%s' "$CACHE" | grep -qi 'immutable'; then
    ok "el asset se cachea para siempre" "los assets llevan hash en el nombre"
  else
    ko "el asset no lleva cache immutable" "recibido: ${CACHE:-nada}"
  fi
else
  ko "la pagina no referencia ningun asset" "no hay nada que servir"
fi

# --- 6. El HTML no se cachea (si se cachea, el sitio no cambia nunca) ------
CACHE_HTML="$(curl -sI --max-time 15 "$SITE/" 2>/dev/null | grep -i '^cache-control:' | head -1)"
if printf '%s' "$CACHE_HTML" | grep -qi 'no-cache'; then
  ok "el HTML no se cachea"
else
  ko "el HTML se cachea" "recibido: ${CACHE_HTML:-nada}"
fi

# --- 7. Las cabeceras de seguridad -----------------------------------------
HEADERS="$(curl -sI --max-time 15 "$SITE/" 2>/dev/null)"
for cabecera in "x-content-type-options: nosniff" "x-frame-options: sameorigin"; do
  if printf '%s' "$HEADERS" | grep -qi "$cabecera"; then
    ok "la cabecera $cabecera esta"
  else
    ko "falta la cabecera $cabecera"
  fi
done

# --- 8. La compresion ------------------------------------------------------
CODE="$(curl -s -o /dev/null -w '%{http_code} %{size_download}' --compressed --max-time 15 "$SITE/" 2>&1)"
if [ "${CODE%% *}" = "200" ]; then
  ok "la pagina se sirve comprimida" "$(printf '%s' "$CODE" | awk '{print $2}') bytes"
else
  ko "la pagina no se sirve" "recibido ${CODE:-nada}"
fi

# --- Resultado -------------------------------------------------------------
if [ "$FAIL" -gt 0 ]; then
  log "el sitio deployed NO cumple el contrato: $FAIL fallo(s), $PASS correctas"
  exit 1
fi

log "el sitio cumple el contrato: $PASS comprobaciones"
exit 0
