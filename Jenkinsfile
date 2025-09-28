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
    // Variable para almacenar la IP del droplet
    DROPLET_IP = ""
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
              echo "Nueva VM creada con IP: $IP"
            else
              echo "Droplet existente: $IP"
            fi
            
            # Guardar IP en archivo de propiedades y como variable de entorno
            echo "DROPLET_IP=$IP" > droplet.properties
            echo "VM_IP_ADDRESS=$IP" >> droplet.properties
            
            # Establecer la IP como variable de entorno para Jenkins
            echo "Estableciendo DROPLET_IP=$IP como variable de entorno"
          '''
          archiveArtifacts artifacts: "droplet.properties", fingerprint: true
          
          // Establecer la IP como variable de entorno para el resto del pipeline
          script {
            // Leer la IP desde el archivo usando shell en lugar de readProperties
            def ipValue = sh(script: "awk -F= '/DROPLET_IP/ {print \$2}' droplet.properties", returnStdout: true).trim()
            env.DROPLET_IP = ipValue
            env.VM_IP_ADDRESS = ipValue
            
            echo "✅ IP establecida como variable de entorno:"
            echo "   DROPLET_IP = ${env.DROPLET_IP}"
            echo "   VM_IP_ADDRESS = ${env.VM_IP_ADDRESS}"
            
            // Guardar en archivo de propiedades global de Jenkins para reutilización
            writeFile file: 'jenkins-env.properties', text: """DROPLET_IP=${env.DROPLET_IP}
VM_IP_ADDRESS=${env.DROPLET_IP}
LAST_DEPLOYMENT_TIME=${new Date().format('yyyy-MM-dd HH:mm:ss')}
BUILD_NUMBER=${env.BUILD_NUMBER}
JOB_NAME=${env.JOB_NAME}
ACTION=${env.MSG?.contains('[rebuild]') ? 'REBUILD' : 'DEPLOY'}
BRANCH=${env.BRANCH_NAME}
"""
            archiveArtifacts artifacts: "jenkins-env.properties", fingerprint: true
          }
        }
      }
    }

    stage("Environment Info"){
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        script {
          echo "📋 Variables de entorno disponibles:"
          echo "   Job: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
          echo "   Droplet IP: ${env.DROPLET_IP}"
          echo "   VM Address: ${env.VM_IP_ADDRESS}"
          echo "   Branch: ${env.BRANCH_NAME}"
          echo "   Action: ${env.MSG?.contains('[rebuild]') ? 'REBUILD' : 'DEPLOY'}"
        }
      }
    }

    stage("Smoke Docker en VM"){
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        script {
          echo "🐳 Verificando Docker en VM: ${env.DROPLET_IP}"
        }
        withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
          sh '''
            set -e
            # Usar la variable de entorno en lugar de leer archivo
            IP="${DROPLET_IP}"
            [ -n "$IP" ] || { echo "❌ No DROPLET_IP en variables de entorno"; exit 1; }
            echo "🔍 Verificando Docker en $IP..."
            
            export SSHPASS="$DEPLOY_PASSWORD"
            sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null deploy@"$IP" '
              docker --version &&
              docker compose version &&
              id -nG deploy | grep -q docker &&
              test -d /opt/microservice-app || exit 1
            '
            echo "✅ Docker verificado correctamente en $IP"
          '''
        }
      }
    }

    stage("Deploy App (compose)"){
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        script {
          echo "🚀 Desplegando aplicación en VM: ${env.DROPLET_IP}"
          echo "   Repositorio: ${env.APP_REPO_URL}"
          echo "   Branch: ${env.APP_BRANCH}"
        }
        withCredentials([string(credentialsId: 'deploy-password', variable: 'DEPLOY_PASSWORD')]) {
          sh '''
            set -e
            # Usar la variable de entorno en lugar de leer archivo
            IP="${DROPLET_IP}"
            [ -n "$IP" ] || { echo "❌ No DROPLET_IP en variables de entorno"; exit 1; }

            echo "📦 Clonando app ${APP_BRANCH} desde ${APP_REPO_URL}..."
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

            echo "📊 Estado de contenedores en la VM:"
            sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null deploy@"$IP" 'cd /opt/microservice-app && docker compose ps'
            
            echo "✅ Despliegue completado en $IP"
          '''
        }
      }
    }

    stage("Deployment Summary"){
      when { anyOf { branch "main"; branch "infra/main" } }
      steps {
        script {
          def action = env.MSG?.contains('[rebuild]') ? 'REBUILD & DEPLOY' : 'DEPLOY'
          
          echo """
╔═══════════════════════════════════════════════════════════════════
║ 🎉 DESPLIEGUE COMPLETADO EXITOSAMENTE
╠═══════════════════════════════════════════════════════════════════
║ 📋 Información del despliegue:
║    • Acción realizada: ${action}
║    • VM IP Address: ${env.DROPLET_IP}
║    • Job: ${env.JOB_NAME} #${env.BUILD_NUMBER}
║    • Branch: ${env.BRANCH_NAME}
║    • Timestamp: ${new Date().format('yyyy-MM-dd HH:mm:ss')}
║
║ 🌐 Variables de entorno establecidas:
║    • DROPLET_IP = ${env.DROPLET_IP}
║    • VM_IP_ADDRESS = ${env.VM_IP_ADDRESS}
║
║ 🔗 Accesos a la aplicación:
║    • Frontend: http://${env.DROPLET_IP}:3000
║    • Zipkin: http://${env.DROPLET_IP}:9411
║    • Backup Frontend: http://${env.DROPLET_IP}:80
║
║ 📁 Artefactos generados:
║    • droplet.properties (IP y configuración)
║    • jenkins-env.properties (variables de entorno)
╚═══════════════════════════════════════════════════════════════════
          """
          
          // Crear un archivo de resumen final
          writeFile file: 'deployment-summary.txt', text: """
DEPLOYMENT SUMMARY
==================
Date: ${new Date().format('yyyy-MM-dd HH:mm:ss')}
Job: ${env.JOB_NAME} #${env.BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
Action: ${action}

VM Information:
- IP Address: ${env.DROPLET_IP}
- Name: ${env.NAME}
- Region: ${env.REGION}
- Size: ${env.SIZE}

Application URLs:
- Frontend: http://${env.DROPLET_IP}:3000
- Zipkin: http://${env.DROPLET_IP}:9411
- Backup Frontend: http://${env.DROPLET_IP}:80

Environment Variables Set:
- DROPLET_IP=${env.DROPLET_IP}
- VM_IP_ADDRESS=${env.VM_IP_ADDRESS}
"""
          
          archiveArtifacts artifacts: "deployment-summary.txt", fingerprint: true
        }
      }
    }
  }
  
  post {
    always {
      script {
        if (env.DROPLET_IP) {
          echo "🏁 Pipeline finalizado. IP de la VM disponible: ${env.DROPLET_IP}"
        }
      }
    }
    success {
      script {
        echo "✅ Pipeline ejecutado exitosamente!"
        if (env.DROPLET_IP) {
          echo "🌐 Tu aplicación está disponible en: http://${env.DROPLET_IP}:3000"
        }
      }
    }
    failure {
      script {
        echo "❌ Pipeline falló. Revisa los logs para más detalles."
      }
    }
  }
}