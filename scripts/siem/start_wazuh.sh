#!/usr/bin/env bash
#
# Wazuh for Instant Lab setup script
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail
echo "[+] Installing docker..."
if ! command -v docker >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y docker.io docker-compose-plugin git findutils
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker
  else
    sudo service docker start || true
  fi
  echo "[*] docker installed and started"
else
  echo "[*] docker is already installed."
fi

if ! command -v find >/dev/null 2>&1; then
  sudo apt update
  sudo apt install -y findutils
fi

ensure_docker_compose() {
  COMPOSE_CMD=()

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
    return 0
  fi

  echo "[+] installing docker compose support..."
  sudo apt update
  sudo apt install -y docker-compose-plugin docker-compose

  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
    return 0
  fi

  echo "[-] docker compose is not available"
  exit 1
}

ensure_docker_compose

# Add current user (or invoking user when run with sudo) to docker group if not already a member
target_user="${SUDO_USER:-$(id -un)}"
if [ "$target_user" = "root" ]; then
  echo "[*] running as root; skipping adding root to docker group"
else
  if ! id -nG "$target_user" | grep -qw docker; then
    sudo usermod -aG docker "$target_user"
    echo "[*] added $target_user to docker group — you may need to log out/in for this to take effect"
  else
    echo "[*] $target_user is already in docker group"
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "[-] Docker is not accessible."
  echo "[*] Log out and log in again after joining the docker group."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WAZUH_DATA_DIR="${ROOT_DIR}/wazuh"
WAZUH_STACK_DIR="${ROOT_DIR}/wazuh-docker"
WAZUH_STACK_VERSION="v4.14.6"
WAZUH_COMPOSE_DIR="${WAZUH_STACK_DIR}/single-node"
WAZUH_NETWORK_NAME="wazuh-lab"
WAZUH_OVERRIDE_DIR="${ROOT_DIR}/.generated/wazuh"
WAZUH_OVERRIDE_FILE="${WAZUH_OVERRIDE_DIR}/single-node.override.yml"

ensure_wazuh_network() {
  if ! docker network inspect "$WAZUH_NETWORK_NAME" >/dev/null 2>&1; then
    docker network create --driver bridge "$WAZUH_NETWORK_NAME" >/dev/null
  fi
}

write_wazuh_override_file() {
  mkdir -p "$WAZUH_OVERRIDE_DIR"
  cat > "$WAZUH_OVERRIDE_FILE" <<EOF
services:
  wazuh.manager:
    networks:
      - default
      - wazuh-lab
  wazuh.indexer:
    networks:
      - default
      - wazuh-lab
  wazuh.dashboard:
    networks:
      - default
      - wazuh-lab

networks:
  wazuh-lab:
    external: true
    name: ${WAZUH_NETWORK_NAME}
EOF
}

if [ ! -d "$WAZUH_DATA_DIR/data" ]; then
  echo "Creating Wazuh storage directories..."
  mkdir -p "$WAZUH_DATA_DIR/data"
fi

echo "[+] Configuring host kernel for the Wazuh indexer..."

echo "vm.max_map_count=262144" |
  sudo tee /etc/sysctl.d/99-wazuh-indexer.conf >/dev/null

sudo sysctl --system >/dev/null

if [ -e "$WAZUH_STACK_DIR" ] && [ ! -d "$WAZUH_STACK_DIR/.git" ]; then
  echo "[*] removing existing non-git Wazuh Docker directory at $WAZUH_STACK_DIR"
  rm -rf "$WAZUH_STACK_DIR"
fi

if [ ! -d "$WAZUH_STACK_DIR/.git" ]; then
  echo "[*] cloning Wazuh Docker stack at $WAZUH_STACK_VERSION"
  git clone https://github.com/wazuh/wazuh-docker.git "$WAZUH_STACK_DIR"
  git -C "$WAZUH_STACK_DIR" checkout "$WAZUH_STACK_VERSION"
else
  if [ -w "$WAZUH_STACK_DIR/.git" ] && [ -w "$WAZUH_STACK_DIR" ]; then
    echo "[*] updating existing Wazuh Docker stack checkout"
    git -C "$WAZUH_STACK_DIR" fetch --tags origin >/dev/null
    git -C "$WAZUH_STACK_DIR" checkout "$WAZUH_STACK_VERSION"
  else
    echo "[*] existing Wazuh Docker checkout is not writable; using current local version"
  fi
fi

if [ ! -d "$WAZUH_COMPOSE_DIR" ]; then
  echo "[-] missing Wazuh single-node compose directory at $WAZUH_COMPOSE_DIR"
  exit 1
fi

write_wazuh_override_file
ensure_wazuh_network

echo "[*] validating Wazuh Compose configuration"

(
  cd "$WAZUH_COMPOSE_DIR"

  "${COMPOSE_CMD[@]}" \
    -f docker-compose.yml \
    -f "$WAZUH_OVERRIDE_FILE" \
    config >/dev/null
)

echo "[*] generating Wazuh certificates"

(
  cd "$WAZUH_COMPOSE_DIR"

  "${COMPOSE_CMD[@]}" \
    -f generate-indexer-certs.yml \
    run --rm generator
)

echo "[+] Starting Wazuh single-node stack..."

(
  cd "$WAZUH_COMPOSE_DIR"

  "${COMPOSE_CMD[@]}" \
    -f docker-compose.yml \
    -f "$WAZUH_OVERRIDE_FILE" \
    up -d --force-recreate --remove-orphans
)

echo "[*] Wazuh stack started. Check the dashboard with:"
echo "    ${COMPOSE_CMD[*]} -f \"$WAZUH_COMPOSE_DIR/docker-compose.yml\" -f \"$WAZUH_OVERRIDE_FILE\" ps"
echo "    https://localhost:7608" default credentials: admin / SecretPassword
