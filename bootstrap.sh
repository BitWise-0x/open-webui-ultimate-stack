#!/usr/bin/env bash
#
# bootstrap.sh — stack setup and deployment
#
# Usage:
#   ./bootstrap.sh          Standalone (Docker Compose)
#   ./bootstrap.sh --swarm  Docker Swarm
#
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()    { echo -e "${BOLD}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[+]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
die()     { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }
hint()    { echo -e "    ${CYAN}→${RESET} $*"; }

cd "$(dirname "$0")"

SWARM=false
[ "${1:-}" = "--swarm" ] && SWARM=true

# --- Sanity checks ---
[ -d "env" ] || die "env/ directory not found — run bootstrap.sh from the repository root."
command -v docker >/dev/null 2>&1 || die "Docker is not installed."
if [ "$SWARM" = false ]; then
  [ -f "docker-compose.yml" ] || die "docker-compose.yml not found — run bootstrap.sh from the repository root."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required."
else
  [ -f "docker-stack-compose.yml" ] || die "docker-stack-compose.yml not found — run bootstrap.sh from the repository root."
  docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active \
    || die "Docker Swarm is not active. Run: docker swarm init"
fi

info "open-webui-ultimate-stack bootstrap$( [ "$SWARM" = true ] && echo ' (swarm)' )"
echo ""

# --- Copy env examples ---
info "Setting up environment files..."
for example in env/*.env.example; do
  target="${example%.example}"
  if [ -f "$target" ]; then
    warn "  $target already exists — skipping"
  else
    cp "$example" "$target"
    success "  Created $target"
  fi
done

if [ "$SWARM" = true ] && [ ! -f ".env" ]; then
  cp .env.example .env
  success "  Created .env"
fi

# --- Generate secrets ---
info "Generating secrets..."

generate_secret() {
  local s
  s=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
  [[ -z "$s" ]] && die "Secret generation failed — install openssl or python3"
  echo "$s"
}

# Safely set a key=value in an env file without sed metacharacter issues.
# Handles passwords containing |, &, \, $, etc.
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

inject_secret() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=change_me" "$file" 2>/dev/null; then
    safe_set_env "$file" "$key" "$value"
    success "  Generated ${key} in ${file}"
  fi
}

WEBUI_SECRET=$(generate_secret)
SEARXNG_SECRET=$(generate_secret)
DB_PASSWORD=$(openssl rand -base64 32 2>/dev/null | tr -d '/+=|\n' | head -c 24)
if [ -z "$DB_PASSWORD" ]; then
  DB_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(24)[:24])" 2>/dev/null)
fi
[ -n "$DB_PASSWORD" ] || die "DB password generation failed — install openssl or python3"

inject_secret env/owui.env    WEBUI_SECRET_KEY  "$WEBUI_SECRET"
inject_secret env/searxng.env SEARXNG_SECRET    "$SEARXNG_SECRET"

# Ensure mcposerver runtime config exists
if [ ! -f conf/mcposerver/config.json ]; then
  cp conf/mcposerver/config.json.example conf/mcposerver/config.json
fi

# Update postgres password consistently across all files
if grep -q "^POSTGRES_PASSWORD=change_me" env/db.env 2>/dev/null; then
  # Safety: if a postgres data volume already exists, a new password will mismatch the existing DB
  if docker volume inspect postgres_data >/dev/null 2>&1 || \
     docker volume inspect "${STACK_NAME:-open-webui}_postgresdata" >/dev/null 2>&1; then
    die "POSTGRES_PASSWORD is 'change_me' but a postgres data volume already exists.
    The database was initialized with a different password.
    Recover the original password and set it in env/db.env, env/owui.env, and env/mcp.env.
    Or remove the volume to start fresh: docker volume rm <volume_name>"
  fi
  safe_set_env env/db.env POSTGRES_PASSWORD "$DB_PASSWORD"
  success "  Generated POSTGRES_PASSWORD in env/db.env"

  ESCAPED_PW=$(sed_escape_val "$DB_PASSWORD")
  sed -i.bak \
    -e "s|postgresql://postgres:change_me@|postgresql://postgres:${ESCAPED_PW}@|g" \
    env/owui.env && rm -f env/owui.env.bak
  sed -i.bak \
    -e "s|postgresql://postgres:change_me@|postgresql://postgres:${ESCAPED_PW}@|g" \
    env/mcp.env && rm -f env/mcp.env.bak
  if command -v jq >/dev/null 2>&1; then
    jq --arg pw "$DB_PASSWORD" \
      '(.mcpServers[].args[]? | select(type == "string") | select(startswith("postgresql://"))) |= gsub("change_me"; $pw)' \
      conf/mcposerver/config.json > conf/mcposerver/config.json.tmp \
      && mv conf/mcposerver/config.json.tmp conf/mcposerver/config.json
  else
    sed -i.bak \
      -e "s|postgresql://postgres:change_me@|postgresql://postgres:${ESCAPED_PW}@|g" \
      conf/mcposerver/config.json && rm -f conf/mcposerver/config.json.bak
  fi
  success "  Synced POSTGRES_PASSWORD into owui.env, mcp.env, and mcposerver/config.json"
fi

# Safety net: if config.json still contains the placeholder password (e.g. user deleted
# config.json after first run, or bootstrap was interrupted), inject the real password.
if [ -f conf/mcposerver/config.json ] && grep -q 'change_me' conf/mcposerver/config.json 2>/dev/null; then
  CURRENT_PW=$(grep '^POSTGRES_PASSWORD=' env/db.env 2>/dev/null | cut -d= -f2-)
  if [ -n "$CURRENT_PW" ] && [ "$CURRENT_PW" != "change_me" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq --arg pw "$CURRENT_PW" \
        '(.mcpServers[].args[]? | select(type == "string") | select(startswith("postgresql://"))) |= gsub("change_me"; $pw)' \
        conf/mcposerver/config.json > conf/mcposerver/config.json.tmp \
        && mv conf/mcposerver/config.json.tmp conf/mcposerver/config.json
    else
      ESCAPED_CURRENT_PW=$(sed_escape_val "$CURRENT_PW")
      sed -i.bak \
        -e "s|postgresql://postgres:change_me@|postgresql://postgres:${ESCAPED_CURRENT_PW}@|g" \
        conf/mcposerver/config.json && rm -f conf/mcposerver/config.json.bak
    fi
    success "  Patched stale password in mcposerver/config.json"
  fi
fi

echo ""

# --- Validate required configuration ---
info "Validating configuration..."
ERRORS=0

check_default() {
  local file="$1" key="$2" default="$3" hint_msg="$4"
  local val
  val=$(grep "^${key}=" "$file" 2>/dev/null | cut -d= -f2-)
  if [ "$val" = "$default" ]; then
    warn "  ${key} is still set to the default value"
    hint "$hint_msg"
    ERRORS=$((ERRORS + 1))
  fi
}

check_default env/owui.env WEBUI_ADMIN_EMAIL    "admin@example.com" \
  "Set WEBUI_ADMIN_EMAIL in env/owui.env"
check_default env/owui.env WEBUI_ADMIN_PASSWORD "change_me" \
  "Set WEBUI_ADMIN_PASSWORD in env/owui.env  (uppercase, lowercase, digit, special char, 8+ chars)"

if [ "$SWARM" = true ]; then
  # Load .env for DATA_ROOT check
  # shellcheck disable=SC1091
  set -o allexport; source .env; set +o allexport

  check_default .env            DATA_ROOT         "/mnt/data" \
    "Set DATA_ROOT in .env to the shared filesystem path on your Swarm nodes"
  check_default .env            ROUTER_NAME       "openwebui" \
    "Set ROUTER_NAME in .env to your subdomain (used for CORS_ALLOW_ORIGIN and Traefik labels)"
  check_default .env            ROOT_DOMAIN       "your.domain.com" \
    "Set ROOT_DOMAIN in .env to your base domain (used for CORS_ALLOW_ORIGIN and Traefik labels)"
  check_default env/searxng.env SEARXNG_BASE_URL  "http://localhost:8888/" \
    "Set SEARXNG_BASE_URL=http://searxng:8080/ in env/searxng.env for Swarm"
  check_default env/owui.env FORWARDED_ALLOW_IPS "127.0.0.1" \
    "Set FORWARDED_ALLOW_IPS to the overlay subnet CIDR in env/owui.env (e.g. 10.0.13.0/24)"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  die "Fix the above before deploying, then re-run bootstrap.sh$( [ "$SWARM" = true ] && echo ' --swarm' )"
fi

success "  Configuration looks good"
echo ""

# --- Sync tools-init credentials from owui.env ---
# tools-init must authenticate with the same credentials as the admin account.
# Sync whenever the values differ (not just on first run with defaults).
if [ -f env/tools-init.env ] && [ -f env/owui.env ]; then
  OWUI_EMAIL=$(grep '^WEBUI_ADMIN_EMAIL=' env/owui.env 2>/dev/null | cut -d= -f2-)
  OWUI_PASS=$(grep '^WEBUI_ADMIN_PASSWORD=' env/owui.env 2>/dev/null | cut -d= -f2-)
  TOOLS_EMAIL=$(grep '^OWUI_ADMIN_EMAIL=' env/tools-init.env 2>/dev/null | cut -d= -f2-)
  TOOLS_PASS=$(grep '^OWUI_ADMIN_PASSWORD=' env/tools-init.env 2>/dev/null | cut -d= -f2-)
  if [ -n "$OWUI_EMAIL" ] && [ "$OWUI_EMAIL" != "$TOOLS_EMAIL" ]; then
    safe_set_env env/tools-init.env OWUI_ADMIN_EMAIL "$OWUI_EMAIL"
    success "  Synced OWUI_ADMIN_EMAIL into env/tools-init.env"
  fi
  if [ -n "$OWUI_PASS" ] && [ "$OWUI_PASS" != "$TOOLS_PASS" ]; then
    safe_set_env env/tools-init.env OWUI_ADMIN_PASSWORD "$OWUI_PASS"
    success "  Synced OWUI_ADMIN_PASSWORD into env/tools-init.env"
  fi
fi
echo ""

# --- Deploy ---
if [ "$SWARM" = false ]; then
  info "Starting the stack..."
  docker compose up -d
  echo ""
  success "Stack is up!"
  echo ""
  echo -e "  ${BOLD}Open WebUI${RESET}  →  http://localhost:3000"
  echo ""
  echo "  First run: Open WebUI will create your admin account automatically."
  echo "  tools-init will authenticate and install tools without any manual steps."
  echo "  To force a reinstall:  docker compose restart tools-init"
  echo ""
  echo "  View logs:  docker compose logs -f openwebui"
  echo "  Stop:       docker compose down"
else
  info "Deploying Swarm stack..."
  bash ./scripts/deploy-swarm.sh
fi
