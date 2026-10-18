#!/usr/bin/env bash
#
# ELK Stack setup script for Instant Lab
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail  
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DATA_DIR="${INSTANT_LAB_DATA_DIR:-$ROOT_DIR}"
NETWORK_NAME="instant_lab_network"
ELASTICSEARCH_IMAGE="docker.elastic.co/elasticsearch/elasticsearch:9.3.1"
LOGSTASH_IMAGE="docker.elastic.co/logstash/logstash:9.3.1"
KIBANA_IMAGE="docker.elastic.co/kibana/kibana:9.3.1"
LOGSTASH_BEATS_PORT="${ELK_LOGSTASH_BEATS_PORT:-5044}"
LOGSTASH_API_PORT="${ELK_LOGSTASH_API_PORT:-9600}"
REQUESTED_ELASTICSEARCH_PORT="${ELK_ELASTICSEARCH_PORT:-9200}"
REQUESTED_KIBANA_PORT="${ELK_KIBANA_PORT:-5601}"
ELASTICSEARCH_PORT="$REQUESTED_ELASTICSEARCH_PORT"
KIBANA_PORT="$REQUESTED_KIBANA_PORT"

port_is_available() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    if ss_output="$(ss -H -ltn "sport = :${port}" 2>/dev/null)"; then
      [ -z "$ss_output" ]
      return
    fi
  fi

  ! (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null
}

select_port() {
  local requested="$1"
  local fallback="$2"

  if port_is_available "$requested"; then
    printf '%s' "$requested"
  else
    echo "[!] Host port ${requested} is busy; using ${fallback} instead." >&2
    if ! port_is_available "$fallback"; then
      echo "[-] Host ports ${requested} and ${fallback} are both busy." >&2
      exit 1
    fi
    printf '%s' "$fallback"
  fi
}

running_container_port() {
  local container="$1"
  local container_port="$2"
  local mapping

  if [ "$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" = "true" ]; then
    mapping="$(docker port "$container" "$container_port" 2>/dev/null | head -n 1)"
    if [ -n "$mapping" ]; then
      printf '%s' "${mapping##*:}"
      return 0
    fi
  fi

  return 1
}

echo "[+] Checking Docker daemon..."
if ! command -v docker >/dev/null 2>&1; then
  echo "[-] docker is not available"
  exit 1
fi

echo "[*] Ensuring network '${NETWORK_NAME}' exists..."
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create --driver bridge "$NETWORK_NAME" >/dev/null
  echo "[*] Network created: ${NETWORK_NAME}"
else
  echo "[*] Network '${NETWORK_NAME}' already exists"
fi

if ! ELASTICSEARCH_PORT="$(running_container_port elasticsearch 9200/tcp)"; then
  ELASTICSEARCH_PORT="$(select_port "$REQUESTED_ELASTICSEARCH_PORT" 19200)"
fi
if ! KIBANA_PORT="$(running_container_port kibana 5601/tcp)"; then
  KIBANA_PORT="$(select_port "$REQUESTED_KIBANA_PORT" 15601)"
fi

# Elasticsearch
echo "[*] Starting Elasticsearch..."
docker pull "$ELASTICSEARCH_IMAGE"
if docker container inspect elasticsearch >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' elasticsearch)" = "true" ]; then
    echo "[*] Elasticsearch is already running"
  else
    docker rm elasticsearch >/dev/null
    docker run -d \
      --name elasticsearch \
      --network "$NETWORK_NAME" \
      --restart unless-stopped \
      -p "${ELASTICSEARCH_PORT}:9200" \
      -e discovery.type=single-node \
      -e xpack.security.enabled=false \
      -e ES_JAVA_OPTS="-Xms1g -Xmx1g" \
      -v elasticsearch-data:/usr/share/elasticsearch/data \
      "$ELASTICSEARCH_IMAGE"
  fi
else
  docker run -d \
    --name elasticsearch \
    --network "$NETWORK_NAME" \
    --restart unless-stopped \
    -p "${ELASTICSEARCH_PORT}:9200" \
    -e discovery.type=single-node \
    -e xpack.security.enabled=false \
    -e ES_JAVA_OPTS="-Xms1g -Xmx1g" \
    -v elasticsearch-data:/usr/share/elasticsearch/data \
    "$ELASTICSEARCH_IMAGE"
fi

echo "[*] Waiting for Elasticsearch to become ready..."
for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:${ELASTICSEARCH_PORT}" >/dev/null 2>&1; then
    echo "[*] Elasticsearch is ready at http://localhost:${ELASTICSEARCH_PORT}"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "[-] Elasticsearch did not become ready"
    docker logs elasticsearch --tail 100
    exit 1
  fi
  sleep 5
done

# Logstash
LOGSTASH_DIR="$DATA_DIR/logstash/pipeline"
mkdir -p "$LOGSTASH_DIR"

LOGSTASH_PORT_ARGS=()
if port_is_available "$LOGSTASH_BEATS_PORT"; then
  LOGSTASH_PORT_ARGS+=(-p "${LOGSTASH_BEATS_PORT}:5044")
else
  echo "[!] Host port ${LOGSTASH_BEATS_PORT} is busy; Logstash beats input remains available inside Docker."
fi
if port_is_available "$LOGSTASH_API_PORT"; then
  LOGSTASH_PORT_ARGS+=(-p "${LOGSTASH_API_PORT}:9600")
else
  echo "[!] Host port ${LOGSTASH_API_PORT} is busy; Logstash monitoring API remains available inside Docker."
fi

cat > "$LOGSTASH_DIR/logstash.conf" <<'EOF'
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
docker pull "$LOGSTASH_IMAGE"
if docker container inspect logstash >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' logstash)" = "true" ]; then
    echo "[*] Logstash is already running"
  else
    docker rm logstash >/dev/null
    docker run -d \
      --name logstash \
      --network "$NETWORK_NAME" \
      --restart unless-stopped \
      "${LOGSTASH_PORT_ARGS[@]}" \
      -v "$LOGSTASH_DIR:/usr/share/logstash/pipeline:ro" \
      -v logstash_data:/usr/share/logstash/data \
      "$LOGSTASH_IMAGE"
  fi
else
  docker run -d \
    --name logstash \
    --network "$NETWORK_NAME" \
    --restart unless-stopped \
    "${LOGSTASH_PORT_ARGS[@]}" \
    -v "$LOGSTASH_DIR:/usr/share/logstash/pipeline:ro" \
    -v logstash_data:/usr/share/logstash/data \
    "$LOGSTASH_IMAGE"
fi

# Kibana
echo "[*] Starting Kibana..."
docker pull "$KIBANA_IMAGE"
if docker container inspect kibana >/dev/null 2>&1; then
  if [ "$(docker inspect -f '{{.State.Running}}' kibana)" = "true" ]; then
    echo "[*] Kibana is already running"
  else
    docker rm kibana >/dev/null
    docker run -d \
      --name kibana \
      --network "$NETWORK_NAME" \
      --restart unless-stopped \
      -p "${KIBANA_PORT}:5601" \
      -e SERVER_HOST=0.0.0.0 \
      -e 'ELASTICSEARCH_HOSTS=["http://elasticsearch:9200"]' \
      "$KIBANA_IMAGE"
  fi
else
  docker run -d \
    --name kibana \
    --network "$NETWORK_NAME" \
    --restart unless-stopped \
    -p "${KIBANA_PORT}:5601" \
    -e SERVER_HOST=0.0.0.0 \
    -e 'ELASTICSEARCH_HOSTS=["http://elasticsearch:9200"]' \
    "$KIBANA_IMAGE"
fi

echo "[*] Waiting for Kibana..."
for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:${KIBANA_PORT}/api/status" >/dev/null 2>&1; then
    echo "[*] Kibana is ready at http://localhost:${KIBANA_PORT}"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "[-] Kibana did not become ready"
    docker logs kibana --tail 100
    exit 1
  fi
  sleep 5
done

echo "[*] ELK stack is Live!"
