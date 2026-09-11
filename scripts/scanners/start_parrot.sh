#!/usr/bin/env bash
#
# Parrot Lab Container Setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${PWD}/work"
SOC_SCRIPT="${SCRIPT_DIR}/../siem/soc_tools.sh"
MSF_DIR="${SCRIPT_DIR}/msf"
IMAGE="parrotsec/security"
CONTAINER_NAME="parrot-lab"
NETWORK_NAME="parrot-lab-net"

mkdir -p "$WORK_DIR" "$MSF_DIR"


echo "[+] Checking for Docker...."
if ! command -v docker >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y docker.io git
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker
  else
    sudo service docker start || true
  fi
  echo "[*] docker installed and started"
else
  echo "[*] docker is already installed."
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[-] docker is not available after installation"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "[-] Docker is installed, but unreachable."
  echo "[*] Try: sudo systemctl start docker"
  echo "[*] If permission is denied, try: newgrp docker"
  exit 1
fi
if [[ ! -f "$SOC_SCRIPT" ]]; then
    echo "[-] SOC script not found:"
    echo "    $SOC_SCRIPT"
    exit 1
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "[+] Creating Docker network: $NETWORK_NAME"
  docker network create "$NETWORK_NAME" >/dev/null
else
  echo "[*] Docker network already exists: $NETWORK_NAME"
fi

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "[*] Container already exists"

    if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
        echo "[+] Starting stopped container..."
        docker start "$CONTAINER_NAME" >/dev/null
    else
        echo "[*] Container is already running"
    fi
else
    echo "[+] Pulling image: $IMAGE"
    docker pull "$IMAGE"

    echo "[+] Creating Parrot container..."

    docker run -d \
        --name "$CONTAINER_NAME" \
        --hostname "$CONTAINER_NAME" \
        --network "$NETWORK_NAME" \
        --cap-add=NET_RAW \
        --cap-add=NET_ADMIN \
        -v "$WORK_DIR:/work" \
        -v "$MSF_DIR:/msf" \
        -v "$SOC_SCRIPT:/soc_tools.sh:ro" \
        "$IMAGE" \
        tail -f /dev/null
fi

read -r -p "Install SOC tools in the container? (y/n) " install_soc_tools
if [[ "$install_soc_tools" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "[+] Installing SOC tools..."
    docker exec -it "$CONTAINER_NAME" \
        bash /soc_tools.sh --yes
else
    echo "[*] Skipping SOC tools installation"
fi

echo
echo "[+] Parrot container is running"
echo "[+] Container: $CONTAINER_NAME"
echo "[+] Work directory: $WORK_DIR"
echo "[+] **WELCOME TO PARROT SECURITY...**"

docker exec -it "$CONTAINER_NAME" bash

