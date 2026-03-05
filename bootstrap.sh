#!/usr/bin/env bash
#
# bootstrap.sh — local / standalone stack setup
# Copies env examples, generates secrets, and starts the stack.
#
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

info()    { echo -e "${BOLD}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[+]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
die()     { echo -e "${RED}[✗]${RESET} $*" >&2; exit 1; }

# Escape special sed characters in a replacement string (/, &, \)
escape_sed() { printf '%s\n' "$1" | sed -e 's/[\/&]/\\&/g'; }

cd "$(dirname "$0")"

# --- Sanity check: must run from repo root ---
[ -d "env" ] || die "env/ directory not found — run bootstrap.sh from the repository root."
[ -f "docker-compose.yml" ] || die "docker-compose.yml not found — run bootstrap.sh from the repository root."

# --- Prerequisite checks ---
command -v docker >/dev/null 2>&1 || die "Docker is not installed. Install it from https://docs.docker.com/get-docker/"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required. Update Docker Desktop or install the plugin."

info "open-webui-ultimate-stack bootstrap"
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

# --- Generate secrets ---
info "Generating secrets..."

generate_secret() {
  local s
  s=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))")
  [[ -z "$s" ]] && die "Secret generation failed — install openssl or python3"
  echo "$s"
}

inject_secret() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=generate_with" "$file" 2>/dev/null; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file" && rm -f "${file}.bak"
    success "  Generated ${key} in ${file}"
  fi
}

WEBUI_SECRET=$(generate_secret)
SEARXNG_SECRET=$(generate_secret)
DB_PASSWORD=$(openssl rand -base64 24 2>/dev/null | tr -d '/+' | head -c 24)

inject_secret env/owui.env    WEBUI_SECRET_KEY  "$WEBUI_SECRET"
inject_secret env/searxng.env SEARXNG_SECRET    "$SEARXNG_SECRET"

# Ensure mcposerver runtime config exists (gitignored; generated from example)
if [ ! -f conf/mcposerver/config.json ]; then
  cp conf/mcposerver/config.json.example conf/mcposerver/config.json
fi

# Update postgres password consistently across all files that reference it
if grep -q "^POSTGRES_PASSWORD=change_me" env/db.env 2>/dev/null; then
  sed -i.bak "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASSWORD}|" env/db.env && rm -f env/db.env.bak
  success "  Generated POSTGRES_PASSWORD in env/db.env"

  sed -i.bak \
    -e "s|postgresql://postgres:change_me@|postgresql://postgres:${DB_PASSWORD}@|g" \
    env/owui.env && rm -f env/owui.env.bak
  sed -i.bak \
    -e "s|postgresql://postgres:change_me@|postgresql://postgres:${DB_PASSWORD}@|g" \
    env/mcp.env && rm -f env/mcp.env.bak
  if command -v jq >/dev/null 2>&1; then
    jq --arg pw "$DB_PASSWORD" \
      '(.mcpServers[].args[]? | select(type == "string") | select(startswith("postgresql://"))) |= gsub("change_me"; $pw)' \
      conf/mcposerver/config.json > conf/mcposerver/config.json.tmp \
      && mv conf/mcposerver/config.json.tmp conf/mcposerver/config.json
  else
    sed -i.bak \
      -e "s|postgresql://postgres:change_me@|postgresql://postgres:${DB_PASSWORD}@|g" \
      conf/mcposerver/config.json && rm -f conf/mcposerver/config.json.bak
  fi
  success "  Synced POSTGRES_PASSWORD into owui.env, mcp.env, and mcposerver/config.json"
fi

echo ""

# --- Ollama ---
info "Ollama configuration"
echo "  Enter your Ollama base URL, or press Enter to skip (API-only mode)."
echo -n "  OLLAMA_BASE_URL [skip]: "
read -r OLLAMA_URL
if [ -n "$OLLAMA_URL" ] && [ "$OLLAMA_URL" != "skip" ]; then
  ESCAPED_URL=$(escape_sed "$OLLAMA_URL")
  sed -i.bak "s|^OLLAMA_BASE_URL=.*|OLLAMA_BASE_URL=${ESCAPED_URL}|" env/owui.env && rm -f env/owui.env.bak
  sed -i.bak "s|^RAG_OLLAMA_BASE_URL=.*|RAG_OLLAMA_BASE_URL=${ESCAPED_URL}|" env/owui.env && rm -f env/owui.env.bak
  success "  Set OLLAMA_BASE_URL=${OLLAMA_URL}"
else
  sed -i.bak "s|^ENABLE_OLLAMA_API=true|ENABLE_OLLAMA_API=false|" env/owui.env && rm -f env/owui.env.bak
  warn "  Ollama disabled. You can re-enable it later by editing env/owui.env"
fi

echo ""

# --- OpenAI API key (optional) ---
info "OpenAI API key (optional)"
echo "  Enter your OpenAI API key, or press Enter to skip."
echo -n "  OPENAI_API_KEY [skip]: "
read -r -s OAI_KEY
echo ""
if [ -n "$OAI_KEY" ] && [ "$OAI_KEY" != "skip" ]; then
  ESCAPED_KEY=$(escape_sed "$OAI_KEY")
  sed -i.bak "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${ESCAPED_KEY}|" env/owui.env && rm -f env/owui.env.bak
  success "  Set OPENAI_API_KEY"
else
  sed -i.bak "s|^ENABLE_OPENAI_API=true|ENABLE_OPENAI_API=false|" env/owui.env && rm -f env/owui.env.bak
  warn "  OpenAI disabled. You can re-enable it later by editing env/owui.env"
fi

echo ""

# --- Start the stack ---
info "Starting the stack..."
docker compose up -d

echo ""
success "Stack is up!"
echo ""
echo -e "  ${BOLD}Open WebUI${RESET}  →  http://localhost:3000"
echo -e "  ${BOLD}SearXNG${RESET}     →  http://localhost:8888"
echo ""
echo "  First run: create your admin account at http://localhost:3000"
echo "  After creating an account, generate an API key and add it to env/tools-init.env"
echo "  then run:  docker compose restart tools-init"
echo ""
echo "  View logs:  docker compose logs -f openwebui"
echo "  Stop:       docker compose down"
