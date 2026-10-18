#!/usr/bin/env bash
#
# Wazuh for Instant Lab setup script
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

# Keep the Docker CLI shipped inside the Snap ahead of host Snap commands.
if [ -n "${SNAP:-}" ] && [ -x "$SNAP/bin/docker" ]; then
  export PATH="$SNAP/bin:$PATH"
fi

if ! docker info >/dev/null 2>&1; then
  echo "[-] Docker daemon is not accessible. Ensure the docker plug is connected."
  exit 1
fi

COMPOSE_CMD=()
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif [ -x /usr/libexec/docker/cli-plugins/docker-compose ]; then
  COMPOSE_CMD=(/usr/libexec/docker/cli-plugins/docker-compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "[-] docker compose is not available"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WAZUH_DATA_ROOT="${INSTANT_LAB_DATA_DIR:-$ROOT_DIR}"
WAZUH_DATA_DIR="${WAZUH_DATA_ROOT}/wazuh"
WAZUH_SOURCE_DIR="${ROOT_DIR}/wazuh-docker"
if [ "$WAZUH_DATA_ROOT" = "$ROOT_DIR" ]; then
  WAZUH_STACK_DIR="$WAZUH_SOURCE_DIR"
else
  WAZUH_STACK_DIR="${WAZUH_DATA_ROOT}/wazuh-docker"
fi
WAZUH_STACK_VERSION="v4.14.6"
WAZUH_COMPOSE_DIR="${WAZUH_STACK_DIR}/single-node"
WAZUH_NETWORK_NAME="instant_lab_network"
WAZUH_OVERRIDE_DIR="${WAZUH_DATA_ROOT}/.generated/wazuh"
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
    # Manager traffic is consumed by the agent on the Docker network. Do not
    # publish these ports on the host, where they can conflict with services
    # already using the standard Wazuh ports.
    ports: !reset []
    networks:
      - default
      - wazuh-lab
  wazuh.indexer:
    # Elasticsearch owns the host's 9200 endpoint in Instant Lab.
    ports: !reset []
    networks:
      - default
      - wazuh-lab
  wazuh.dashboard:
    ports: !override
      - "7608:5601"
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

if [ ! -d "$WAZUH_COMPOSE_DIR" ]; then
  if [ "$WAZUH_STACK_DIR" != "$WAZUH_SOURCE_DIR" ] && [ -d "$WAZUH_SOURCE_DIR/single-node" ]; then
    echo "[*] copying bundled Wazuh Docker stack to writable application data"
    mkdir -p "$(dirname "$WAZUH_STACK_DIR")"
    cp -a "$WAZUH_SOURCE_DIR" "$WAZUH_STACK_DIR"
  else
    echo "[*] cloning Wazuh Docker stack at $WAZUH_STACK_VERSION"
    mkdir -p "$(dirname "$WAZUH_STACK_DIR")"
    git clone https://github.com/wazuh/wazuh-docker.git "$WAZUH_STACK_DIR"
    git -C "$WAZUH_STACK_DIR" checkout "$WAZUH_STACK_VERSION"
  fi
else
  if [ -d "$WAZUH_STACK_DIR/.git" ] && [ -w "$WAZUH_STACK_DIR/.git" ] && [ -w "$WAZUH_STACK_DIR" ]; then
    echo "[*] updating existing Wazuh Docker stack checkout"
    git -C "$WAZUH_STACK_DIR" fetch --tags origin >/dev/null
    git -C "$WAZUH_STACK_DIR" checkout "$WAZUH_STACK_VERSION"
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
echo "    https://localhost:7608 (default credentials: admin / SecretPassword)"
