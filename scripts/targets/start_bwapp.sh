#!/usr/bin/env bash
#
# BWAPP Target for Instant Lab setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

IMAGE="cambarts/arm-bwapp"
CONTAINER_NAME="instant_bwapp"
HOST_PORT=8200
CONTAINER_PORT=80
NETWORK_NAME="instant_lab_network"

# Terminal colors
CLR_RESET="\033[0m"
CLR_GREEN="\033[38;2;0;230;118m"
CLR_RED="\033[38;2;255;23;68m"
CLR_MUTED="\033[38;2;110;118;129m"

echo -e "${CLR_RED}[+] Initializing bWAPP Target...${CLR_RESET}"

# Ensure lab bridge network exists
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network create "$NETWORK_NAME" >/dev/null
fi

# Remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    echo -e "${CLR_MUTED}[*] Removing existing ${CONTAINER_NAME} container...${CLR_RESET}"
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
fi

# Pull bwapp image
docker pull "$IMAGE"
IMAGE_ARCH="$(docker image inspect "$IMAGE" \
    --format '{{.Os}}/{{.Architecture}}')"

echo -e "${CLR_MUTED}[*] Image architecture: ${IMAGE_ARCH}${CLR_RESET}"

if [[ "$IMAGE_ARCH" != "linux/arm" ]]; then
    echo -e "${CLR_RED}[-] Warning: expected linux/arm but found ${IMAGE_ARCH}.${CLR_RESET}"
    exit 1
fi

docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    -p "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" \
    --restart=no \
    "$IMAGE" >/dev/null
sleep 3
STATUS="$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME")"

if [[ "$STATUS" != "running" ]]; then
    echo "bWAPP failed to start. Container status: $STATUS"
    docker logs "$CONTAINER_NAME"
    exit 1
fi
echo -e "${CLR_GREEN}[+] bWAPP is live!${CLR_RESET}"
echo -e "${CLR_MUTED}[*] Access URL: ${CLR_RESET}${CLR_GREEN}http://localhost:${HOST_PORT}/install.php${CLR_RESET}"
echo -e "${CLR_MUTED}[*] First time setup: Click 'Install/Create' database on that page.${CLR_RESET}"
