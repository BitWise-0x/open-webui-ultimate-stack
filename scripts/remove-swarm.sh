#!/usr/bin/env bash
#
# remove-swarm.sh — Remove the Docker Swarm stack
# Sources .env to respect STACK_NAME (same variable used by deploy-swarm.sh).
# NOTE: External volumes (postgresdata, searxngcache) are NOT removed automatically.
#
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  # shellcheck disable=SC1091
  set -o allexport; source .env; set +o allexport
else
  echo "ERROR: .env not found. Cannot determine STACK_NAME." >&2
  exit 1
fi

: "${STACK_NAME:?STACK_NAME must be set in .env}"
: "${BACKEND_NETWORK_NAME:?BACKEND_NETWORK_NAME must be set in .env}"

echo ""
echo "[*] Removing stack ${STACK_NAME}..."
docker stack rm "${STACK_NAME}"
echo "[+] Stack removed."
echo ""
echo "    External volumes and networks are NOT removed automatically."
echo "    To remove volumes (DESTROYS ALL DATA):"
echo "      docker volume rm ${STACK_NAME}_postgresdata ${STACK_NAME}_searxngcache"
echo "    To remove the overlay network:"
echo "      docker network rm ${BACKEND_NETWORK_NAME}"
