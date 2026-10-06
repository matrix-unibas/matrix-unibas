#!/usr/bin/env bash
set -euo pipefail

# Generate a random 32-byte hex string (64 hex characters)
generate_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    od -vN 32 -An -tx1 /dev/urandom | tr -d ' \n'
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="${1:-$SCRIPT_DIR/.env}"
EXAMPLE_FILE="${2:-$SCRIPT_DIR/.env.example}"

if [ ! -f "$EXAMPLE_FILE" ] && [ -f "$SCRIPT_DIR/env.example" ]; then
  EXAMPLE_FILE="$SCRIPT_DIR/env.example"
fi

if [ ! -f "$EXAMPLE_FILE" ]; then
  echo "Error: Example file not found at '$EXAMPLE_FILE'" >&2
  exit 1
fi

# Check if .env file is already present
if [ -f "$TARGET_FILE" ]; then
  echo "Error: Environment file already exists at '$TARGET_FILE'" >&2
  exit 1
fi

# Prompt user for confirmation
read -rp "Are you sure you want to create a new .env file at '$TARGET_FILE'? (yes/no): " confirmation
if [[ ! "$confirmation" =~ ^[Yy]([Ee][Ss])?$ ]]; then
  echo "Creation aborted."
  exit 0
fi

# Ensure parent directory exists
mkdir -p "$(dirname "$TARGET_FILE")"

POSTGRES_PASSWORD="$(generate_hex)"
SYNAPSE_REGISTRATION_SHARED_SECRET="$(generate_hex)"
SYNAPSE_MACAROON_SECRET_KEY="$(generate_hex)"
SYNAPSE_FORM_SECRET="$(generate_hex)"
SYNAPSE_TURN_SHARED_SECRET="$(generate_hex)"
MAUBOT_ADMIN_PASSWORD="$(generate_hex)"
MAUBOT_ADMIN_PASS="$(generate_hex)"
USERBOTS_ADMIN_PASSWORD="$(generate_hex)"
USERBOTS_CRYPTO_PICKLE_KEY="$(generate_hex)"

sed \
  -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" \
  -e "s|^SYNAPSE_REGISTRATION_SHARED_SECRET=.*|SYNAPSE_REGISTRATION_SHARED_SECRET=${SYNAPSE_REGISTRATION_SHARED_SECRET}|" \
  -e "s|^SYNAPSE_MACAROON_SECRET_KEY=.*|SYNAPSE_MACAROON_SECRET_KEY=${SYNAPSE_MACAROON_SECRET_KEY}|" \
  -e "s|^SYNAPSE_FORM_SECRET=.*|SYNAPSE_FORM_SECRET=${SYNAPSE_FORM_SECRET}|" \
  -e "s|^SYNAPSE_TURN_SHARED_SECRET=.*|SYNAPSE_TURN_SHARED_SECRET=${SYNAPSE_TURN_SHARED_SECRET}|" \
  -e "s|^MAUBOT_ADMIN_PASSWORD=.*|MAUBOT_ADMIN_PASSWORD=${MAUBOT_ADMIN_PASSWORD}|" \
  -e "s|^MAUBOT_ADMIN_PASS=.*|MAUBOT_ADMIN_PASS=${MAUBOT_ADMIN_PASS}|" \
  -e "s|^USERBOTS_ADMIN_PASSWORD=.*|USERBOTS_ADMIN_PASSWORD=${USERBOTS_ADMIN_PASSWORD}|" \
  -e "s|^USERBOTS_CRYPTO_PICKLE_KEY=.*|USERBOTS_CRYPTO_PICKLE_KEY=${USERBOTS_CRYPTO_PICKLE_KEY}|" \
  "$EXAMPLE_FILE" > "$TARGET_FILE"

chmod 600 "$TARGET_FILE"
echo "Environment file created successfully at: $TARGET_FILE"
