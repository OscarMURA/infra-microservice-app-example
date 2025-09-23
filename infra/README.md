# Infra - DigitalOcean Droplet provisioning

Este folder contiene:

- `cloud-init.yaml`: configura el Droplet (usuario `deploy` con contraseña, Docker/Compose, UFW, puertos).
- `create-do-droplet.sh`: crea un Droplet por API de DigitalOcean usando `DO_TOKEN`.

## Requisitos

- DigitalOcean Personal Access Token con permisos de escritura (`DO_TOKEN`).
- `bash`, `curl`, `jq` instalados.

## Crear la VM (login por contraseña)

1. Exporta variables mínimas:

```bash
export DO_TOKEN=<tu_token_do>
export DEPLOY_PASSWORD='P@ssw0rd!'
```

2. Ejecuta el script (valores por defecto entre paréntesis):

```bash
cd infra
REGION=nyc3 SIZE=s-1vcpu-2gb IMAGE=ubuntu-22-04-x64 NAME=microservice-app \
./create-do-droplet.sh
```

3. Conéctate:

```bash
ssh deploy@<IP_PUBLICA>
# password: la de DEPLOY_PASSWORD
```

Notas:

- `cloud-init` habilita `PasswordAuthentication yes` y configura Docker + compose plugin.
- UFW abre puertos 22, 3000, 8000, 8082, 8083, 9411.

## Jenkins (CD) con contraseña

- Credencial tipo "SSH Username with password": user `deploy`, password `DEPLOY_PASSWORD`.
- Paso de despliegue (ejemplo):

```bash
sshpass -p "$DEPLOY_PASSWORD" ssh -o StrictHostKeyChecking=no deploy@${DEPLOY_HOST} \
  'mkdir -p /opt/microservice-app && cd /opt/microservice-app && \
   docker compose pull && docker compose up -d && docker compose ps'
```

Recomendación: para producción, usar SSH keys; el login por contraseña se deja para simplicidad de la demo.
