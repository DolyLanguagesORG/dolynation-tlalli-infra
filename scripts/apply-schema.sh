#!/usr/bin/env bash
#
# Deja la base del ambiente con el schema actual.
#
# POR QUE EXISTE
#
# El schema vive en **un solo archivo**: `database/postgres/01-init.sql`.
# PostgreSQL ejecuta los scripts de `/docker-entrypoint-initdb.d` **solo cuando
# el volumen de datos esta vacio** (la primera vez que se crea la base). En un
# ambiente que ya existe, cambiar el schema **no se aplica solo**: la base se
# queda con el schema viejo y el backend nuevo falla con "columna o tabla
# inexistente" (HTTP 500 en endpoints que antes funcionaban).
#
# QUE HACE
#
#   1. Calcula el hash de `01-init.sql` (la huella del schema).
#   2. Lo compara con el hash guardado **dentro de la base**, en la tabla
#      `schema_metadata`. El estado vive junto a los datos: si alguien borra
#      el volumen, el hash tambien se borra y el script vuelve a aplicarlo.
#   3. Si coincide -> no se toca nada (el caso normal de cada deploy).
#   4. Si NO coincide -> el schema cambio:
#        - si la base NO tiene datos -> se **recrea** y PostgreSQL aplica el
#          schema solo, al arrancar con el volumen vacio;
#        - si la base TIENE datos -> NO se toca nada y el script **falla**,
#          para que alguien migre a mano. Se puede forzar con `FORCE=1`.
#
# MODOS
#
#   - `FORCE=1` recrea la base aunque tenga datos. Solo para ambientes de
#     prueba (desarrollo), donde los datos son desechables.
#   - `CHECK_ONLY=1` no modifica nada: solo informa si el schema esta al dia.
#     Devuelve 1 si esta desactualizado (util en la CI y en el diagnostico).
#
# VARIABLES DE ENTORNO
#
#   COMPOSE_FILE  compose del ambiente (por defecto el de desarrollo)
#   DB_SERVICE    servicio de la base (por defecto se detecta: `db` o
#                 `database`, segun el compose)
#   SCHEMA_FILE   schema a aplicar (por defecto el del repo de infra)
#   FORCE=1       recrea la base aunque tenga datos
#   CHECK_ONLY=1  solo informa; no modifica nada
#
# VER operations/PLAN-DE-DESPLIEGUE.md y conventions/database.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${INFRA_DIR:-$(dirname "$SCRIPT_DIR")}"
SCHEMA_FILE="${SCHEMA_FILE:-$INFRA_DIR/database/postgres/01-init.sql}"
COMPOSE_FILE="${COMPOSE_FILE:-$INFRA_DIR/docker-compose.dev.yml}"
DB_SERVICE="${DB_SERVICE:-}"
DB_CONTAINER="${DB_CONTAINER:-}"
FORCE="${FORCE:-0}"
CHECK_ONLY="${CHECK_ONLY:-0}"

# Las 22 tablas que el backend mapea con Drizzle. Si falta alguna, el schema
# esta mal y el backend revienta al primer query.
EXPECTED_TABLES="roles users user_oauth_accounts user_settings auth_access_tokens auth_email_tokens access_requests readings friendships friend_invite_links user_blocks friend_streaks friend_streak_days reading_explanations prompt_logs moderated_categories category_daily_usage audit_logs error_logs billing_subscriptions billing_payments billing_webhook_events"
# Los nombres van entre comillas simples: en SQL son valores, no columnas.
EXPECTED_TABLES_SQL="$(echo "$EXPECTED_TABLES" | tr ' ' ',' | sed "s/[a-zA-Z_][a-zA-Z0-9_]*/'&'/g")"

log() { echo "[apply-schema] $*"; }
die() { echo "[apply-schema] ERROR: $*" >&2; exit 1; }

[ -f "$SCHEMA_FILE" ] || die "no existe el schema $SCHEMA_FILE"
[ -f "$COMPOSE_FILE" ] || die "no existe el compose $COMPOSE_FILE"

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }

# --- 1. Servicio y contenedor de la base ----------------------------------
if [ -z "$DB_SERVICE" ]; then
  # Se busca el servicio cuya imagen es PostgreSQL: cada compose le pone un
  # nombre distinto (`db` en dev, `database` en env, `postgres` en test).
  DB_SERVICE="$(compose config 2>/dev/null | awk '
    /^  [a-zA-Z0-9_.-]+:$/ { svc = $1; sub(/:$/, "", svc) }
    /image: postgres/ { print svc; exit }
  ')"
fi
if [ -z "$DB_SERVICE" ]; then
  # Fallback: los nombres conocidos.
  DB_SERVICE="$(compose config --services 2>/dev/null | grep -E '^(db|database|postgres)$' | head -1 || true)"
fi
[ -n "$DB_SERVICE" ] || die "no se encontro el servicio de la base en $COMPOSE_FILE"

if [ -z "$DB_CONTAINER" ]; then
  # `ps -a` esta acotado al proyecto del compose, asi que con varios
  # ambientes en el mismo servidor no se confunde una base con otra.
  DB_CONTAINER="$(compose ps -a --format '{{.Name}} {{.Service}}' 2>/dev/null \
    | awk -v svc="$DB_SERVICE" '$2 == svc { print $1; exit }')"
fi
log "Servicio de la base: $DB_SERVICE${DB_CONTAINER:+ (contenedor: $DB_CONTAINER)}"

# --- 2. Hash del schema -----------------------------------------------------
NEW_HASH="$(sha256sum "$SCHEMA_FILE" | cut -d' ' -f1)"
log "Hash del schema: ${NEW_HASH:0:12}"

# --- 3. Asegurar que la base esta levantada y acepta conexiones -----------
psql_q() {
  # psql_q <sql>  ->  una linea de salida (sin cabecera, sin espacios)
  printf '%s\n' "$1" | docker exec -i "$DB_CONTAINER" sh -c \
    'PGPASSWORD="$POSTGRES_PASSWORD" psql -qtA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f -'
}

# La tabla `schema_metadata` es contabilidad del deploy, no parte del schema
# de la aplicacion: por eso no esta en 01-init.sql.
ensure_metadata_table() {
  psql_q "CREATE TABLE IF NOT EXISTS schema_metadata (
  id INTEGER PRIMARY KEY,
  schema_hash TEXT NOT NULL,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);" >/dev/null
}

wait_ready() {
  # El entrypoint de Postgres arranca un servidor **temporal** para correr los
  # scripts de initdb y luego lo reinicia. Durante esa ventana el servidor
  # responde, pero al reiniciarse cualquier consulta falla con "the database
  # system is shutting down".
  #
  # Por eso no basta con `pg_isready`: se exige que el servidor final
  # responda **por TCP** (el temporal solo escucha en el socket) y que una
  # consulta real funcione, dos veces seguidas.
  local ok=0
  for _ in $(seq 1 60); do
    if docker exec "$DB_CONTAINER" pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1 \
      && docker exec "$DB_CONTAINER" sh -c \
        'PGPASSWORD="$POSTGRES_PASSWORD" psql -qtA -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select 1"' \
        >/dev/null 2>&1; then
      ok=$((ok + 1))
      if [ "$ok" -ge 2 ]; then
        return 0
      fi
    else
      ok=0
    fi
    sleep 1
  done
  return 1
}

if [ -z "$DB_CONTAINER" ]; then
  log "La base no estaba levantada: se levanta."
  compose up -d "$DB_SERVICE" >/dev/null
  DB_CONTAINER="$(compose ps -a --format '{{.Name}} {{.Service}}' 2>/dev/null \
    | awk -v svc="$DB_SERVICE" '$2 == svc { print $1; exit }')"
  [ -n "$DB_CONTAINER" ] || die "el contenedor de la base no aparecio"
fi

wait_ready || die "la base no acepto conexiones tras 90s"
log "La base acepta conexiones."

# --- 4. Hash guardado en la base vs. el del archivo ------------------------
ensure_metadata_table

OLD_HASH="$(psql_q "SELECT schema_hash FROM schema_metadata WHERE id = 1;" 2>/dev/null | tr -d '[:space:]' || true)"

if [ "$NEW_HASH" = "$OLD_HASH" ]; then
  log "El schema ya esta aplicado (hash ${NEW_HASH:0:12}): no se toca la base."
  exit 0
fi

log "El schema cambio (${OLD_HASH:0:12} -> ${NEW_HASH:0:12})."

# --- 5. Cuantos datos hay --------------------------------------------------
USERS="$(psql_q "SELECT count(*) FROM users;" 2>/dev/null | tr -d '[:space:]' || echo "")"
case "$USERS" in
  ''|*[!0-9]*) USERS="" ;;
esac

if [ "$CHECK_ONLY" = "1" ]; then
  log "CHECK_ONLY=1: el schema esta desactualizado (no se modifica nada)."
  exit 1
fi

if [ -n "$USERS" ] && [ "$USERS" != "0" ] && [ "$FORCE" != "1" ]; then
  log "La base tiene $USERS usuario(s): NO se recrea."
  log "El schema cambio y la base tiene datos. Hace falta una migracion"
  log "incremental (database/postgres/updates/NN-*.sql) o, si los datos no"
  log "valen, recrearla a mano con FORCE=1."
  exit 1
fi

if [ -n "$USERS" ] && [ "$USERS" != "0" ]; then
  log "FORCE=1: se recrea la base aunque tenga $USERS usuario(s)."
else
  log "La base no tiene datos: se puede recrear sin perder nada."
fi

# --- 6. Recrear la base -----------------------------------------------------
# Postgres solo aplica `01-init.sql` cuando el volumen esta vacio, asi que
# hay que quitar el volumen y el contenedor, y volver a levantarlos.
DATA_VOLUME=""
if [ -n "$DB_CONTAINER" ]; then
  DATA_VOLUME="$(docker inspect "$DB_CONTAINER" \
    --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' \
    2>/dev/null || true)"
fi

log "Quitando el contenedor de la base"
compose rm -sf "$DB_SERVICE" >/dev/null 2>&1 || true

if [ -n "$DATA_VOLUME" ]; then
  log "Quitando el volumen de datos $DATA_VOLUME"
  docker volume rm "$DATA_VOLUME" >/dev/null 2>&1 || true
fi

log "Levantando la base: se aplica $(basename "$SCHEMA_FILE")"
compose up -d "$DB_SERVICE" >/dev/null

DB_CONTAINER="$(compose ps -a --format '{{.Name}} {{.Service}}' 2>/dev/null \
  | awk -v svc="$DB_SERVICE" '$2 == svc { print $1; exit }')"
[ -n "$DB_CONTAINER" ] || die "el contenedor de la base no aparecio"
wait_ready || die "la base no acepto conexiones tras 90s"

# --- 7. Verificar que el schema quedo bien ----------------------------------
# La espera real no es "pg_isready" (que solo dice que el proceso levanta),
# sino que las tablas del schema existan.
APPLIED=0
for _ in $(seq 1 45); do
  sleep 2
  if [ "$(psql_q "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_name IN ($EXPECTED_TABLES_SQL);" | tr -d '[:space:]')" = "22" ]; then
    APPLIED=1
    break
  fi
done
[ "$APPLIED" = "1" ] || die "el schema no quedo aplicado tras 90s"

log "Schema aplicado: las 22 tablas del backend estan."

# --- 8. Guardar el hash -----------------------------------------------------
# La tabla se crea otra vez: si la base se recreo, se fue con ella.
ensure_metadata_table

psql_q "INSERT INTO schema_metadata (id, schema_hash, applied_at)
VALUES (1, '$NEW_HASH', NOW())
ON CONFLICT (id) DO UPDATE
  SET schema_hash = EXCLUDED.schema_hash, applied_at = EXCLUDED.applied_at;" >/dev/null

log "Hash guardado en la base (schema_metadata): ${NEW_HASH:0:12}"

# --- 9. Reiniciar el backend ------------------------------------------------
# La base se recreo: el backend que estaba corriendo tiene conexiones
# muertas a una base que ya no existe. Sin reiniciarlo, sus primeras
# consultas fallan con "the database system is shutting down" (HTTP 500).
if compose config --services 2>/dev/null | grep -qx backend; then
  log "Reiniciando el backend para que reconecte a la base nueva"
  compose restart backend >/dev/null 2>&1 || true
fi

log "Listo."
