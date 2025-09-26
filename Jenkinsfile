pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  environment {
    NAME  = "microservice-app"
    REGION = "nyc3"
    SIZE   = "s-1vcpu-2gb"
    IMAGE  = "ubuntu-22-04-x64"
    APP_REPO_URL = "https://github.com/Gab27x/microservice-app-example.git"
    APP_BRANCH   = "develop"
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

    stage("Deploy App (compose)"){
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
          sh '''
            set -e
            IP=$(awk -F= '/DROPLET_IP/ {print $2}' droplet.properties)
            [ -n "$IP" ] || { echo "No DROPLET_IP"; exit 1; }

            echo "Clonando app ${APP_BRANCH} desde ${APP_REPO_URL}..."
            rm -rf app-src
            git clone --depth 1 -b "$APP_BRANCH" "$APP_REPO_URL" app-src

            export SSHPASS="$DEPLOY_PASSWORD"
            sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null deploy@"$IP" 'mkdir -p /opt/microservice-app'

            echo "Sincronizando fuentes a la VM..."
            tar -C app-src -czf - . | sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null deploy@"$IP" 'tar -xzf - -C /opt/microservice-app'

            echo "Levantando docker compose en la VM..."
            sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null deploy@"$IP" '
              set -e
              cd /opt/microservice-app
              docker compose up -d --build
              # Abrir puertos comunes por si UFW está activo
              sudo ufw allow 3000/tcp || true
              sudo ufw allow 80/tcp || true
            '

            echo "Smokes HTTP con reintentos..."
            wait_on() {
              url="$1"; name="$2"; attempts=30; sleep_secs=3
              for i in $(seq 1 "$attempts"); do
                if curl -fsS -o /dev/null "$url"; then
                  echo "[OK] $name disponible en $url"
                  return 0
                fi
                echo "[wait] $name no disponible aún ($i/$attempts): $url"; sleep "$sleep_secs"
              done
              echo "[FAIL] Timeout esperando $name en $url"; return 1
            }

            # Descubrir puerto del frontend: probar 3000 y fallback a 80
            FRONT_OK=no
            if wait_on "http://$IP:3000" "frontend"; then FRONT_OK=yes; fi
            if [ "$FRONT_OK" = "no" ]; then
              wait_on "http://$IP:80" "frontend" || FRONT_OK=no
            fi
            wait_on "http://$IP:9411" "zipkin"

            echo "Estado de contenedores en la VM:"
            sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null deploy@"$IP" 'cd /opt/microservice-app && docker compose ps'
          '''
        }
      }
    }
  }
}