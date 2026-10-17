#!/bin/sh
# =============================================================================
# wait-for-services.sh — TCP dependency gate for Docker Swarm services
# =============================================================================
#
# Docker Swarm does not support depends_on. All services start simultaneously,
# which means a service may attempt to connect to a dependency (e.g., postgres,
# redis) before DNS resolves or the port is listening. This script blocks
# startup until all specified host:port pairs are reachable via TCP, then
# exec's into the real entrypoint/command.
#
# Usage (in docker-compose entrypoint):
#   entrypoint: ["/bin/sh", "/wait-for-services.sh", "db:5432", "redis:6379", "--"]
#   command:    ["bash", "start.sh"]
#
#   The "--" separator is required. Everything before it is a wait target,
#   everything after it (merged with command:) is the process to exec into.
#
# Environment variables:
#   WAIT_TIMEOUT   Max seconds to wait per target (default: 120)
#   WAIT_INTERVAL  Seconds between retry attempts (default: 2)
#
# TCP check methods (auto-detected in order of preference):
#   1. python3/python (socket connect, available in searxng/mcpo/tools-init)
#   2. nc -z          (only if this nc supports -z)
#
# Notes:
#   - Targets are checked sequentially, not in parallel
#   - The script is POSIX-compatible (works with sh, ash, dash, bash)
#   - Mount as read-only volume from shared storage:
#       ${DATA_ROOT}/open-webui/scripts/wait-for-services.sh:/wait-for-services.sh:ro
# =============================================================================

set -e

TIMEOUT="${WAIT_TIMEOUT:-120}"
INTERVAL="${WAIT_INTERVAL:-2}"

# Parse targets (everything before --)
TARGETS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    *)  TARGETS="$TARGETS $1"; shift ;;
  esac
done

# Guard: must have a command to exec into after --
if [ "$#" -eq 0 ]; then
  echo "[wait] ERROR: No command specified after '--'. Nothing to exec into." >&2
  exit 1
fi

if [ -z "$TARGETS" ]; then
  echo "[wait] No targets specified, starting immediately."
  exec "$@"
fi

# Detect available TCP check method (python first: some images ship a BusyBox nc without -z)
if command -v python3 >/dev/null 2>&1; then
  check_port() { python3 -c "import socket,sys; socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=1).close()" "$1" "$2" 2>/dev/null; }
elif command -v python >/dev/null 2>&1; then
  check_port() { python -c "import socket,sys; socket.create_connection((sys.argv[1],int(sys.argv[2])),timeout=1).close()" "$1" "$2" 2>/dev/null; }
elif command -v nc >/dev/null 2>&1 && ! nc -z 127.0.0.1 1 2>&1 | grep -qiE "invalid option|unrecognized option|usage"; then
  check_port() { nc -z "$1" "$2" 2>/dev/null; }
else
  echo "[wait] WARNING: No TCP check tool found (nc, python3, python). Skipping wait." >&2
  exec "$@"
fi

echo "[wait] Waiting for: $TARGETS (timeout: ${TIMEOUT}s)"

for TARGET in $TARGETS; do
  HOST="${TARGET%%:*}"
  PORT="${TARGET##*:}"
  ELAPSED=0

  while ! check_port "$HOST" "$PORT"; do
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
      echo "[wait] ERROR: $TARGET not reachable after ${TIMEOUT}s — aborting." >&2
      exit 1
    fi
    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  echo "[wait] $TARGET is available (after ${ELAPSED}s)."
done

echo "[wait] All dependencies ready. Starting: $*"
exec "$@"
