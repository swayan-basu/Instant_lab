#!/usr/bin/env bash
#
# Wazuh Agent for Instant Lab setup script
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
WAZUH_SOURCE_DIR="${ROOT_DIR}/wazuh-docker"
if [ "$WAZUH_DATA_ROOT" = "$ROOT_DIR" ]; then
  WAZUH_STACK_DIR="$WAZUH_SOURCE_DIR"
else
  WAZUH_STACK_DIR="${WAZUH_DATA_ROOT}/wazuh-docker"
fi
WAZUH_STACK_VERSION="v4.14.6"
WAZUH_COMPOSE_DIR="${WAZUH_STACK_DIR}/single-node"
WAZUH_NETWORK_NAME="instant_lab_network"

# Agent override
WAZUH_OVERRIDE_DIR="${WAZUH_DATA_ROOT}/.generated/wazuh-agent"
WAZUH_OVERRIDE_FILE="${WAZUH_OVERRIDE_DIR}/docker-compose.override.yml"

# Server override, used only to inspect the manager
WAZUH_SERVER_OVERRIDE_DIR="${WAZUH_DATA_ROOT}/.generated/wazuh"
WAZUH_SERVER_OVERRIDE_FILE="${WAZUH_SERVER_OVERRIDE_DIR}/single-node.override.yml"

ensure_wazuh_network() {
  if ! docker network inspect "$WAZUH_NETWORK_NAME" >/dev/null 2>&1; then
    docker network create --driver bridge "$WAZUH_NETWORK_NAME" >/dev/null
  fi
}

WAZUH_AGENT_LOCAL_DIR="${WAZUH_DATA_ROOT}/scripts/siem/wazuh-agent"
WAZUH_AGENT_DATA_DIR="${WAZUH_AGENT_LOCAL_DIR}/data"
WAZUH_AGENT_CONFIG_DIR="${WAZUH_AGENT_LOCAL_DIR}/config"
WAZUH_AGENT_TEMPLATE_DIR="${WAZUH_STACK_DIR}/wazuh-agent"
WAZUH_AGENT_COMPOSE_FILE="${WAZUH_AGENT_LOCAL_DIR}/docker-compose.yml"
WAZUH_AGENT_CONF_FILE="${WAZUH_AGENT_CONFIG_DIR}/wazuh-agent-conf"

if [ ! -d "$WAZUH_AGENT_DATA_DIR" ]; then
  echo "[*] creating Wazuh agent local directories at $WAZUH_AGENT_LOCAL_DIR"
  mkdir -p "$WAZUH_AGENT_DATA_DIR" "$WAZUH_AGENT_CONFIG_DIR"
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

if [ ! -d "$WAZUH_AGENT_TEMPLATE_DIR" ]; then
  echo "[-] missing Wazuh agent template directory at $WAZUH_AGENT_TEMPLATE_DIR"
  exit 1
fi

if [ ! -f "$WAZUH_AGENT_COMPOSE_FILE" ]; then
  cp "$WAZUH_AGENT_TEMPLATE_DIR/docker-compose.yml" "$WAZUH_AGENT_COMPOSE_FILE"
fi
if [ ! -f "$WAZUH_AGENT_CONF_FILE" ]; then
  cp "$WAZUH_AGENT_TEMPLATE_DIR/config/wazuh-agent-conf" "$WAZUH_AGENT_CONF_FILE"
fi

ensure_wazuh_network

WAZUH_MANAGER_SERVER="${WAZUH_MANAGER_SERVER:-}"

write_wazuh_agent_override_file() {
  mkdir -p "$WAZUH_OVERRIDE_DIR"

  cat > "$WAZUH_OVERRIDE_FILE" <<EOF
services:
  wazuh.agent:
    environment:
      WAZUH_MANAGER_SERVER: "$WAZUH_MANAGER_SERVER"
    networks:
      - wazuh-lab

networks:
  wazuh-lab:
    external: true
    name: "$WAZUH_NETWORK_NAME"
EOF
}

if [ -z "$WAZUH_MANAGER_SERVER" ]; then
  manager_running=false

  if [ -f "$WAZUH_COMPOSE_DIR/docker-compose.yml" ]; then
    if (
      cd "$WAZUH_COMPOSE_DIR"

      "${COMPOSE_CMD[@]}" \
        -f docker-compose.yml \
        -f "$WAZUH_SERVER_OVERRIDE_FILE" \
        ps --status running --services 2>/dev/null |
        grep -qx 'wazuh.manager'
    ); then
      manager_running=true
    fi
  fi

  if [ "$manager_running" = false ]; then
    echo "[*] Wazuh manager is not running; starting server stack"
    bash "$SCRIPT_DIR/start_wazuh.sh"

    echo "[*] waiting for Wazuh manager container"

    manager_ready=false

    for _ in {1..60}; do
      if (
        cd "$WAZUH_COMPOSE_DIR"

        "${COMPOSE_CMD[@]}" \
          -f docker-compose.yml \
          -f "$WAZUH_SERVER_OVERRIDE_FILE" \
          ps --status running --services 2>/dev/null |
          grep -qx 'wazuh.manager'
      ); then
        manager_ready=true
        break
      fi

      sleep 5
    done

    if [ "$manager_ready" = false ]; then
      echo "[-] Wazuh manager did not start successfully"
      exit 1
    fi
  fi
fi

WAZUH_MANAGER_SERVER="wazuh.manager"

if [ -z "$WAZUH_MANAGER_SERVER" ]; then
  echo "[-] Could not determine the Wazuh manager address."
  exit 1
fi

write_wazuh_agent_override_file

echo "[*] validating agent Compose configuration"

(
  cd "$WAZUH_AGENT_LOCAL_DIR"

  "${COMPOSE_CMD[@]}" \
    -f "$WAZUH_AGENT_COMPOSE_FILE" \
    -f "$WAZUH_OVERRIDE_FILE" \
    config >/dev/null
)

echo "[+] Starting Wazuh agent..."

(
  cd "$WAZUH_AGENT_LOCAL_DIR"

  "${COMPOSE_CMD[@]}" \
    -f "$WAZUH_AGENT_COMPOSE_FILE" \
    -f "$WAZUH_OVERRIDE_FILE" \
    up -d --force-recreate --remove-orphans
)

echo "[*] Wazuh agent started and pointed to manager: $WAZUH_MANAGER_SERVER"
echo "[*] Local agent files are stored in: $WAZUH_AGENT_LOCAL_DIR"
