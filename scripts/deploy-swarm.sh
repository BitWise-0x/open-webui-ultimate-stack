#!/usr/bin/env bash
#
# deploy-swarm.sh — Docker Swarm deployment helper
# Creates the overlay backend network and deploys the stack.
# Run from the repo root on a Swarm manager node.
#
set -euo pipefail

cd "$(dirname "$0")/.."

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

echo ""
echo "[*] Deploying stack ${STACK_NAME}..."
docker stack deploy -c docker-stack-compose.yml "${STACK_NAME}"

echo ""
echo "[+] Deployed. Monitor with:  docker stack ps ${STACK_NAME}"
