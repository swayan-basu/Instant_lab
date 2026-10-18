#!/usr/bin/env bash
#
# RKali Lab Container Setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="${INSTANT_LAB_DATA_DIR:-$ROOT_DIR}"
WORKDIR="${DATA_DIR}/work"
RKALI_DIR="${DATA_DIR}/.generated/rkali"
IMAGE_NAME="rkali"
CONTAINER_NAME="rkali"
CONTAINER_WORKDIR="/rkali"
SOC_SCRIPT="${ROOT_DIR}/scripts/siem/soc_tools.sh"
NETWORK_NAME="instant_lab_network"

if [[ ! -f "$SOC_SCRIPT" ]]; then
    echo "[-] SOC script not found at $SOC_SCRIPT"
    exit 1
fi

echo "[+] Creating Working Directory"
mkdir -p "$RKALI_DIR" "$WORKDIR"

if ! docker info >/dev/null 2>&1; then
    echo "[-] Docker is not accessible."
    exit 1
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network create --driver bridge "$NETWORK_NAME" >/dev/null
fi

echo "[+] Building/Checking rkali image..."
mkdir -p "$RKALI_DIR"
cat > "$RKALI_DIR/Dockerfile" <<'DOCKERFILE'
FROM kalilinux/kali-rolling:latest
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /rkali
DOCKERFILE

if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 || [[ "${REBUILD:-0}" == "1" ]]; then
    docker build -t "$IMAGE_NAME" "$RKALI_DIR"
fi

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
        docker start "$CONTAINER_NAME" >/dev/null
    fi
else
    docker run -d \
      --name "$CONTAINER_NAME" \
      --network "$NETWORK_NAME" \
      --user 0:0 \
      --cap-add=NET_RAW \
      --cap-add=NET_ADMIN \
      -v "$WORKDIR:$CONTAINER_WORKDIR" \
      -v "$SOC_SCRIPT:/soc_tools.sh:ro" \
      -w "$CONTAINER_WORKDIR" \
      "$IMAGE_NAME" \
      tail -f /dev/null
fi

read -r -p "Install SOC tools in the container? (y/n) " install_soc_tools
if [[ "$install_soc_tools" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    docker exec -it "$CONTAINER_NAME" bash /soc_tools.sh --yes
fi

docker exec -it "$CONTAINER_NAME" bash

echo
echo "[+] RKali container is running"
echo "[+] Container: $CONTAINER_NAME"
echo "[+] **WELCOME TO Kali Linux...**"

docker exec -it "$CONTAINER_NAME" bash
