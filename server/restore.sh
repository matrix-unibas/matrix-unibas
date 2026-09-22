#!/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE=".env"
DATA_DIR="./data"

BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file $BACKUP_FILE not found."
  echo "Usage: $0 <backup_file>"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found."
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

echo "This script will delete the existing data in $DATA_DIR and restore it from the backup file $BACKUP_FILE."
echo "!!! WARNING: This action is irreversible. All existing data will be lost. !!!"
read -p "Are you sure you want to continue? (yes/no): " confirmation
if [[ "$confirmation" != "yes" ]]; then
  echo "Restoration stopped."
  exit 0
fi

echo "creating temporary directory for restoration"
STAGE_DIR="$(mktemp -d)"
cleanup () {
  echo "Cleaning up temporary directory..."
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

echo "Extracting backup file $BACKUP_FILE to temporary directory $STAGE_DIR"
tar -xf "$BACKUP_FILE" -C "$STAGE_DIR"

if [ ! -f "$STAGE_DIR/postgres.dump" ]; then
    echo "Error: Postgres dump not found in the backup. Restoration cannot proceed."
    exit 1
fi

echo "Stopping Synapse services"
docker compose stop synapse

echo "Restoring Postgres database from dump"
docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists < "$STAGE_DIR/postgres.dump"

echo "Restoring Synapse data and configuration"
rsync -a --delete "$STAGE_DIR/media_store" "$DATA_DIR/"
rsync -a "$STAGE_DIR/"*.signing.key "$DATA_DIR/"
rsync -a "$STAGE_DIR/homeserver.yaml" "$DATA_DIR/"

echo "Starting Synapse services"
docker compose start synapse

echo "Waiting for Synapse to be ready..."
until curl -sf "http://localhost:${SYNAPSE_HTTP_PORT}/health" >/dev/null 2>&1; do
  sleep 1
done

echo "Restoration completed successfully."