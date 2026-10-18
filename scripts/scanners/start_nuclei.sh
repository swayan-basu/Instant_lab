#!/usr/bin/env bash
#
# Nuclei Scanner Setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="${INSTANT_LAB_DATA_DIR:-$ROOT_DIR}"
IMAGE="projectdiscovery/nuclei:latest"
NETWORK_NAME="instant_lab_network"
TEMPLATES_DIR="${DATA_DIR}/scripts/scanners/nuclei-templates"

echo "[+] Launching Nuclei Scanner..."
mkdir -p "$TEMPLATES_DIR"

if ! docker info >/dev/null 2>&1; then
    echo "[-] Docker is not accessible."
    exit 1
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network create --driver bridge "$NETWORK_NAME" >/dev/null
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker pull "$IMAGE"
fi

docker run -it --rm \
    --name instant_nuclei \
    --network "$NETWORK_NAME" \
    -v "$TEMPLATES_DIR:/root/nuclei-templates" \
    --entrypoint /bin/sh \
    "$IMAGE" \
    -c '
        if [ ! -f /root/nuclei-templates/.initialized ]; then
            echo "[+] Installing Nuclei templates..."
            nuclei -update-templates -ud /root/nuclei-templates
            touch /root/nuclei-templates/.initialized
        fi

        echo
        echo "[+] Nuclei shell started."
        exec /bin/sh
    '
