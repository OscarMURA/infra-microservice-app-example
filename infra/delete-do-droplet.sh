#!/usr/bin/env bash
set -euo pipefail

# Delete a DigitalOcean Droplet by ID or by name.
# Requirements:
#  - env DO_TOKEN
#  - curl, jq
# Usage examples:
#  DROPLET_ID=123456 ./delete-do-droplet.sh
#  NAME=microservice-app ./delete-do-droplet.sh

if [[ -z "${DO_TOKEN:-}" ]]; then
  echo "Missing DO_TOKEN env var" >&2
  exit 1
fi

if [[ -z "${DROPLET_ID:-}" && -z "${NAME:-}" ]]; then
  echo "Provide DROPLET_ID or NAME env var" >&2
  exit 1
fi

if [[ -z "${DROPLET_ID:-}" ]]; then
  echo "Resolving ID by name: ${NAME}"
  PAGE=1
  while :; do
    RESP=$(curl -sS -H "Authorization: Bearer ${DO_TOKEN}" "https://api.digitalocean.com/v2/droplets?page=${PAGE}")
    IDS=$(echo "$RESP" | jq -r --arg NAME "$NAME" '.droplets[] | select(.name==$NAME) | .id')
    if [[ -n "$IDS" ]]; then
      DROPLET_ID=$(echo "$IDS" | head -n1)
      break
    fi
    NP=$(echo "$RESP" | jq -r '.links.pages.next?')
    if [[ -z "$NP" || "$NP" == "null" ]]; then
      echo "Droplet with name '$NAME' not found" >&2
      exit 1
    fi
    PAGE=$((PAGE+1))
  done
fi

echo "Deleting droplet ID: ${DROPLET_ID}"
HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE \
  -H "Authorization: Bearer ${DO_TOKEN}" \
  "https://api.digitalocean.com/v2/droplets/${DROPLET_ID}")

if [[ "$HTTP_CODE" == "204" ]]; then
  echo "Droplet ${DROPLET_ID} deleted successfully"
else
  echo "Failed to delete droplet ${DROPLET_ID}. HTTP $HTTP_CODE" >&2
  exit 1
fi

