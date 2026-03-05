#!/bin/bash
#
# Install tools/filters/functions into Open WebUI via internal REST API
# Runs as a sidecar init container on the Docker overlay network,
# hitting Open WebUI directly at http://openwebui:8080 (bypasses Traefik OAuth)
#
set -euo pipefail

API_URL="${OWUI_API_URL:-http://openwebui:8080}"
API_KEY="${OWUI_API_KEY:?OWUI_API_KEY env var required}"
TOOLS_DIR="/tools"

echo "========================================"
echo " Open WebUI Tools Installer"
echo " Target: ${API_URL}"
echo "========================================"

# Phase 1: Wait for Open WebUI to be reachable (unauthenticated health check)
echo ""
echo "Waiting for Open WebUI to become reachable..."
RETRIES=0
MAX_RETRIES=60
until curl -sf "${API_URL}/health" >/dev/null 2>&1; do
  RETRIES=$((RETRIES + 1))
  if [ "$RETRIES" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: Open WebUI did not become reachable after ${MAX_RETRIES} attempts. Exiting."
    exit 1
  fi
  echo "  Attempt ${RETRIES}/${MAX_RETRIES} - waiting 5s..."
  sleep 5
done
echo "Open WebUI is reachable."
echo ""

# Phase 2: Verify API key is valid before attempting installs
echo "Verifying API key..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${API_KEY}" "${API_URL}/api/v1/tools/")
if [ "$HTTP_STATUS" = "401" ]; then
  echo "ERROR: API key rejected (401 Unauthorized)."
  echo "  Generate a key in Open WebUI: Settings > Account > API Keys"
  echo "  Then set OWUI_API_KEY in env/tools-init.env and redeploy."
  exit 1
elif [ "$HTTP_STATUS" != "200" ]; then
  echo "ERROR: Unexpected response ${HTTP_STATUS} from Open WebUI API. Exiting."
  exit 1
fi
echo "API key valid."
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

  local response http_code body
  response=$(echo "$payload" | curl -s -w "\n%{http_code}" -X POST "${API_URL}/api/v1/${endpoint}/create" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d @- 2>&1)

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    echo "OK (${http_code})"
    return 0
  elif echo "$body" | jq . >/dev/null 2>&1 && echo "$body" | jq -r '.detail // empty' 2>/dev/null | grep -qi "already\|registered"; then
    echo "EXISTS — updating..."
    local update_response update_code
    update_response=$(echo "$payload" | curl -s -w "\n%{http_code}" -X POST "${API_URL}/api/v1/${endpoint}/id/${id}/update" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d @- 2>&1)
    update_code=$(echo "$update_response" | tail -1)
    if [[ "$update_code" =~ ^2[0-9]{2}$ ]]; then
      echo "  UPDATED (${update_code})"
      return 0
    else
      echo "  UPDATE FAILED (${update_code})"
      local update_body
      update_body=$(echo "$update_response" | sed '$d')
      if echo "$update_body" | jq . >/dev/null 2>&1; then
        echo "$update_body" | jq -r '.detail // .' 2>/dev/null || true
      else
        echo "$update_body"
      fi
      return 1
    fi
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
