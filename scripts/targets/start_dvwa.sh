#!/usr/bin/env bash
#
# DVWA vulnerable application container setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

IMAGE="kaakaww/dvwa-docker:latest"
CONTAINER_NAME="instant_dvwa"
HOST_PORT=8080
CONTAINER_PORT=80
NETWORK_NAME="instant_lab_network"
URL="http://127.0.0.1:${HOST_PORT}/setup.php"

# ANSI colors; disable when output is redirected
if [[ -t 1 ]]; then
    CLR_RESET='\033[0m'
    CLR_GREEN='\033[38;2;0;230;118m'
    CLR_CYAN='\033[38;2;0;229;255m'
    CLR_RED='\033[38;2;255;23;68m'
    CLR_MUTED='\033[38;2;110;118;129m'
else
    CLR_RESET=''
    CLR_GREEN=''
    CLR_CYAN=''
    CLR_RED=''
    CLR_MUTED=''
fi

msg() {
    printf '%b\n' "$1"
}

cleanup_on_error() {
    msg "${CLR_RED}[-] Script failed. Container logs:${CLR_RESET}"
    docker logs "$CONTAINER_NAME" 2>/dev/null || true
}

trap cleanup_on_error ERR

msg "${CLR_CYAN}[+] Initializing DVWA container...${CLR_RESET}"

# Ensure Docker is running
if ! docker info >/dev/null 2>&1; then
    msg "${CLR_RED}[-] Docker daemon is not accessible.${CLR_RESET}"
    msg "${CLR_MUTED}[*] Start Docker or run with the required permissions.${CLR_RESET}"
    exit 1
fi

# Ensure network exists
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    msg "${CLR_MUTED}[*] Creating network: ${NETWORK_NAME}${CLR_RESET}"
    docker network create "$NETWORK_NAME" >/dev/null
fi

# Pull image
msg "${CLR_MUTED}[*] Pulling image: ${IMAGE}${CLR_RESET}"
docker pull "$IMAGE"

# Remove old container
if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    msg "${CLR_MUTED}[*] Removing old container: ${CONTAINER_NAME}${CLR_RESET}"
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

# Starting container
msg "${CLR_CYAN}[*] Starting DVWA on port ${HOST_PORT}...${CLR_RESET}"

docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    -p "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" \
    --restart unless-stopped \
    "$IMAGE" >/dev/null

# Check container process
if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
    msg "${CLR_RED}[-] Container failed to start.${CLR_RESET}"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

# Wait until HTTP responds
msg "${CLR_MUTED}[*] Waiting for DVWA to become ready...${CLR_RESET}"

ready=false

for _ in {1..30}; do
    if curl --silent --show-error --max-time 2 "$URL" >/dev/null 2>&1; then
        ready=true
        break
    fi
    sleep 1
done

if [[ "$ready" != "true" ]]; then
    msg "${CLR_RED}[-] Container is running, but DVWA is not responding.${CLR_RESET}"
    docker logs "$CONTAINER_NAME"
    exit 1
fi

msg "${CLR_GREEN}[+] DVWA is live!${CLR_RESET}"
msg "${CLR_MUTED}[*] Access URL:${CLR_RESET} ${CLR_GREEN}${URL}${CLR_RESET}"
msg "${CLR_MUTED}[*] Setup: Click 'Create / Reset Database'.${CLR_RESET}"
msg "${CLR_MUTED}[*] Default login: admin / password${CLR_RESET}"
msg "${CLR_MUTED}[*] Welcome to Instant lab DVWA environment!${CLR_RESET}"
