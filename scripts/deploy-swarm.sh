#!/usr/bin/env bash
#
# deploy-swarm.sh — Docker Swarm deployment helper
# Creates the overlay backend network and deploys the stack.
# Run from the repo root on a Swarm manager node.
#
set -euo pipefail

cd "$(dirname "$0")/.."

# Safely set a key=value in an env file without sed metacharacter issues.
safe_set_env() {
  local file="$1" key="$2" value="$3"
  _SSE_KEY="$key" _SSE_VAL="$value" awk '
    BEGIN { k=ENVIRON["_SSE_KEY"]; v=ENVIRON["_SSE_VAL"] }
    index($0, k"=") == 1 { print k "=" v; next }
    { print }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Escape a value for safe use in sed replacement (with | delimiter).
sed_escape_val() { printf '%s\n' "$1" | sed 's/[&/\|]/\\&/g'; }

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
: "${BACKEND_NETWORK_NAME:?BACKEND_NETWORK_NAME must be set in .env}"
: "${DATA_ROOT:?DATA_ROOT must be set in .env}"

# Load postgres password from db.env — generate if still set to change_me
if [ -z "${POSTGRES_PASSWORD:-}" ] && [ -f env/db.env ]; then
  POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' env/db.env | cut -d= -f2-)
fi
if [ "${POSTGRES_PASSWORD:-}" = "change_me" ]; then
  # Safety: if a postgres data volume already exists, a new password will mismatch the existing DB
  if docker volume inspect "${STACK_NAME}_postgresdata" >/dev/null 2>&1; then
    echo "ERROR: POSTGRES_PASSWORD is 'change_me' but volume ${STACK_NAME}_postgresdata already exists." >&2
    echo "       The database was initialized with a different password." >&2
    echo "       Recover the original password and set it in env/db.env, env/owui.env, and env/mcp.env." >&2
    echo "       Or remove the volume to start fresh: docker volume rm ${STACK_NAME}_postgresdata" >&2
    exit 1
  fi
  POSTGRES_PASSWORD=$(openssl rand -base64 32 2>/dev/null | tr -d '/+=|\n' | head -c 24)
  if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(24)[:24])" 2>/dev/null)
  fi
  [ -n "$POSTGRES_PASSWORD" ] || { echo "ERROR: Password generation failed — install openssl or python3" >&2; exit 1; }
  safe_set_env env/db.env POSTGRES_PASSWORD "$POSTGRES_PASSWORD"
  ESCAPED_PW=$(sed_escape_val "$POSTGRES_PASSWORD")
  sed -i.bak "s|postgresql://postgres:change_me@|postgresql://postgres:${ESCAPED_PW}@|g" env/owui.env && rm -f env/owui.env.bak
  sed -i.bak "s|postgresql://postgres:change_me@|postgresql://postgres:${ESCAPED_PW}@|g" env/mcp.env && rm -f env/mcp.env.bak
  echo "[+] Generated POSTGRES_PASSWORD and synced to env/db.env, env/owui.env, env/mcp.env"
fi
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD not found. Set it in env/db.env}"

# Load searxng secret from searxng.env — generate if still set to change_me
if [ -z "${SEARXNG_SECRET:-}" ] && [ -f env/searxng.env ]; then
  SEARXNG_SECRET=$(grep '^SEARXNG_SECRET=' env/searxng.env | cut -d= -f2-)
fi
if [ "${SEARXNG_SECRET:-}" = "change_me" ]; then
  SEARXNG_SECRET=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
  [ -n "$SEARXNG_SECRET" ] || { echo "ERROR: SEARXNG_SECRET generation failed — install openssl or python3" >&2; exit 1; }
  safe_set_env env/searxng.env SEARXNG_SECRET "$SEARXNG_SECRET"
  echo "[+] Generated SEARXNG_SECRET in env/searxng.env"
fi

# Generate WEBUI_SECRET_KEY if still set to change_me (safety net for direct invocation)
WEBUI_SECRET=$(grep '^WEBUI_SECRET_KEY=' env/owui.env 2>/dev/null | cut -d= -f2-)
if [ "${WEBUI_SECRET:-}" = "change_me" ]; then
  WEBUI_SECRET=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
  [ -n "$WEBUI_SECRET" ] || { echo "ERROR: WEBUI_SECRET_KEY generation failed — install openssl or python3" >&2; exit 1; }
  safe_set_env env/owui.env WEBUI_SECRET_KEY "$WEBUI_SECRET"
  echo "[+] Generated WEBUI_SECRET_KEY in env/owui.env"
fi

# Sync tools-init credentials from owui.env whenever they differ
if [ -f env/tools-init.env ] && [ -f env/owui.env ]; then
  OWUI_EMAIL=$(grep '^WEBUI_ADMIN_EMAIL=' env/owui.env 2>/dev/null | cut -d= -f2-)
  OWUI_PASS=$(grep '^WEBUI_ADMIN_PASSWORD=' env/owui.env 2>/dev/null | cut -d= -f2-)
  TOOLS_EMAIL=$(grep '^OWUI_ADMIN_EMAIL=' env/tools-init.env 2>/dev/null | cut -d= -f2-)
  TOOLS_PASS=$(grep '^OWUI_ADMIN_PASSWORD=' env/tools-init.env 2>/dev/null | cut -d= -f2-)
  if [ -n "$OWUI_EMAIL" ] && [ "$OWUI_EMAIL" != "$TOOLS_EMAIL" ]; then
    safe_set_env env/tools-init.env OWUI_ADMIN_EMAIL "$OWUI_EMAIL"
    echo "[+] Synced OWUI_ADMIN_EMAIL into env/tools-init.env"
  fi
  if [ -n "$OWUI_PASS" ] && [ "$OWUI_PASS" != "$TOOLS_PASS" ]; then
    safe_set_env env/tools-init.env OWUI_ADMIN_PASSWORD "$OWUI_PASS"
    echo "[+] Synced OWUI_ADMIN_PASSWORD into env/tools-init.env"
  fi
fi

# Validate DATA_ROOT is reachable (must be mounted before deploy)
[ -d "${DATA_ROOT}" ] || { echo "ERROR: DATA_ROOT '${DATA_ROOT}' does not exist or is not mounted" >&2; exit 1; }

# Validate REDIS_DATA_ROOT if set (separate mount for redis directio performance)
if [ -n "${REDIS_DATA_ROOT:-}" ] && [ "${REDIS_DATA_ROOT}" != "${DATA_ROOT}" ]; then
  [ -d "${REDIS_DATA_ROOT}" ] || { echo "ERROR: REDIS_DATA_ROOT '${REDIS_DATA_ROOT}' does not exist or is not mounted" >&2; exit 1; }
fi

# Warn if SEARXNG_BASE_URL still points to standalone default
SEARXNG_BASE_URL_VAL=$(grep '^SEARXNG_BASE_URL=' env/searxng.env 2>/dev/null | cut -d= -f2-)
if [ "${SEARXNG_BASE_URL_VAL}" = "http://localhost:8888/" ]; then
  echo "ERROR: SEARXNG_BASE_URL is still set to the standalone default (http://localhost:8888/)" >&2
  echo "       Set SEARXNG_BASE_URL=http://searxng:8080/ (or /searxng for Traefik subpath) in env/searxng.env" >&2
  exit 1
fi

# Warn if FORWARDED_ALLOW_IPS is still set to standalone default
FWIP=$(grep '^FORWARDED_ALLOW_IPS=' env/owui.env 2>/dev/null | cut -d= -f2- | tr -d "'\"")
if [ "${FWIP}" = "127.0.0.1" ]; then
  echo "[!] WARNING: FORWARDED_ALLOW_IPS is set to 127.0.0.1 (standalone default)"
  echo "    For Swarm/Traefik, set FORWARDED_ALLOW_IPS=10.0.13.0/24 in env/owui.env"
  echo "    (must match the overlay subnet created by this script)"
fi

echo "[*] Stack:          ${STACK_NAME}"
echo "[*] Backend net:    ${BACKEND_NETWORK_NAME}"
echo "[*] Data root:      ${DATA_ROOT}"
[ -n "${ROUTER_NAME:-}" ] && [ -n "${ROOT_DOMAIN:-}" ] && echo "[*] Domain:         ${ROUTER_NAME}.${ROOT_DOMAIN}"
echo ""

# Create overlay network (idempotent)
if docker network inspect "${BACKEND_NETWORK_NAME}" >/dev/null 2>&1; then
  echo "[~] Network ${BACKEND_NETWORK_NAME} already exists"
else
  docker network create \
    --driver overlay \
    --subnet=10.0.13.0/24 \
    --gateway=10.0.13.1 \
    "${BACKEND_NETWORK_NAME}" \
    || { echo "ERROR: Failed to create network ${BACKEND_NETWORK_NAME} — check for subnet conflicts (10.0.13.0/24)" >&2; exit 1; }
  echo "[+] Created network ${BACKEND_NETWORK_NAME}"
fi

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
  echo "[!] Note: --delete is active — files in ${TOOLS_DST} not present in ${TOOLS_SRC} will be removed"
  mkdir -p "$TOOLS_DST"
  rsync -av --delete --exclude='__pycache__' "$TOOLS_SRC/" "$TOOLS_DST/"
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
  chmod +x "${PG_INIT_DST}"/*.sh 2>/dev/null || true
  echo "[+] Postgres init scripts synced"
fi

# Sync conf/mcposerver to DATA_ROOT and inject postgres password
MCP_SRC="./conf/mcposerver"
MCP_DST="${DATA_ROOT}/open-webui/mcposerver/conf"
echo "[*] Syncing mcposerver config to ${MCP_DST}..."
mkdir -p "$MCP_DST"
rsync -av "$MCP_SRC/" "$MCP_DST/"
# Generate config.json from example on first deploy only — preserves user customisations on redeploy
if [ ! -f "${MCP_DST}/config.json" ]; then
  if [ -f "${MCP_DST}/config.json.example" ]; then
    cp "${MCP_DST}/config.json.example" "${MCP_DST}/config.json"
    echo "[+] Generated config.json from example"
  else
    echo "ERROR: Neither config.json nor config.json.example found in ${MCP_DST}" >&2; exit 1
  fi
fi
# Inject postgres password — Python handles all special characters safely, idempotent on re-deploy.
# Uses rfind('@') to locate the userinfo/host boundary, so passwords containing '@' are handled correctly.
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" python3 -c "
import json, os, sys
path = sys.argv[1]
pw = os.environ['POSTGRES_PASSWORD']
with open(path) as f:
    data = json.load(f)
def patch(obj):
    if isinstance(obj, dict): return {k: patch(v) for k, v in obj.items()}
    if isinstance(obj, list): return [patch(v) for v in obj]
    if isinstance(obj, str) and obj.startswith('postgresql://'):
        at = obj.rfind('@')
        if at != -1:
            after = obj[at+1:]
            scheme_user = obj[:at].rsplit(':', 1)[0]
            return scheme_user + ':' + pw + '@' + after
    return obj
with open(path, 'w') as f:
    json.dump(patch(data), f, indent=2)
" "${MCP_DST}/config.json"
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
