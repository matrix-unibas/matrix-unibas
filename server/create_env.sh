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
TARGET_FILE="${1:-}"

# Determine target file location if not explicitly provided
if [ -z "$TARGET_FILE" ]; then
  if [ -d "$SCRIPT_DIR/test_synaps" ]; then
    TARGET_FILE="$SCRIPT_DIR/test_synaps/.env"
  else
    TARGET_FILE="$SCRIPT_DIR/.env"
  fi
fi

# Check if .env file is already present
if [ -f "$TARGET_FILE" ]; then
  echo "Error: Environment file already exists at '$TARGET_FILE'" >&2
  exit 1
fi

if [ "$TARGET_FILE" = "$SCRIPT_DIR/test_synaps/.env" ] && [ -f "$SCRIPT_DIR/.env" ]; then
  echo "Error: Environment file already exists at '$SCRIPT_DIR/.env'." >&2
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
MAUBOT_ADMIN_PASS="$(generate_hex)"

cat > "$TARGET_FILE" <<EOF
SERVER_NAME=matrix.dmi.unibas.ch
SYNAPSE_REPORT_STATS=no
SYNAPSE_IMAGE_TAG=v1.157.0
POSTGRES_DB=synapse
POSTGRES_USER=synapse
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
SYNAPSE_REGISTRATION_SHARED_SECRET=${SYNAPSE_REGISTRATION_SHARED_SECRET}
SYNAPSE_MACAROON_SECRET_KEY=${SYNAPSE_MACAROON_SECRET_KEY}
SYNAPSE_FORM_SECRET=${SYNAPSE_FORM_SECRET}
SYNAPSE_HTTP_PORT=8008

ADMIN_UI_PORT=8443
MAUBOT_ADMIN_PASS=${MAUBOT_ADMIN_PASS}
MAUBOT_ADMIN_PASSWORD=password_here_please!!!
MAUBOT_UI_PORT=29316
EOF

chmod 600 "$TARGET_FILE"
echo "Environment file created successfully at: $TARGET_FILE"

# If created in test_synaps/.env and running from root, also keep root .env in sync
if [ "$TARGET_FILE" = "$SCRIPT_DIR/test_synaps/.env" ] && [ -d "$SCRIPT_DIR/test_synaps" ]; then
  cp "$TARGET_FILE" "$SCRIPT_DIR/.env"
  chmod 600 "$SCRIPT_DIR/.env"
  echo "Also copied to: $SCRIPT_DIR/.env"
fi
