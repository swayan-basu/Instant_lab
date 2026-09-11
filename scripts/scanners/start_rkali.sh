#!/usr/bin/env bash
#
# RKali Lab Container Setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab
set -euo pipefail

USER_NAME="${SUDO_USER:-$(id -un)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKDIR="${ROOT_DIR}/work"
RKALI_DIR="${SCRIPT_DIR}/rkali"
IMAGE_NAME="rkali"
CONTAINER_NAME="rkali"
CONTAINER_WORKDIR="/rkali"
SOC_SCRIPT="${SCRIPT_DIR}/../siem/soc_tools.sh"
NETWORK_NAME="rkali-net"

if [[ ! -f "$SOC_SCRIPT" ]]; then
    echo "[-] SOC script not found:"
    echo "    $SOC_SCRIPT"
    exit 1
fi

echo "[+] Creating Working Directory"
mkdir -p "$RKALI_DIR" "$WORKDIR"

echo "[+] Checking for Docker installation..."
if ! command -v docker >/dev/null 2>&1; then
    echo "[+] Installing Docker"

    sudo apt-get update
    sudo apt-get install -y \
        docker.io \
        git

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable --now docker
    else
        sudo service docker start || true
    fi
else
    echo "[*] Docker is already installed"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[-] docker is unavailable"
  exit 1
fi

echo "[+] Add $USER_NAME to Docker group (may require re-login to take effect)"
if ! id -nG "$USER_NAME" | grep -qw docker; then
    sudo usermod -aG docker "$USER_NAME"
    echo "[*] Added $USER_NAME to the Docker group"
    echo "[*] Log out and back in, or run: newgrp docker"
else
    echo "[*] $USER_NAME is already in the Docker group"
fi

echo "[+] Creating DOCKERFILE"
cat > "$RKALI_DIR/Dockerfile" <<'DOCKERFILE'
FROM kalilinux/kali-rolling:latest

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /rkali
DOCKERFILE

cat > "$RKALI_DIR/.dockerignore" <<'EOF'
.git
*.log
.cache
__pycache__
EOF

if ! docker info >/dev/null 2>&1; then
    echo "[-] Docker is not accessible from this shell."
    echo "[*] Run: newgrp docker"
    echo "[*] Then run this script again."
    exit 1
fi
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "[+] Creating Docker network: $NETWORK_NAME"
    docker network create \
        --driver bridge \
        "$NETWORK_NAME" >/dev/null
else
    echo "[*] Docker network already exists: $NETWORK_NAME"
fi


if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 && [[ "${REBUILD:-0}" != "1" ]]; then
    echo "[*] Image already exists; skipping build"
else
    echo "[+] Building image: $IMAGE_NAME (this may take a while)"

    for attempt in 1 2 3; do
        echo "[+] Docker build attempt $attempt of 3"

        if docker build -t "$IMAGE_NAME" "$RKALI_DIR"; then
            echo "[+] Image built successfully"
            break
        fi

        if [[ "$attempt" -eq 3 ]]; then
            echo "[-] Docker build failed after 3 attempts"
            exit 1
        fi

        echo "[!] Build failed; waiting 30 seconds before retry"
        sleep 30
    done
fi

if docker container inspect rkali >/dev/null 2>&1; then
    echo "[*] Container rkali already exists"

    if [[ "$(docker inspect -f '{{.State.Running}}' rkali)" != "true" ]]; then
        docker start rkali >/dev/null
    fi
else
    echo "[*] Starting rkali container"
    echo "[*] Volume mount: $WORKDIR:$CONTAINER_WORKDIR"
    echo "[*] Network: $NETWORK_NAME"
    echo "[*] Working directory: $CONTAINER_WORKDIR"
    echo "[*] **WELCOME TO INSTANT LAB WITH RKALI CONTAINER!**"
    docker run -d \
      --name rkali \
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
    echo "[+] Installing SOC tools..."
    docker exec -it "$CONTAINER_NAME" \
        bash /soc_tools.sh --yes
else
    echo "[*] Skipping SOC tools installation"
fi

echo
echo "[+] RKali container is running"
echo "[+] Container: $CONTAINER_NAME"
echo "[+] **WELCOME TO Kali Linux...**"

docker exec -it "$CONTAINER_NAME" bash
