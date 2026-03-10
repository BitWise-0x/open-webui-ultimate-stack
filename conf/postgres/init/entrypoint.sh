#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh — Custom PostgreSQL entrypoint for pgvector extension management
# =============================================================================
#
# This script wraps the official postgres docker-entrypoint.sh to ensure the
# pgvector (vector) extension is created and kept up to date on every container
# start. It is designed for Docker Swarm where containers may be rescheduled.
#
# What it does:
#   1. Removes stale postmaster.pid (safe for Swarm rescheduling after crash)
#   2. Starts the official docker-entrypoint.sh in the background
#   3. Waits for PostgreSQL to accept connections (up to 300s)
#   4. Creates the 'vector' extension if it doesn't exist
#   5. Upgrades the 'vector' extension to match the installed shared library
#   6. Forwards SIGTERM/SIGINT/SIGQUIT to the postgres process
#
# Mount path (compose):
#   ${DATA_ROOT}/open-webui/postgres/init:/init:ro
#
# Compose entrypoint:
#   entrypoint: ["/init/entrypoint.sh"]
#   command: ["postgres"]
#
# Environment variables (from env/db.env):
#   POSTGRES_DB        Database name (default: openwebui)
#   POSTGRES_USER      Database user (default: postgres)
#   POSTGRES_PASSWORD  Database password
# =============================================================================

set -e

# Forward termination signals to the background postgres process
PG_PID=0
cleanup() {
  if [ "$PG_PID" -ne 0 ]; then
    echo "[init] Forwarding signal to PostgreSQL (PID ${PG_PID})..."
    kill -TERM "$PG_PID" 2>/dev/null || true
    wait "$PG_PID" 2>/dev/null || true
  fi
}
trap cleanup SIGTERM SIGINT SIGQUIT

# Remove stale postmaster.pid file if it exists
if [ -f "/var/lib/postgresql/data/postmaster.pid" ]; then
  echo "[init] Removing stale postmaster.pid file..."
  rm -f /var/lib/postgresql/data/postmaster.pid
fi

# Start the default entrypoint in the background
/usr/local/bin/docker-entrypoint.sh "$@" &
PG_PID=$!
echo "[init] Waiting for PostgreSQL to be ready..."

# Check for DB connection (timeout after 300s)
MAX_WAIT=300
waited=0
until pg_isready -h localhost -p 5432 -U "$POSTGRES_USER" > /dev/null 2>&1; do
  sleep 1
  waited=$((waited + 1))
  if [ "$waited" -ge "$MAX_WAIT" ]; then
    echo "[init] ERROR: PostgreSQL did not become ready after ${MAX_WAIT}s — aborting" >&2
    exit 1
  fi
  [ $((waited % 5)) -eq 0 ] && echo "[init] waiting... (${waited}/${MAX_WAIT}s)"
done

echo "[init] PostgreSQL is up..."

# Set the internal PGPASSWORD env. variable
export PGPASSWORD="$POSTGRES_PASSWORD"

# Check for 'pgvector' extension
echo "[init] Checking for 'pgvector' extension..."
if ! psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -tc "SELECT 1 FROM pg_extension WHERE extname = 'vector';" | grep -q 1; then
  echo "[init] 'pgvector' not found — setting up..."
  psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "CREATE EXTENSION IF NOT EXISTS vector;"
  echo "[init] 'pgvector' extension enabled ✅"
else
  echo "[init] 'pgvector' extension already enabled 👍"
fi

# Upgrade extension to match the installed shared library version.
# No-op if already current; upgrades catalog if library is newer.
psql -h localhost -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
  -c "ALTER EXTENSION vector UPDATE;"
echo "[init] 'pgvector' extension is at latest version"

# Wait for the main Postgres process to exit
wait "$PG_PID"
