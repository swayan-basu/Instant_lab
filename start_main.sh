#!/usr/bin/env bash
#
# Welcome to Instant Lab Dashboard
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

set -euo pipefail

# ==========================================
# Base & Writable Data Directory Paths
# ==========================================
# use $SNAP for code/scripts and $SNAP_USER_DATA for data
if [ -n "${SNAP:-}" ]; then
    APP_ROOT="$SNAP"
    export INSTANT_LAB_DATA_DIR="$SNAP_USER_DATA"
else
    APP_ROOT="$(cd "$(dirname "$0")" && pwd)"
    export INSTANT_LAB_DATA_DIR="$APP_ROOT"
fi

TARGETS_DIR="${APP_ROOT}/scripts/targets"
SCANNERS_DIR="${APP_ROOT}/scripts/scanners"
SIEM_DIR="${APP_ROOT}/scripts/siem"
SETUP_DIR="${APP_ROOT}/scripts/setup"

# Ensure writable runtime directories exist
mkdir -p "${INSTANT_LAB_DATA_DIR}/work" \
         "${INSTANT_LAB_DATA_DIR}/.generated" \
         "${INSTANT_LAB_DATA_DIR}/scripts/scanners/msf" \
         "${INSTANT_LAB_DATA_DIR}/scripts/scanners/nuclei-templates"

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

# Dedicated Lab Network Setup
WAZUH_NETWORK_NAME="instant_lab_network"
if ! docker network inspect "$WAZUH_NETWORK_NAME" >/dev/null 2>&1; then
    echo -e "${CLR_INFO}[*] Creating isolated network '${WAZUH_NETWORK_NAME}'...${CLR_RESET}"
    docker network create --driver bridge "$WAZUH_NETWORK_NAME" >/dev/null
    echo -e "${CLR_SUCCESS}[+] Bridge network '${WAZUH_NETWORK_NAME}' established.${CLR_RESET}"
fi

# Helper: Smart Port Availability Check with Container Identification
check_port() {
    local port="$1"
    local service_name="$2"
    local access_url="$3"
    local in_use=0

    if command -v ss >/dev/null 2>&1 && ss -H -ltn >/dev/null 2>&1; then
        if ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
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
    fi

    if [[ "$in_use" -eq 1 ]]; then
        echo -e "${CLR_SUCCESS}[*] ${service_name} is already running and active!${CLR_RESET}"
        echo -e "${CLR_INFO}[*] Access it directly at: ${access_url}${CLR_RESET}"
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
        if check_port 8080 "DVWA" "http://localhost:8080"; then
            echo -e "${CLR_DANGER}[+] Launching DVWA target at http://localhost:8080...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_dvwa.sh"
        fi
        ;;
      5)
        if check_port 3000 "OWASP Juice Shop" "http://localhost:3000"; then
            echo -e "${CLR_DANGER}[+] Launching OWASP Juice Shop target at http://localhost:3000...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_juice.sh"
        fi
        ;;
      6)
        if check_port 8200 "bWAPP" "http://localhost:8200/install.php"; then
            echo -e "${CLR_WARN}[+] Initializing bWAPP target...${CLR_RESET}"
            bash "${TARGETS_DIR}/start_bwapp.sh"
        fi
        ;;
      7)
        echo -e "${CLR_WARN}[+] Initializing Elastic Stack (ELK)...${CLR_RESET}"
        bash "${SIEM_DIR}/start_elk.sh"
        ;;
      8)
        if check_port 7608 "Wazuh Dashboard" "https://localhost:7608"; then
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
