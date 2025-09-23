#!/usr/bin/env bash
set -euo pipefail

# Simple creator for a DigitalOcean Droplet with cloud-init user-data and password auth.
# Requirements:
#  - env DO_TOKEN (Personal Access Token)
#  - curl, jq
# Usage:
#  REGION=nyc3 SIZE=s-1vcpu-2gb IMAGE=ubuntu-22-04 DEPLOY_PASSWORD='P@ssw0rd!' ./create-do-droplet.sh

REGION=${REGION:-"nyc3"}
SIZE=${SIZE:-"s-1vcpu-2gb"}
IMAGE=${IMAGE:-"ubuntu-22-04-x64"}
NAME=${NAME:-"microservice-app"}
DEPLOY_PASSWORD=${DEPLOY_PASSWORD:-}
SSH_KEYS_JSON=${SSH_KEYS_JSON:-"[]"}  # optional: JSON array of SSH key IDs to attach as well

if [[ -z "${DO_TOKEN:-}" ]]; then
  echo "Missing DO_TOKEN env var" >&2
  exit 1
fi
if [[ -z "${DEPLOY_PASSWORD}" ]]; then
  echo "Missing DEPLOY_PASSWORD env var" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CLOUD_INIT_TEMPLATE="${SCRIPT_DIR}/cloud-init.yaml"
if [[ ! -f "${CLOUD_INIT_TEMPLATE}" ]]; then
  echo "cloud-init.yaml not found at ${CLOUD_INIT_TEMPLATE}" >&2
  exit 1
fi

# Inject password into cloud-init template safely
USER_DATA=$(sed "s|__DEPLOY_PASSWORD__|${DEPLOY_PASSWORD//|/\|}|g" "${CLOUD_INIT_TEMPLATE}")

echo "Creating Droplet '${NAME}' in ${REGION} (${SIZE})..."
CREATE_PAYLOAD=$(jq -n \
  --arg name "${NAME}" \
  --arg region "${REGION}" \
  --arg size "${SIZE}" \
  --arg image "${IMAGE}" \
  --arg user_data "${USER_DATA}" \
  --argjson ssh_keys "${SSH_KEYS_JSON}" \
  '{name:$name, region:$region, size:$size, image:$image, user_data:$user_data, ssh_keys:$ssh_keys, backups:false, ipv6:false, monitoring:true, tags:["microservice-app"]}')

RESP=$(curl -sS -X POST "https://api.digitalocean.com/v2/droplets" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DO_TOKEN}" \
  -d "${CREATE_PAYLOAD}")

if [[ "$(echo "$RESP" | jq -r '.droplet.id?')" == "null" ]]; then
  echo "$RESP" | jq . >&2
  echo "Droplet creation failed" >&2
  exit 1
fi

DROPLET_ID=$(echo "$RESP" | jq -r '.droplet.id')
echo "Droplet ID: ${DROPLET_ID}"

echo "Waiting for public IP..."
for i in {1..60}; do
  DESC=$(curl -sS -H "Authorization: Bearer ${DO_TOKEN}" "https://api.digitalocean.com/v2/droplets/${DROPLET_ID}")
  IP=$(echo "$DESC" | jq -r '.droplet.networks.v4[] | select(.type=="public") | .ip_address' | head -n1)
  if [[ -n "${IP}" && "${IP}" != "null" ]]; then
    echo "Public IP: ${IP}"
    break
  fi
  sleep 5
done

if [[ -z "${IP:-}" ]]; then
  echo "Could not get public IP for droplet ${DROPLET_ID}" >&2
  exit 1
fi

cat <<EOF

Droplet created successfully.

Name:      ${NAME}
Region:    ${REGION}
Size:      ${SIZE}
Image:     ${IMAGE}
DropletID: ${DROPLET_ID}
Public IP: ${IP}

Login (password-based):
  ssh deploy@${IP}
  Password: (the value you set in DEPLOY_PASSWORD)

Next steps:
  - Copy your docker-compose file(s) to /opt/microservice-app
  - Run: ssh deploy@${IP} "docker compose version" to verify

EOF

