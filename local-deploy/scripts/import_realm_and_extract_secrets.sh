#!/usr/bin/env bash
# Import a Keycloak realm JSON into a running Keycloak and extract client secrets.
# Usage: ./import_realm_and_extract_secrets.sh \
#   --kc-url http://localhost:8081 \
#   --admin-user admin --admin-pass change-me \
#   --realm-json /path/to/realm.json \
#   [--env-file ../.env] [--update-env]

set -euo pipefail

KC_URL="http://localhost:8081"
ADMIN_USER=admin
ADMIN_PASS=change-me
REALM_JSON="./realm.json"
ENV_FILE="../.env"
UPDATE_ENV=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --kc-url) KC_URL="$2"; shift 2;;
    --admin-user) ADMIN_USER="$2"; shift 2;;
    --admin-pass) ADMIN_PASS="$2"; shift 2;;
    --realm-json) REALM_JSON="$2"; shift 2;;
    --env-file) ENV_FILE="$2"; shift 2;;
    --update-env) UPDATE_ENV=true; shift 1;;
    -h|--help) echo "Usage: $0 [--kc-url URL] [--admin-user USER] [--admin-pass PASS] --realm-json PATH [--env-file PATH] [--update-env]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

if [ ! -f "$REALM_JSON" ]; then
  echo "Realm JSON not found: $REALM_JSON" >&2
  exit 2
fi

echo "Requesting admin token from $KC_URL ..."
TOKEN_JSON=$(curl -s -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -d client_id=admin-cli -d grant_type=password -d username="$ADMIN_USER" -d password="$ADMIN_PASS")

ACCESS_TOKEN=$(python3 - <<PY
import sys, json
obj=json.load(sys.stdin)
print(obj.get('access_token',''))
PY
<<< "$TOKEN_JSON")

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Failed to obtain access token. Response:" >&2
  echo "$TOKEN_JSON" >&2
  exit 3
fi

echo "Importing realm JSON..."
HTTP_CODE=$(curl -s -o /tmp/realm_import_resp -w "%{http_code}" -X POST "$KC_URL/admin/realms" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" --data-binary @"$REALM_JSON")
echo "Import HTTP code: $HTTP_CODE"
if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "204" ]; then
  echo "Realm import response:"; sed -n '1,200p' /tmp/realm_import_resp
  # Continue anyway if realm exists
fi

echo "Looking up clients..."
jq_cmd='import json,sys
arr=json.load(sys.stdin)
print(arr[0]["id"] if arr else "")'

AUTH_ID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KC_URL/admin/realms/authority-portal/clients?clientId=authority-portal-client" | python3 -c "$jq_cmd")
OAUTH_ID=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KC_URL/admin/realms/authority-portal/clients?clientId=oauth2-proxy" | python3 -c "$jq_cmd")

echo "authority-portal client id: $AUTH_ID"
echo "oauth2-proxy client id: $OAUTH_ID"

if [ -n "$AUTH_ID" ]; then
  curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KC_URL/admin/realms/authority-portal/clients/$AUTH_ID/client-secret" > /tmp/auth_client_secret.json
  AUTH_SECRET=$(python3 -c 'import json,sys; print(json.load(open("/tmp/auth_client_secret.json"))["value"])')
  echo "authority client secret: $AUTH_SECRET"
fi

if [ -n "$OAUTH_ID" ]; then
  # Try client-secret endpoint; fallback to client representation secret
  curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KC_URL/admin/realms/authority-portal/clients/$OAUTH_ID/client-secret" > /tmp/oauth_client_secret.json || true
  OAUTH_SECRET=$(python3 -c 'import json,sys
try:
  d=json.load(open("/tmp/oauth_client_secret.json"))
  print(d.get("value",""))
except Exception:
  d=json.load(open("/tmp/oauth_clients.json"))
  print(d[0].get("secret",""))' 2>/dev/null || true)
  if [ -z "$OAUTH_SECRET" ]; then
    # fallback: fetch client representation and extract 'secret' field
    curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$KC_URL/admin/realms/authority-portal/clients?clientId=oauth2-proxy" > /tmp/oauth_clients.json
    OAUTH_SECRET=$(python3 -c 'import json; a=json.load(open("/tmp/oauth_clients.json")); print(a[0].get("secret",""))')
  fi
  echo "oauth2-proxy client secret: $OAUTH_SECRET"
fi

if [ "$UPDATE_ENV" = true ]; then
  echo "Updating env file: $ENV_FILE"
  cp "$ENV_FILE" "$ENV_FILE.bak"
  sed -i "s/^AP_CLIENT_SECRET=.*/AP_CLIENT_SECRET=$AUTH_SECRET/" "$ENV_FILE" || echo "AP_CLIENT_SECRET=$AUTH_SECRET" >> "$ENV_FILE"
  sed -i "s/^OAUTH2_PROXY_CLIENT_SECRET=.*/OAUTH2_PROXY_CLIENT_SECRET=$OAUTH_SECRET/" "$ENV_FILE" || echo "OAUTH2_PROXY_CLIENT_SECRET=$OAUTH_SECRET" >> "$ENV_FILE"
  echo "Wrote secrets to $ENV_FILE (backup at $ENV_FILE.bak)"
fi

echo "Done."