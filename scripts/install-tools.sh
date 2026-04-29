#!/bin/bash
#
# Install tools/filters/functions into Open WebUI via internal REST API
# Runs as a sidecar init container on the Docker overlay network,
# hitting Open WebUI directly at http://openwebui:8080 (bypasses Traefik OAuth)
#
set -euo pipefail

API_URL="${OWUI_API_URL:-http://openwebui:8080}"
ADMIN_EMAIL="${OWUI_ADMIN_EMAIL:?OWUI_ADMIN_EMAIL env var required}"
ADMIN_PASSWORD="${OWUI_ADMIN_PASSWORD:?OWUI_ADMIN_PASSWORD env var required}"
TOKEN=""
TOOLS_DIR="/tools"

echo "========================================"
echo " Open WebUI Tools Installer"
echo " Target: ${API_URL}"
echo "========================================"

# Phase 1: Wait for Open WebUI to be reachable (unauthenticated health check)
echo ""
echo "Waiting for Open WebUI to become ready..."
RETRIES=0
MAX_RETRIES=60
until curl -sf --max-time 10 "${API_URL}/health/db" >/dev/null 2>&1; do
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: Open WebUI did not become ready after ${MAX_RETRIES} attempts. Exiting."
    exit 1
  fi
  echo "  Attempt ${RETRIES}/${MAX_RETRIES} - waiting 5s..."
  sleep 5
done
echo "Open WebUI is ready."
echo ""

# Phase 2: Sign in to obtain a fresh bearer token
echo "Authenticating as ${ADMIN_EMAIL}..."
SIGNIN_BODY=$(curl -s --max-time 30 -X POST "${API_URL}/api/v1/auths/signin" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg e "$ADMIN_EMAIL" --arg p "$ADMIN_PASSWORD" '{email:$e,password:$p}')")

TOKEN=$(echo "$SIGNIN_BODY" | jq -r '.token // empty' 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "ERROR: Sign-in failed. Response:"
  echo "$SIGNIN_BODY" | jq . 2>/dev/null || echo "$SIGNIN_BODY"
  exit 1
fi
echo "Authenticated. Token obtained."
echo ""

# Extract title from Python docstring frontmatter
extract_field() {
  local file="$1" field="$2"
  python3 -c "
import re, sys
with open(sys.argv[1]) as f:
    text = f.read()
m = re.search(r'\"\"\".*?' + sys.argv[2] + r':\s*(.+?)$', text, re.DOTALL | re.MULTILINE)
if m:
    print(m.group(1).strip())
else:
    print('')
" "$file" "$field"
}

install_item() {
  local file="$1"
  local endpoint="$2"  # "tools" or "functions"
  local id
  id=$(basename "$file" .py | tr '-' '_')
  local name
  name=$(extract_field "$file" "title")
  [ -z "$name" ] && name=$(basename "$file" .py | tr '_' ' ')
  local desc
  desc=$(extract_field "$file" "description")
  echo -n "  [${endpoint}] ${name} (${id})... "

  local payload
  payload=$(jq -n \
    --arg id "$id" \
    --arg name "$name" \
    --arg desc "$desc" \
    --rawfile content "$file" \
    '{id: $id, name: $name, content: $content, meta: {description: $desc}}')

  # Probe existing item: if content+name+description match what's on disk,
  # skip the write entirely. This avoids triggering Open WebUI's module
  # reload + frontmatter pip-install on every redeploy — which blocks the
  # live workers and causes intermittent 5xx during deploys.
  local existing_code existing_body
  existing_body=$(curl -s --max-time 30 -w "\n%{http_code}" -X GET "${API_URL}/api/v1/${endpoint}/id/${id}" \
    -H "Authorization: Bearer ${TOKEN}" 2>&1)
  existing_code=$(echo "$existing_body" | tail -1)
  existing_body=$(echo "$existing_body" | sed '$d')

  if [[ "$existing_code" =~ ^2[0-9]{2}$ ]] && echo "$existing_body" | jq . >/dev/null 2>&1; then
    local rc
    rc=$(jq -n \
      --argjson cur "$existing_body" \
      --argjson new "$payload" \
      '($cur.content == $new.content)
        and ($cur.name == $new.name)
        and (($cur.meta.description // "") == ($new.meta.description // ""))' 2>/dev/null || echo false)
    if [ "$rc" = "true" ]; then
      echo "UNCHANGED — skipping"
      return 0
    fi
  fi

  local response http_code body
  if [[ "$existing_code" =~ ^2[0-9]{2}$ ]]; then
    # Exists and content differs — update directly (skip create→409→update dance).
    response=$(echo "$payload" | curl -s --max-time 30 -w "\n%{http_code}" -X POST "${API_URL}/api/v1/${endpoint}/id/${id}/update" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d @- 2>&1)
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
      echo "UPDATED (${http_code})"
      return 0
    fi
    echo "UPDATE FAILED (${http_code})"
    if echo "$body" | jq . >/dev/null 2>&1; then
      echo "$body" | jq -r '.detail // .' 2>/dev/null || true
    else
      echo "$body"
    fi
    return 1
  fi

  # Doesn't exist (404 or otherwise) — create.
  response=$(echo "$payload" | curl -s --max-time 30 -w "\n%{http_code}" -X POST "${API_URL}/api/v1/${endpoint}/create" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d @- 2>&1)

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    echo "CREATED (${http_code})"
    return 0
  elif echo "$body" | jq . >/dev/null 2>&1 && echo "$body" | jq -r '.detail // empty' 2>/dev/null | grep -qi "already\|registered"; then
    # Race: GET said missing but create says exists. Fall back to update.
    echo "EXISTS (race) — updating..."
    local update_response update_code
    update_response=$(echo "$payload" | curl -s --max-time 30 -w "\n%{http_code}" -X POST "${API_URL}/api/v1/${endpoint}/id/${id}/update" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d @- 2>&1)
    update_code=$(echo "$update_response" | tail -1)
    if [[ "$update_code" =~ ^2[0-9]{2}$ ]]; then
      echo "  UPDATED (${update_code})"
      return 0
    fi
    echo "  UPDATE FAILED (${update_code})"
    local update_body
    update_body=$(echo "$update_response" | sed '$d')
    if echo "$update_body" | jq . >/dev/null 2>&1; then
      echo "$update_body" | jq -r '.detail // .' 2>/dev/null || true
    else
      echo "$update_body"
    fi
    return 1
  else
    echo "FAILED (${http_code})"
    if echo "$body" | jq . >/dev/null 2>&1; then
      echo "$body" | jq -r '.detail // .' 2>/dev/null
    else
      echo "$body"
    fi
    return 1
  fi
}

FAIL_COUNT=0
PASS_COUNT=0

# --- Filters (installed as functions) ---
echo "--- Filters ---"
if [ -d "${TOOLS_DIR}/filters" ]; then
  for f in "${TOOLS_DIR}/filters/"*.py; do
    [ -f "$f" ] || continue
    if install_item "$f" "functions"; then
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done
fi

echo ""

# --- Tools ---
echo "--- Tools ---"
if [ -d "${TOOLS_DIR}/tools" ]; then
  for t in "${TOOLS_DIR}/tools/"*.py; do
    [ -f "$t" ] || continue
    if install_item "$t" "tools"; then
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done
fi

echo ""

# --- Functions / Pipes ---
echo "--- Functions / Pipes ---"
if [ -d "${TOOLS_DIR}/functions" ]; then
  for f in "${TOOLS_DIR}/functions/"*.py; do
    [ -f "$f" ] || continue
    if install_item "$f" "functions"; then
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done
fi

echo ""
echo "========================================"
echo " Done: ${PASS_COUNT} succeeded, ${FAIL_COUNT} failed"
echo "========================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
