#!/usr/bin/env bash
#
# ELK Stack setup script for Instant Lab
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail  

source "$(cd "$(dirname "$0")" && pwd)/../setup/docker_env.sh"
source "$(cd "$(dirname "$0")" && pwd)/../setup/port_check.sh"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$EUID" -ne 0 && ! -t 0 ]] && ! sudo -n true 2>/dev/null; then
  echo "[-] This script needs sudo authentication when Docker is not already configured."
  echo "[*] Run it from an interactive terminal, or authenticate first with: sudo -v"
  exit 1
fi

ELASTICSEARCH_HOST_PORT="${ELASTICSEARCH_HOST_PORT:-9201}"
KIBANA_HOST_PORT="${KIBANA_HOST_PORT:-5602}"
LOGSTASH_BEATS_HOST_PORT="${LOGSTASH_BEATS_HOST_PORT:-5045}"
LOGSTASH_API_HOST_PORT="${LOGSTASH_API_HOST_PORT:-9601}"

if [ "$ELASTICSEARCH_HOST_PORT" = "$KIBANA_HOST_PORT" ]; then
  echo "[-] ELK Elasticsearch and Kibana cannot use the same host port"
  exit 1
fi

if [ "$ELASTICSEARCH_HOST_PORT" = "$LOGSTASH_BEATS_HOST_PORT" ] ||
   [ "$ELASTICSEARCH_HOST_PORT" = "$LOGSTASH_API_HOST_PORT" ] ||
   [ "$KIBANA_HOST_PORT" = "$LOGSTASH_BEATS_HOST_PORT" ] ||
   [ "$KIBANA_HOST_PORT" = "$LOGSTASH_API_HOST_PORT" ] ||
   [ "$LOGSTASH_BEATS_HOST_PORT" = "$LOGSTASH_API_HOST_PORT" ]; then
  echo "[-] ELK services cannot use the same host port"
  exit 1
fi

recreate_if_port_mapping_changed() {
  local container="$1"
  local container_port="$2"
  local host_port="$3"
  local bindings

  if docker container inspect "$container" >/dev/null 2>&1; then
    bindings="$(docker inspect -f '{{json .NetworkSettings.Ports}}' "$container")"
    if ! grep -q "\"${container_port}/tcp\".*\"HostPort\":\"${host_port}\"" <<<"$bindings" ||
       [[ "$(docker inspect -f '{{.State.Status}}' "$container")" != "running" && "$bindings" == "{}" ]]; then
      echo "[*] Recreating ${container} to apply host port ${host_port}"
      docker rm -f "$container" >/dev/null
    fi
  fi
}

echo "[+] Installing required packages..."

sudo apt update
sudo apt install -y docker.io docker-compose git curl
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now docker
else
  sudo service docker start || true
fi

echo "[*] Docker installed and started"

if ! command -v docker >/dev/null 2>&1; then
  echo "[-] docker is not available after installation"
  exit 1
fi

check_port "$ELASTICSEARCH_HOST_PORT" elasticsearch Elasticsearch
check_port "$KIBANA_HOST_PORT" kibana Kibana
check_port "$LOGSTASH_BEATS_HOST_PORT" logstash Logstash
check_port "$LOGSTASH_API_HOST_PORT" logstash Logstash

if ! groups "$USER" | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  echo "[*] Added $USER to docker group (log out/in or run: newgrp docker)"
else
  echo "[*] $USER is already in docker group"
fi

echo "[*] Create a network for Elasticsearch Logstash Kibana..."
if ! docker network ls --format '{{.Name}}' | grep -qw elk-network; then
  docker network create elk-network
  echo "[*] Network created: elk-network"
else
  echo "[*] Network 'elk-network' already exists"
fi

#Elasticsearch

echo "[*] Starting Elasticsearch..."

docker pull docker.elastic.co/elasticsearch/elasticsearch:9.3.1
recreate_if_port_mapping_changed elasticsearch 9200 "$ELASTICSEARCH_HOST_PORT"
if docker ps -a --format '{{.Names}}' | grep -qw '^elasticsearch$'; then
  docker start elasticsearch 2>/dev/null || true
else
  docker run -d \
    --name elasticsearch \
    --network elk-network \
    --restart unless-stopped \
    -p "${ELASTICSEARCH_HOST_PORT}:9200" \
    -e discovery.type=single-node \
    -e xpack.security.enabled=false \
    -e ES_JAVA_OPTS="-Xms1g -Xmx1g" \
    -v elasticsearch-data:/usr/share/elasticsearch/data \
    docker.elastic.co/elasticsearch/elasticsearch:9.3.1
fi

echo "[*] Waiting for Elasticsearch to become ready..."

for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:${ELASTICSEARCH_HOST_PORT}" >/dev/null 2>&1; then
    echo "[*] Elasticsearch is ready"
    break
  fi

  if [ "$i" -eq 60 ]; then
    echo "[-] Elasticsearch did not become ready"
    docker logs elasticsearch --tail 100
    exit 1
  fi

  sleep 5
done


#LOGSTASH

mkdir -p "$SCRIPT_DIR/logstash/pipeline"

sudo tee "$SCRIPT_DIR/logstash/pipeline/logstash.conf" >/dev/null <<'EOF'
input {
  beats {
    host => "0.0.0.0"
    port => 5044
  }
}

output {
  stdout {
    codec => rubydebug
  }

  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
  }
}
EOF

echo "[*] Starting Logstash..."

docker pull docker.elastic.co/logstash/logstash:9.3.1
recreate_if_port_mapping_changed logstash 5044 "$LOGSTASH_BEATS_HOST_PORT"
recreate_if_port_mapping_changed logstash 9600 "$LOGSTASH_API_HOST_PORT"
if docker ps -a --format '{{.Names}}' | grep -qw '^logstash$'; then
  docker start logstash 2>/dev/null || true
  docker restart logstash >/dev/null
else
  docker run -d \
    --name logstash \
    --network elk-network \
    --restart unless-stopped \
    -p "${LOGSTASH_BEATS_HOST_PORT}:5044" \
    -p "${LOGSTASH_API_HOST_PORT}:9600" \
    -v "$SCRIPT_DIR/logstash/pipeline:/usr/share/logstash/pipeline:ro" \
    -v logstash_data:/usr/share/logstash/data \
    docker.elastic.co/logstash/logstash:9.3.1
fi

if docker ps --format '{{.Names}}' | grep -qw '^logstash$'; then
  echo "[*] Logstash container is running"
else
  echo "[-] Logstash failed to start"
  docker logs logstash
  exit 1
fi

#KIBANA

echo "[*] Starting Kibana..."

docker pull docker.elastic.co/kibana/kibana:9.3.1
recreate_if_port_mapping_changed kibana 5601 "$KIBANA_HOST_PORT"
if docker container inspect kibana >/dev/null 2>&1 &&
   ! docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' kibana |
     grep -Fq 'ELASTICSEARCH_HOSTS=["http://elasticsearch:9200"]'; then
  echo "[*] Recreating kibana to apply the Elasticsearch endpoint"
  docker rm -f kibana >/dev/null
fi
if docker ps -a --format '{{.Names}}' | grep -qw '^kibana$'; then
  docker start kibana 2>/dev/null || true
else
  docker run -d \
    --name kibana \
    --network elk-network \
    --restart unless-stopped \
    -p "${KIBANA_HOST_PORT}:5601" \
    -e SERVER_HOST=0.0.0.0 \
    -e 'ELASTICSEARCH_HOSTS=["http://elasticsearch:9200"]' \
    docker.elastic.co/kibana/kibana:9.3.1
fi

echo "[*] Waiting for Kibana..."

for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:${KIBANA_HOST_PORT}/api/status" >/dev/null 2>&1; then
    echo "[*] Kibana is ready at http://localhost:${KIBANA_HOST_PORT}"
    break
  fi

  if ! docker ps --format '{{.Names}}' | grep -qw '^kibana$'; then
    echo "[-] Kibana stopped unexpectedly"
    docker logs kibana --tail 100
    exit 1
  fi

  if [ "$i" -eq 60 ]; then
    echo "[-] Kibana did not become ready"
    docker logs kibana --tail 100
    exit 1
  fi

  sleep 5
done

echo "[*] Kibana container is running. Access it at http://localhost:${KIBANA_HOST_PORT}"
echo "[*] Logstash container is running. API at http://localhost:${LOGSTASH_API_HOST_PORT} and Beats input at port ${LOGSTASH_BEATS_HOST_PORT}"
echo "[*] Elasticsearch container is running. Access it at http://localhost:${ELASTICSEARCH_HOST_PORT}"
