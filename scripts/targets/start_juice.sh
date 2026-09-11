#!/usr/bin/env bash
#
# Juice-Shop vulnerable application container setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

IMAGE="bkimminich/juice-shop:latest"
CONTAINER_NAME="juice-shop"
HOST_PORT=3000
CONTAINER_PORT=3000
NETWORK_NAME="instant_lab_network"

echo "[+] Checking for Docker...."
if ! command -v docker >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y docker.io
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker
  else
    sudo service docker start || true
  fi
  echo "[*] Docker installed and started"
else
  echo "[*] Docker is already installed."
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[-] Docker is not available after installation"
  exit 1
fi

if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl is-active --quiet docker; then
        sudo systemctl start docker
    fi
else
    sudo service docker start >/dev/null 2>&1 || true
fi

# Add current user to docker group if not already a member
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    sudo usermod -aG docker "$USER"

    echo "[*] Added $USER to the docker group."
    echo "[!] Log out and back in, then run this script again."
    exit 0
else
    echo "[*] $USER is already in the docker group."
fi

if ! docker info >/dev/null 2>&1; then
  echo "[-] Docker is installed but unavailable to the current user."
  echo "[!] Log out and back in, or run: newgrp docker"
  exit 1
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "[+] Creating Docker network: $NETWORK_NAME"
  docker network create "$NETWORK_NAME" >/dev/null
else
  echo "[*] Docker network already exists: $NETWORK_NAME"
fi

echo "[+] Pulling Juice-Shop..."

# Pull the latest image
docker pull "$IMAGE"
echo "[*] pulled latest Juice-Shop image: $IMAGE"

# Remove any existing container with the same name
if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "[*] Removing existing container: $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME"
fi

# Run detached, bind to localhost, and restart automatically
echo "[*] running juice-shop container named $CONTAINER_NAME on port $HOST_PORT"
docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    --publish "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" \
    --restart unless-stopped \
    "$IMAGE"

echo
echo "[+] Juice Shop is running."
echo "[+] Access it at: http://localhost:${HOST_PORT}"
echo "[+] Container name: ${CONTAINER_NAME}"
echo "[+] Welcome to the instant Juice Shop lab environment!"
