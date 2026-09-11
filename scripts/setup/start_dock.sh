#!/usr/bin/env bash
#
# Docker setup script for Instant Lab
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

CURRENT_USER="${SUDO_USER:-${USER:-}}"

echo "[+] Installing Docker prerequisites..."

if [[ -z "$CURRENT_USER" ]]; then
    echo "[-] Could not determine the current user."
    exit 1
fi

if [[ "$EUID" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    echo "[-] sudo is required when the script is not run as root."
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "[-] This script requires a Debian-based system with apt-get."
    exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
    SUDO=()
else
    SUDO=(sudo)
fi

if ! command -v docker >/dev/null 2>&1; then
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y docker.io docker-compose git
    echo "[*] Docker installed"
else
    echo "[*] Docker is already installed"
fi

if command -v systemctl >/dev/null 2>&1; then
    if ! "${SUDO[@]}" systemctl is-active --quiet docker; then
        echo "[*] Starting Docker service..."
        "${SUDO[@]}" systemctl start docker
    fi

    "${SUDO[@]}" systemctl enable docker >/dev/null
elif command -v service >/dev/null 2>&1; then
    if ! "${SUDO[@]}" service docker status >/dev/null 2>&1; then
        echo "[*] Starting Docker service..."
        "${SUDO[@]}" service docker start
    fi
else
    echo "[-] Unable to manage the Docker service on this system."
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "[-] Docker is not available after installation."
    exit 1
fi

if ! id -nG "$CURRENT_USER" | grep -qw docker; then
    "${SUDO[@]}" usermod -aG docker "$CURRENT_USER"
    echo "[*] Added $CURRENT_USER to the docker group."
    echo "[*] Log out and back in, or run: newgrp docker"
else
    echo "[*] $CURRENT_USER is already in the docker group."
fi

echo "[+] Docker setup completed."
