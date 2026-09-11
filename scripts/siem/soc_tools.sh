#!/usr/bin/env bash
#
# SOC tools installation script
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

ASSUME_YES=0

case "${1:-}" in
    -y|--yes)
        ASSUME_YES=1
        ;;
esac

if [[ "$ASSUME_YES" -eq 1 ]]; then
    answer="y"
else
    read -r -n 1 -p "Want to install security packages in the container? (y/n) " answer || answer="n"
    printf '\n'
fi

if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "[*] Skipping package installation."
    exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "[!] apt-get is not available; this does not appear to be a Debian-based container." >&2
    exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
    APT_PREFIX=()
elif command -v sudo >/dev/null 2>&1; then
    APT_PREFIX=(sudo)
else
    echo "[!] Run this script as root or install sudo." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

packages=(
    python3
    python3-pip
    nano
    wget
    curl
    hashcat
    net-tools
    john
    tshark
    nikto
    hydra
    gobuster
    sqlmap
    tcpdump
    git
    postgresql
    metasploit-framework
    dnsmap
    recon-ng
    sslscan
)

echo "[+] Updating package lists..."
"${APT_PREFIX[@]}" apt-get update

echo "[+] Checking package availability..."

available_packages=()
missing_packages=()

for package in "${packages[@]}"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
        available_packages+=("$package")
    else
        missing_packages+=("$package")
    fi
done

if ((${#missing_packages[@]})); then
    printf '[!] Unavailable packages: %s\n' "${missing_packages[*]}" >&2
fi

if ((${#available_packages[@]})); then
    echo "[+] Installing available security packages..."
    "${APT_PREFIX[@]}" apt-get install -y --no-install-recommends \
        "${available_packages[@]}"
else
    echo "[!] None of the requested packages are available." >&2
    exit 1
fi

echo "[+] Cleaning APT cache..."
"${APT_PREFIX[@]}" apt-get clean

echo "[+] Removing APT lists..."
"${APT_PREFIX[@]}" rm -rf /var/lib/apt/lists/*

echo "[+] Package installation complete."
