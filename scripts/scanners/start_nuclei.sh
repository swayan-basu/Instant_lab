#!/usr/bin/env bash
#
# Nuclei Scanner Setup
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="projectdiscovery/nuclei:latest"
NETWORK_NAME="instant_lab_network"
TEMPLATES_DIR="${SCRIPT_DIR}/nuclei-templates"

# Cybersecurity ANSI Palette
CLR_RESET="\033[0m"
CLR_CYAN="\033[38;2;0;229;255m"
CLR_GREEN="\033[38;2;0;230;118m"
CLR_MUTED="\033[38;2;110;118;129m"

echo -e "${CLR_CYAN}[+] Launching Nuclei Scanner...${CLR_RESET}"

mkdir -p "$TEMPLATES_DIR"


if ! command -v docker >/dev/null 2>&1; then
    echo "[-] Docker is not installed."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "[-] Docker is not accessible."
    echo "[!] Start Docker or configure the Docker group for your user."
    exit 1
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo -e "${CLR_MUTED}[*] Creating Docker network: ${NETWORK_NAME}${CLR_RESET}"
    docker network create "$NETWORK_NAME" >/dev/null
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo -e "${CLR_MUTED}[*] Pulling ${IMAGE}...${CLR_RESET}"
    docker pull "$IMAGE"
fi

echo -e "${CLR_GREEN}[+] Nuclei will use network: $NETWORK_NAME${CLR_RESET}"
echo -e "${CLR_MUTED}[*] Targets must be reachable from this Docker network.${CLR_RESET}"
echo

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
        echo "[+] Examples:"
        echo "    nuclei -u http://juice-shop:3000 -t /root/nuclei-templates"
        echo "    nuclei -u http://dvwa:80 -t /root/nuclei-templates"
        echo "    nuclei -u https://authorized-example.com -t /root/nuclei-templates"
        echo

        exec /bin/sh
    '
