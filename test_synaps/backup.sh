#!/usr/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

ENV_FILE=".env"
DATA_DIR="./data"
BACKUP_DIR="./backup"
KEEP_BACKUPS=1

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE."
  exit 1
fi

set -a; source "$ENV_FILE"; set +a

mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
STAGE_DIR="$BACKUP_DIR/.staging_$TIMESTAMP"
TMP_TAR="$BACKUP_DIR/.tmp_$TIMESTAMP.tar"
BACKUP_TAR="$BACKUP_DIR/synapse_backup_$TIMESTAMP.tar"

cleanup() {
  rm -rf "$STAGE_DIR" "$TMP_TAR"
}
trap cleanup EXIT

mkdir -p "$STAGE_DIR"

echo "dumping Postgres"
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom > "$STAGE_DIR/postgres.dump"

echo "syncing Synapse data + config + keys"
rsync -a \
    "$DATA_DIR/media_store" \
    "$DATA_DIR/"*.signing.key \
    "$DATA_DIR/homeserver.yaml" \
    "$STAGE_DIR/"

echo "creating tar"

tar -cf "$TMP_TAR" -C "$STAGE_DIR" .

mv "$TMP_TAR" "$BACKUP_TAR"
rm -rf "$STAGE_DIR"

echo "Backup created at $BACKUP_TAR"

echo "Cleaning up old backups, keeping $KEEP_BACKUPS most recent"
ls -1t "$BACKUP_DIR"/synapse_backup_*.tar | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f