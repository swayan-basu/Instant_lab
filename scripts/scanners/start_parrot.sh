#!/usr/bin/env bash
#
# Parrot Lab Container Setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="${INSTANT_LAB_DATA_DIR:-$ROOT_DIR}"
WORK_DIR="${DATA_DIR}/work"
MSF_DIR="${DATA_DIR}/scripts/scanners/msf"
SOC_SCRIPT="${ROOT_DIR}/scripts/siem/soc_tools.sh"
IMAGE="parrotsec/security"
CONTAINER_NAME="parrot-lab"
NETWORK_NAME="instant_lab_network"

mkdir -p "$WORK_DIR" "$MSF_DIR"

if ! docker info >/dev/null 2>&1; then
  echo "[-] Docker daemon is unreachable."
  exit 1
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create --driver bridge "$NETWORK_NAME" >/dev/null
fi

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]]; then
        docker start "$CONTAINER_NAME" >/dev/null
    fi
else
    docker pull "$IMAGE"
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
    docker exec -it "$CONTAINER_NAME" bash /soc_tools.sh --yes
fi

docker exec -it "$CONTAINER_NAME" bash

echo
echo "[+] Parrot container is running"
echo "[+] Container: $CONTAINER_NAME"
echo "[+] Work directory: $WORK_DIR"
echo "[+] **WELCOME TO PARROT SECURITY...**"

docker exec -it "$CONTAINER_NAME" bash

