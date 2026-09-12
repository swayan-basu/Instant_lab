#!/usr/bin/env bash
#
# ELK Stack setup script for Instant Lab
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail  
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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
if docker ps -a --format '{{.Names}}' | grep -qw '^elasticsearch$'; then
  docker start elasticsearch 2>/dev/null || true
else
  docker run -d \
    --name elasticsearch \
    --network elk-network \
    --restart unless-stopped \
    -p 9200:9200 \
    -e discovery.type=single-node \
    -e xpack.security.enabled=false \
    -e ES_JAVA_OPTS="-Xms1g -Xmx1g" \
    -v elasticsearch-data:/usr/share/elasticsearch/data \
    docker.elastic.co/elasticsearch/elasticsearch:9.3.1
fi

echo "[*] Waiting for Elasticsearch to become ready..."

for i in {1..60}; do
  if curl -fsS http://127.0.0.1:9200 >/dev/null 2>&1; then
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

cat > "$SCRIPT_DIR/logstash/pipeline/logstash.conf" <<'EOF'
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
if docker ps -a --format '{{.Names}}' | grep -qw '^logstash$'; then
  docker start logstash 2>/dev/null || true
else
  docker run -d \
    --name logstash \
    --network elk-network \
    --restart unless-stopped \
    -p 5044:5044 \
    -p 9600:9600 \
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
if docker ps -a --format '{{.Names}}' | grep -qw '^kibana$'; then
  docker start kibana 2>/dev/null || true
else
  docker run -d \
    --name kibana \
    --network elk-network \
    --restart unless-stopped \
    -p 5601:5601 \
    -e SERVER_HOST=0.0.0.0 \
    -e 'ELASTICSEARCH_HOSTS=["http://elasticsearch:9200"]' \
    docker.elastic.co/kibana/kibana:9.3.1
fi

echo "[*] Waiting for Kibana..."

for i in {1..60}; do
  if curl -fsS http://127.0.0.1:5601/api/status >/dev/null 2>&1; then
    echo "[*] Kibana is ready at http://localhost:5601"
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

echo "[*] Kibana container is running. Access it at http://localhost:5601"  
echo "[*] Logstash container is running. API at http://localhost:9600 and Beats input at port 5044"
echo "[*] Elasticsearch container is running. Access it at http://localhost:9200"
