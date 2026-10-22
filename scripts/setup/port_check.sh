#!/usr/bin/env bash
#
# Docker setup script for Instant Lab
# Maintainer: Swayan Basu
# Repository: https://github.com/swayan-basu/Instant_lab

port_owner() {
    local port="$1"
    local docker_owner=""
    local process_owner=""

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        docker_owner="$(docker ps --filter "publish=${port}" \
            --format '{{.Names}}|{{.Image}}|{{.Status}}' | head -n 1)"
        if [[ -n "$docker_owner" ]]; then
            printf 'container|%s\n' "$docker_owner"
            return 0
        fi
    fi

    if command -v lsof >/dev/null 2>&1; then
        process_owner="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN \
            -F pc 2>/dev/null | awk '
                /^p/ { pid = substr($0, 2) }
                /^c/ { command = substr($0, 2) }
                END {
                    if (pid != "") {
                        printf "%s|%s", pid, command
                    }
                }')"
    fi

    if [[ -z "$process_owner" ]] && command -v ps >/dev/null 2>&1; then
        process_owner="$(ps -eo pid=,args= | awk -v port="$port" '
            /docker-proxy/ && $0 ~ ("-host-port " port "($| )") {
                printf "%s|docker-proxy", $1
                exit
            }')"
    fi

    if [[ -z "$process_owner" ]] && command -v ss >/dev/null 2>&1; then
        process_owner="$(ss -ltnpH "sport = :${port}" 2>/dev/null | sed -n 's/.*users:((("\([^"]*\)".*/\1/p' | head -n 1)"
    fi

    if [[ -z "$process_owner" ]] && command -v netstat >/dev/null 2>&1; then
        process_owner="$(netstat -ltnp 2>/dev/null | awk -v port=":${port}" '$4 ~ port"$" {
            split($7, process, "/")
            if (process[1] != "" && process[1] != "-") {
                printf "%s|%s", process[1], process[2]
                exit
            }
        }')"
    fi

    if [[ -n "$process_owner" ]]; then
        printf 'process|%s\n' "$process_owner"
        return 0
    fi

    return 1
}

describe_port_owner() {
    local port="$1"
    local owner_type owner_details owner_name owner_image owner_status

    if ! IFS='|' read -r owner_type owner_details < <(port_owner "$port"); then
        return 1
    fi

    if [[ "$owner_type" == "container" ]]; then
        IFS='|' read -r owner_name owner_image owner_status <<<"$owner_details"
        printf '%s (container %s, %s)\n' "$owner_name" "$owner_image" "$owner_status"
    else
        IFS='|' read -r owner_name owner_image <<<"$owner_details"
        if [[ -n "$owner_image" ]]; then
            printf '%s (PID %s)\n' "$owner_image" "$owner_name"
        else
            printf 'process PID %s\n' "$owner_name"
        fi
    fi
}

check_port() {
    local port="$1"
    local allowed_container="${2:-}"
    local service_name="${3:-}"
    local owner_type owner_details owner_name

    if ! IFS='|' read -r owner_type owner_details < <(port_owner "$port"); then
        return 0
    fi

    if [[ "$owner_type" == "container" ]]; then
        IFS='|' read -r owner_name _ <<<"$owner_details"
        if [[ -n "$allowed_container" &&
            ( "$owner_name" == "$allowed_container" ||
              "$owner_name" == *"-${allowed_container}-"* ||
              "$owner_name" == *"-${allowed_container}" ) ]]; then
            echo "[*] ${service_name:-$owner_name} is already running on port ${port}; reusing its container."
            return 0
        fi
    fi

    echo "[-] Port ${port} is already in use by $(describe_port_owner "$port")." >&2
    echo "[!] Stop that service or choose a different host port before continuing." >&2
    return 1
}
