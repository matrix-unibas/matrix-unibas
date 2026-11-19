#!/bin/bash
# Runs only on a fresh Postgres volume. On an existing server, see docs/admin-bot-setup.md.
set -e
: "${USERBOTS_DB_PASSWORD:?USERBOTS_DB_PASSWORD is not set}"
# The heredoc is quoted: the password never passes through the shell, psql inserts it (:'userbots_pw').
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v userbots_pw="$USERBOTS_DB_PASSWORD" -v main_db="$POSTGRES_DB" <<-'EOSQL'
  SELECT 'CREATE DATABASE maubot' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'maubot')\gexec
  -- Professor bots run unsandboxed plugins: their maubot gets an unprivileged role that owns only
  -- its own database (I12). The superuser keeps using synapse and maubot.
  CREATE ROLE userbots LOGIN PASSWORD :'userbots_pw' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;
  CREATE DATABASE userbots OWNER userbots;
  -- Only owners (and the superuser) may connect to the other databases.
  REVOKE CONNECT, TEMPORARY ON DATABASE :"main_db" FROM PUBLIC;
  REVOKE CONNECT, TEMPORARY ON DATABASE maubot FROM PUBLIC;
  REVOKE CONNECT, TEMPORARY ON DATABASE postgres FROM PUBLIC;
EOSQL
