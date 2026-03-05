#!/usr/bin/env bash
#
# deploy-swarm.sh — Docker Swarm deployment helper
# Creates the overlay backend network and deploys the stack.
# Run from the repo root on a Swarm manager node.
#
set -euo pipefail

cd "$(dirname "$0")/.."

command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync is required. Install with: apt-get install rsync" >&2; exit 1; }

# Load top-level .env
if [ -f .env ]; then
  # shellcheck disable=SC1091
  set -o allexport; source .env; set +o allexport
else
  echo "ERROR: .env not found. Copy .env.example → .env and configure it first." >&2
  exit 1
fi

# Ensure required variables are set
: "${STACK_NAME:?STACK_NAME must be set in .env}"
: "${ROUTER_NAME:?ROUTER_NAME must be set in .env}"
: "${ROOT_DOMAIN:?ROOT_DOMAIN must be set in .env}"
: "${BACKEND_NETWORK_NAME:?BACKEND_NETWORK_NAME must be set in .env}"
: "${DATA_ROOT:?DATA_ROOT must be set in .env}"

# Load postgres password from db.env if not already set
if [ -z "${POSTGRES_PASSWORD:-}" ] && [ -f env/db.env ]; then
  POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' env/db.env | cut -d= -f2-)
fi
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD not found. Set it in env/db.env}"

echo "[*] Stack:          ${STACK_NAME}"
echo "[*] Domain:         ${ROUTER_NAME}.${ROOT_DOMAIN}"
echo "[*] Backend net:    ${BACKEND_NETWORK_NAME}"
echo "[*] Data root:      ${DATA_ROOT}"
echo ""

# Create overlay network (idempotent)
docker network create \
  --driver overlay \
  --subnet=10.0.13.0/24 \
  --gateway=10.0.13.1 \
  "${BACKEND_NETWORK_NAME}" 2>/dev/null && echo "[+] Created network ${BACKEND_NETWORK_NAME}" \
  || echo "[~] Network ${BACKEND_NETWORK_NAME} already exists"

# Create external volumes (idempotent)
docker volume create "${STACK_NAME}_postgresdata" 2>/dev/null && echo "[+] Created volume ${STACK_NAME}_postgresdata" \
  || echo "[~] Volume ${STACK_NAME}_postgresdata already exists"

docker volume create "${STACK_NAME}_searxngcache" 2>/dev/null && echo "[+] Created volume ${STACK_NAME}_searxngcache" \
  || echo "[~] Volume ${STACK_NAME}_searxngcache already exists"

# Sync conf/tools to DATA_ROOT for the tools-init container
TOOLS_SRC="./conf/tools"
TOOLS_DST="${DATA_ROOT}/open-webui/tools"
if [ -d "$TOOLS_SRC" ]; then
  echo "[*] Syncing tools to ${TOOLS_DST}..."
  mkdir -p "$TOOLS_DST"
  rsync -av --delete "$TOOLS_SRC/" "$TOOLS_DST/"
  cp -f ./scripts/install-tools.sh "$TOOLS_DST/install-tools.sh"
  echo "[+] Tools synced"
fi

# Sync conf/postgres/init to DATA_ROOT for the db container
PG_INIT_SRC="./conf/postgres/init"
PG_INIT_DST="${DATA_ROOT}/open-webui/postgres/init"
if [ -d "$PG_INIT_SRC" ]; then
  echo "[*] Syncing postgres init scripts to ${PG_INIT_DST}..."
  mkdir -p "$PG_INIT_DST"
  rsync -av "$PG_INIT_SRC/" "$PG_INIT_DST/"
  echo "[+] Postgres init scripts synced"
fi

# Sync conf/mcposerver to DATA_ROOT and inject postgres password
MCP_SRC="./conf/mcposerver"
MCP_DST="${DATA_ROOT}/open-webui/mcposerver/conf"
echo "[*] Syncing mcposerver config to ${MCP_DST}..."
mkdir -p "$MCP_DST"
rsync -av "$MCP_SRC/" "$MCP_DST/"
# Always regenerate config.json from example so password rotation is always applied
cp "${MCP_DST}/config.json.example" "${MCP_DST}/config.json"
sed -i "s|postgresql://postgres:change_me@|postgresql://postgres:${POSTGRES_PASSWORD}@|g" \
  "${MCP_DST}/config.json"
echo "[+] mcposerver config synced and password injected"

# Sync conf/tika to DATA_ROOT for the tika container
TIKA_SRC="./conf/tika"
TIKA_DST="${DATA_ROOT}/open-webui/tika/conf"
if [ -d "$TIKA_SRC" ]; then
  echo "[*] Syncing tika config to ${TIKA_DST}..."
  mkdir -p "$TIKA_DST"
  rsync -av "$TIKA_SRC/" "$TIKA_DST/"
  echo "[+] Tika config synced"
fi

# Sync conf/searxng to DATA_ROOT for the searxng container
SEARXNG_SRC="./conf/searxng"
SEARXNG_DST="${DATA_ROOT}/open-webui/searxng/conf"
if [ -d "$SEARXNG_SRC" ]; then
  echo "[*] Syncing searxng config to ${SEARXNG_DST}..."
  mkdir -p "$SEARXNG_DST"
  rsync -av "$SEARXNG_SRC/" "$SEARXNG_DST/"
  echo "[+] SearXNG config synced"
fi

echo ""
echo "[*] Deploying stack ${STACK_NAME}..."
docker stack deploy -c docker-stack-compose.yml "${STACK_NAME}"

echo ""
echo "[+] Deployed. Monitor with:  docker stack ps ${STACK_NAME}"
