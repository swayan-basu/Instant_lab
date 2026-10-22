#!/usr/bin/env bash
#
# Welcome to Instant Lab Dashboard
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/scripts/setup/docker_env.sh"
source "$(cd "$(dirname "$0")" && pwd)/scripts/setup/port_check.sh"

# ==========================================
# Base & Subdirectory Paths
# ==========================================
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGETS_DIR="${BASE_DIR}/scripts/targets"
SCANNERS_DIR="${BASE_DIR}/scripts/scanners"
SIEM_DIR="${BASE_DIR}/scripts/siem"
SETUP_DIR="${BASE_DIR}/scripts/setup"

# ==========================================
# Terminal Color Palette
# ==========================================
CLR_RESET="\033[0m"
CLR_SUCCESS="\033[38;2;35;134;54m"    # Terminal Green (Active / Healthy)
CLR_DANGER="\033[38;2;218;54;51m"     # Crimson Red (Targets / Errors)
CLR_INFO="\033[38;2;56;139;253m"      # Cobalt Blue (Scanners / Net)
CLR_WARN="\033[38;2;210;153;34m"      # Amber Gold (Warnings / Status)
CLR_MUTED="\033[38;2;139;148;158m"    # Slate Gray (Subtexts / Borders)

clear 2>/dev/null || true
echo -e "${CLR_MUTED}============================================================${CLR_RESET}"
echo -e "${CLR_SUCCESS}[*]   /^_^\\  INSTANT LAB — RASPBERRY PI & DOCKER  /^_^\\   ${CLR_RESET}"
echo -e "${CLR_MUTED}============================================================${CLR_RESET}"
echo -e "${CLR_INFO}[*] Manage test systems, security tools, and monitoring services${CLR_RESET}\n"

# 1. Docker Installation Check
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${CLR_DANGER}[-] System Docker command line tool is not available.${CLR_RESET}"
    echo -e "${CLR_WARN}[*] Install Docker on the host before starting Instant Lab.${CLR_RESET}"
    exit 1
fi

# 2. Docker Daemon Status Check
if ! docker info >/dev/null 2>&1; then
    echo -e "${CLR_DANGER}[-] Cannot communicate with Docker daemon.${CLR_RESET}"
    echo -e "${CLR_WARN}[*] Make sure the Docker service is active and execute with sudo:${CLR_RESET}"
    echo -e "${CLR_WARN}    sudo /snap/bin/instant-lab${CLR_RESET}"
    exit 1
fi

echo -e "${CLR_SUCCESS}[+] Docker daemon operational.${CLR_RESET}"

# 3. Dedicated Lab Network Setup
if ! docker network inspect instant_lab_network >/dev/null 2>&1; then
    echo -e "${CLR_INFO}[*] Creating isolated network 'instant_lab_network'...${CLR_RESET}"
    docker network create instant_lab_network >/dev/null
    echo -e "${CLR_SUCCESS}[+] Bridge network 'instant_lab_network' established.${CLR_RESET}"
fi

# Initial Container Check
read -r -p "Inspect running lab containers? (y/n): " check_status
if [[ "$check_status" =~ ^[Yy]$ ]]; then
    bash "${SETUP_DIR}/status.sh" || docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
fi

# ==========================================
# Main Menu Loop
# ==========================================
while true; do
    echo ""
    echo -e "${CLR_MUTED}------------------------------------------------------------${CLR_RESET}"
    echo -e "${CLR_INFO}Select a service to start:${CLR_RESET}"
    echo -e "${CLR_INFO}  [ CLI Scanners & Assessment ]${CLR_RESET}"
    echo "    1. Parrot Security OS"
    echo "    2. Kali Linux Core"
    echo "    3. Nuclei Vulnerability Scanner"
    echo -e "${CLR_DANGER}  [ Vulnerable Targets ]${CLR_RESET}"
    echo "    4. DVWA (Web Port: 8080)"
    echo "    5. OWASP Juice Shop (Web Port: 3000)"
    echo "    6. bWAPP (Web Port: 8200)"
    echo -e "${CLR_WARN}  [ SOC & SIEM Stack ]${CLR_RESET}"
    echo "    7. ELK Stack (Ports: 9201, 5602, 5045, 9601)"
    echo "    8. Wazuh Stack (Dashboard: 7608)"
    echo "    9. Wazuh Agent (Docker network only)"
    echo -e "${CLR_MUTED}  [ Lab Control ]${CLR_RESET}"
    echo "    10. Container Status Monitor"
    echo "    0. Exit"
    echo -e "${CLR_MUTED}------------------------------------------------------------${CLR_RESET}"

    read -r -p "Select Option [0-10]: " choice

    case "$choice" in
      1)
        echo -e "${CLR_INFO}[+] Initializing ParrotSec CLI environment...${CLR_RESET}"
        bash "${SCANNERS_DIR}/start_parrot.sh"
        ;;
      2)
        echo -e "${CLR_INFO}[+] Launching Kali Linux container...${CLR_RESET}"
        bash "${SCANNERS_DIR}/start_rkali.sh"
        ;;
      3)
        echo -e "${CLR_INFO}[+] Starting Nuclei vulnerability scanner...${CLR_RESET}"
        bash "${SCANNERS_DIR}/start_nuclei.sh"
        ;;
      4)
        if check_port 8080 instant_dvwa DVWA; then
            echo -e "${CLR_DANGER}[+] Launching DVWA target at http://localhost:8080...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_dvwa.sh"
        fi
        ;;
      5)
        if check_port 3000 juice-shop "Juice Shop"; then
            echo -e "${CLR_DANGER}[+] Launching OWASP Juice Shop target at http://localhost:3000...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_juice.sh"
        fi
        ;;
      6)
        if check_port 8200 instant_bwapp bWAPP; then
            echo -e "${CLR_WARN}[+] Initializing bWAPP target...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_bwapp.sh"
        fi
        ;;
      7)
        if check_port 9201 elasticsearch Elasticsearch &&
           check_port 5602 kibana Kibana &&
           check_port 5045 logstash Logstash &&
           check_port 9601 logstash Logstash; then
            echo -e "${CLR_WARN}[+] Initializing Elastic Stack (ELK)...${CLR_RESET}"
            bash "${SIEM_DIR}/start_elk.sh"
        fi
        ;;
      8)
        if check_port "${WAZUH_DASHBOARD_HOST_PORT:-7608}" wazuh.dashboard "Wazuh dashboard"; then
            echo -e "${CLR_WARN}[+] Deploying Wazuh SIEM cluster...${CLR_RESET}"
            bash "${SIEM_DIR}/start_wazuh.sh"
        fi
        ;;
      9)
        echo -e "${CLR_WARN}[+] Registering Wazuh Agent...${CLR_RESET}"
        bash "${SIEM_DIR}/start_wazuh_agent.sh"
        ;;
      10)
        echo -e "${CLR_SUCCESS}[*] Live Container Status:${CLR_RESET}"
        bash "${SETUP_DIR}/status.sh" || docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        ;;
      0)
        echo -e "${CLR_SUCCESS}[*] Terminating menu session. Containers continue running.${CLR_RESET}"
        exit 0
        ;;
      *)
        echo -e "${CLR_DANGER}[-] Invalid selection. Choose a valid menu index.${CLR_RESET}"
        ;;
    esac
done
