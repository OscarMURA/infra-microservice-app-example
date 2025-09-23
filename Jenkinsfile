pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  environment {
    NAME  = "microservice-app"
    REGION = "nyc3"
    SIZE   = "s-1vcpu-2gb"
    IMAGE  = "ubuntu-22-04-x64"
  }
  stages {
    stage("Checkout"){ steps { checkout scm } }
    stage("Detect flags"){
      steps { script { env.MSG = sh(script: "git log -1 --pretty=%B", returnStdout: true).trim() } }
    }
    stage("Ensure/Apply"){
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        withCredentials([
          string(credentialsId: "do-token", variable: "DO_TOKEN"),
          string(credentialsId: "deploy-password", variable: "DEPLOY_PASSWORD")
        ]) {
          sh '''
            set -e
            chmod +x ./infra/*.sh || true
            get_ip() {
              curl -sS -H "Authorization: Bearer $DO_TOKEN" "https://api.digitalocean.com/v2/droplets?per_page=200" \
                | jq -r --arg NAME "$NAME" '.droplets[] | select(.name==$NAME) | .networks.v4[] | select(.type=="public") | .ip_address' | head -n1
            }
            REBUILD_FLAG="$(echo "${MSG:-}" | grep -qiF '[rebuild]' && echo yes || echo no)"
            IP="$(get_ip)"
            if [ "$REBUILD_FLAG" = "yes" ]; then
              echo "[rebuild] detectado: destruyendo $NAME..."
              DO_TOKEN="$DO_TOKEN" NAME="$NAME" bash ./infra/delete-do-droplet.sh || true
              sleep 5
              IP=""
            fi
            if [ -z "$IP" ]; then
              echo "Creando $NAME..."
              REGION="$REGION" SIZE="$SIZE" IMAGE="$IMAGE" NAME="$NAME" DO_TOKEN="$DO_TOKEN" DEPLOY_PASSWORD="$DEPLOY_PASSWORD" \
                bash ./infra/create-do-droplet.sh
              sleep 10
              IP="$(get_ip)"
            else
              echo "Droplet existente: $IP"
            fi
            echo "DROPLET_IP=$IP" > droplet.properties
          '''
          archiveArtifacts artifacts: "droplet.properties", fingerprint: true
        }
      }
    }

    stage("Smoke Docker en VM"){
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
          sh '''
            set -e
            IP=$(awk -F= '/DROPLET_IP/ {print $2}' droplet.properties)
            [ -n "$IP" ] || { echo "No DROPLET_IP"; exit 1; }
            export SSHPASS="$DEPLOY_PASSWORD"
            sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null deploy@"$IP" '
              docker --version &&
              docker compose version &&
              id -nG deploy | grep -q docker &&
              test -d /opt/microservice-app || exit 1
            '
          '''
        }
      }
    }
  }
}