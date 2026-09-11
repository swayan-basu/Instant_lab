#!/usr/bin/env bash
#
# Instant Lab status script
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed or not available in PATH." >&2
    exit 1
fi

echo " =__= Instant Lab status =__= "
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

read -r -n 1 -p "Do you want to stop and remove all containers? [y/N] " answer || answer="n"
printf '\n'

if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Stopping and removing all containers..."

    running_containers=()
    all_containers=()

    mapfile -t running_containers < <(docker ps -q)
    mapfile -t all_containers < <(docker ps -a -q)

    if ((${#running_containers[@]})); then
        docker stop "${running_containers[@]}" >/dev/null
    fi

    if ((${#all_containers[@]})); then
        docker rm "${all_containers[@]}" >/dev/null
    fi

    if docker ps -q | grep -q .; then
        echo "Error: Some containers are still running after attempted cleanup." >&2
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        exit 1
    fi

    echo "All containers stopped and removed."
else
    echo "Don't worry, no changes were made to the containers."
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
fi
