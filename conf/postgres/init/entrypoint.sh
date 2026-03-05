#!/usr/bin/env bash

# Custom entrypoint - enables vector extension

set -e

# Remove stale postmaster.pid file if it exists
if [ -f "/var/lib/postgresql/data/postmaster.pid" ]; then
  echo "[init] Removing stale postmaster.pid file..."
  rm -f /var/lib/postgresql/data/postmaster.pid
fi

# Start the default entrypoint in the background
/usr/local/bin/docker-entrypoint.sh "$@" &
echo "[init] Waiting for PostgreSQL to be ready..."

# Check for DB connection
until pg_isready -h db -p 5432 -U "$POSTGRES_USER" > /dev/null 2>&1; do
  echo "[init] waiting... 🕒"
  sleep 1
done

echo "[init] PostgreSQL is up..."

# Set the internal PGPASSWORD env. variable
export PGPASSWORD="$POSTGRES_PASSWORD"

# Check for 'pgvector' extension
echo "[init] Checking for 'pgvector' extension..."
if ! psql -h db -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      -tc "SELECT 1 FROM pg_extension WHERE extname = 'vector';" | grep -q 1; then
  echo "[init] 'pgvector' not found — setting up..."
  psql -h db -p 5432 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "CREATE EXTENSION IF NOT EXISTS vector;"
  echo "[init] 'pgvector' extension enabled ✅"
else
  echo "[init] 'pgvector' extension already enabled 👍"
fi

# Wait for the main Postgres process to exit
wait
