#!/usr/bin/env bash
#
# Welcome to Instant Lab Dashboard
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

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

clear
echo -e "${CLR_MUTED}============================================================${CLR_RESET}"
echo -e "${CLR_SUCCESS}[*]   /^_^\\  INSTANT LAB — RASPBERRY PI & DOCKER  /^_^\\   ${CLR_RESET}"
echo -e "${CLR_MUTED}============================================================${CLR_RESET}"
echo -e "${CLR_INFO}[*] Manage test systems, security tools, and monitoring services${CLR_RESET}\n"

# 1. Docker Installation Check
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${CLR_WARN}[!] Docker is not installed on this host.${CLR_RESET}"
    read -r -p "Run installation setup script now? (y/n): " install_ans
    if [[ "$install_ans" =~ ^[Yy]$ ]]; then
        bash "${SETUP_DIR}/start_dock.sh"
    else
        echo -e "${CLR_DANGER}[-] Cannot proceed without Docker engine. Exiting.${CLR_RESET}"
        exit 1
    fi
fi

# 2. Docker Daemon Status Check
if ! docker info >/dev/null 2>&1; then
    echo -e "${CLR_DANGER}[-] Error: Docker daemon is inactive or user lacks group rights.${CLR_RESET}"
    echo -e "${CLR_WARN}[*] Fix: Run 'sudo systemctl start docker' or add user to 'docker' group.${CLR_RESET}"
    exit 1
fi

echo -e "${CLR_SUCCESS}[+] Docker daemon operational.${CLR_RESET}"

# 3. Dedicated Lab Network Setup
if ! docker network inspect instant_lab_network >/dev/null 2>&1; then
    echo -e "${CLR_INFO}[*] Creating isolated network 'instant_lab_network'...${CLR_RESET}"
    docker network create instant_lab_network >/dev/null
    echo -e "${CLR_SUCCESS}[+] Bridge network 'instant_lab_network' established.${CLR_RESET}"
fi

# Helper: Port Availability Check
check_port() {
    local port="$1"
    local in_use=0

    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -qE "(:|\])${port}[[:space:]]"; then
            in_use=1
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -Pi :"$port" -sTCP:LISTEN -t >/dev/null 2>&1; then
            in_use=1
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -qE "(:|\])${port}[[:space:]]"; then
            in_use=1
        fi
    else
    echo -e "${CLR_WARN}[!] Cannot check port ${port}.${CLR_RESET}"
    echo -e "${CLR_WARN}[*] Install a port-checking tool with:${CLR_RESET}"
    echo -e "${CLR_WARN}    sudo apt install iproute2${CLR_RESET}"
    fi

    if [[ "$in_use" -eq 1 ]]; then
        echo -e "${CLR_DANGER}[!] Port Conflict: Port ${port} is already in use.${CLR_RESET}"
        echo -e "${CLR_WARN}[!] Free the port before deploying this service.${CLR_RESET}"
        return 1
    fi

    return 0
}

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
    echo "    7. ELK Stack (Ports: 9200, 5601)"
    echo "    8. Wazuh Stack (Manager, Indexer, Dashboard)"
    echo "    9. Wazuh Agent"
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
        if check_port 8080; then
            echo -e "${CLR_DANGER}[+] Launching DVWA target at http://localhost:8080...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_dvwa.sh"
        fi
        ;;
      5)
        if check_port 3000; then
            echo -e "${CLR_DANGER}[+] Launching OWASP Juice Shop target at http://localhost:3000...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_juice.sh"
        fi
        ;;
      6)
        if check_port 8200; then
            echo -e "${CLR_WARN}[+] Initializing bWAPP target...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_bwapp.sh"
        fi
        ;;
      7)
        if check_port 9200 && check_port 5601; then
            echo -e "${CLR_WARN}[+] Initializing Elastic Stack (ELK)...${CLR_RESET}"
            bash "${SIEM_DIR}/start_elk.sh"
        fi
        ;;
      8)
        if check_port 1514 && check_port 1515 && check_port 55000; then
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
