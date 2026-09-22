#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

ENV_FILE=".env"
DATA_DIR="./data"
TEMPLATE="./homeserver.yaml.template"
ADMIN_CONFIG_TEMPLATE="./admin/config.json.template"
ADMIN_CONFIG_OUT="./admin/config.json"
CERT_DIR="./nginx/certs"
CERT_FILE="$CERT_DIR/admin-selfsigned.crt"
KEY_FILE="$CERT_DIR/admin-selfsigned.key"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — copy .env.example to .env and fill in real values first." >&2
  exit 1
fi

# Source environment variables AFTER checking and generating them
set -a; source "$ENV_FILE"; set +a

required_vars=(
  SERVER_NAME POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD
  SYNAPSE_REGISTRATION_SHARED_SECRET SYNAPSE_MACAROON_SECRET_KEY
  SYNAPSE_FORM_SECRET SYNAPSE_IMAGE_TAG SYNAPSE_HTTP_PORT SYNAPSE_REPORT_STATS
  ADMIN_UI_PORT MAUBOT_ADMIN_PASSWORD
)
for v in "${required_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Error: $v is not set in $ENV_FILE" >&2
    exit 1
  fi
done

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst not found" >&2
  exit 1
fi

export HOST_UID="$(id -u)"
export HOST_GID="$(id -g)"

mkdir -p "$DATA_DIR"

SIGNING_KEY="$DATA_DIR/${SERVER_NAME}.signing.key"
if [ ! -f "$SIGNING_KEY" ]; then
  echo "No signing key found, bootstrapping one via 'synapse generate'"
  docker run --rm \
    -e SYNAPSE_SERVER_NAME="$SERVER_NAME" \
    -e SYNAPSE_REPORT_STATS="$SYNAPSE_REPORT_STATS" \
    -e UID="$HOST_UID" \
    -e GID="$HOST_GID" \
    -v "$(pwd)/$DATA_DIR:/data" \
    "ghcr.io/element-hq/synapse:${SYNAPSE_IMAGE_TAG}" generate
else
  echo "Signing key already present, skipping bootstrap."
fi

echo "Rendering homeserver.yaml from template"
envsubst < "$TEMPLATE" > "$DATA_DIR/homeserver.yaml"

echo "Rendering admin UI config.json from template"
envsubst < "$ADMIN_CONFIG_TEMPLATE" > "$ADMIN_CONFIG_OUT"

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  echo "No admin UI TLS cert found, generating a self-signed one"
  openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -days 3650 -subj "/CN=admin.local"
else
  echo "Admin UI TLS cert already present, skipping generation."
fi

echo "Rendering Maubot configs"
mkdir -p ./maubot
sudo chown -R "$HOST_UID:$HOST_GID" ./maubot

# Render templates globally with all environment variables loaded
envsubst < "./maubot/config.yaml.template" > "./maubot/config.yaml"

sudo chown -R 1337:1337 ./maubot

echo "Starting stack"
docker compose up -d

echo "Waiting for Postgres"
until docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
  sleep 1
done

echo "Waiting for Synapse"
until curl -sf "http://localhost:${SYNAPSE_HTTP_PORT}/health" >/dev/null 2>&1; do
  sleep 1
done

echo "Synapse is up: http://localhost:${SYNAPSE_HTTP_PORT}"
echo "Admin UI is up: https://localhost:${ADMIN_UI_PORT} (reach it via: ssh -L ${ADMIN_UI_PORT}:localhost:${ADMIN_UI_PORT} <vm-host>)"
echo "Create an admin user with:"
echo "docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml http://localhost:8008"
echo "Then mark them as server admin in Postgres:"
echo "docker compose exec postgres psql -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -c \"UPDATE users SET admin = 1 WHERE name = '@USERNAME:${SERVER_NAME}';\""
