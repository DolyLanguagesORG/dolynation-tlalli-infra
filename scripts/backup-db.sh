#!/usr/bin/env bash
#
# Crea respaldo lógico comprimido (`pg_dump -Fc`) de PostgreSQL en Docker con
# permisos 0600 (umask 077) y rotación automática por antigüedad.
#
# Uso:
#   POSTGRES_CONTAINER=doly-prod-db BACKUP_DIR=/var/backups/dolynglish ./scripts/backup-db.sh
set -euo pipefail

umask 077

POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-doly-prod-db}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-dolynglish}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker no está disponible en PATH." >&2
  exit 1
fi

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: RETENTION_DAYS debe ser un entero positivo (recibido: '$RETENTION_DAYS')." >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET="$BACKUP_DIR/${POSTGRES_DB}_${TIMESTAMP}.dump"

echo "[backup-db] Generando respaldo de '$POSTGRES_DB' desde contenedor '$POSTGRES_CONTAINER'..."
docker exec "$POSTGRES_CONTAINER" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc > "$TARGET"

if [ ! -s "$TARGET" ]; then
  rm -f "$TARGET"
  echo "ERROR: el archivo de respaldo salió vacío." >&2
  exit 1
fi

chmod 600 "$TARGET"
echo "[backup-db] OK: respaldo guardado en $TARGET ($(wc -c < "$TARGET") bytes)."

if [ "$RETENTION_DAYS" -gt 0 ]; then
  DELETED_COUNT="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.dump' -mtime +"$RETENTION_DAYS" -print -delete | wc -l)"
  echo "[backup-db] Rotación completada (retención=${RETENTION_DAYS}d, eliminados=${DELETED_COUNT})."
fi
