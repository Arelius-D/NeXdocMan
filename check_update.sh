#!/bin/bash

SCRIPT_NAME="check_update.sh"
VERSION="v0.3"

log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME $VERSION] $message" | sudo tee -a "$LOG_FILE" >/dev/null
    echo "$message"
}

run_command() {
    if [ "$VERBOSE" = true ]; then
        "$@" 2>&1 | sudo tee -a "$LOG_FILE"
        return ${PIPESTATUS[0]}
    else
        "$@" 2>&1 | sudo tee -a "$LOG_FILE" >/dev/null
        return ${PIPESTATUS[0]}
    fi
}

log_message "[INFO] Checking for Docker and Docker Compose..."
if ! dpkg -l | grep -q docker; then
    log_message "[WARNING] Neither Docker nor Docker Compose is installed."
    exit 0
fi

docker_ver=$(docker --version)
compose_ver=$(docker compose version)
log_message "[INFO] Current Docker: $docker_ver"
log_message "[INFO] Current Docker Compose: $compose_ver"

log_message "[INFO] Checking for updates..."
run_command sudo apt update
upgradable=$(apt list --upgradable 2>/dev/null | grep -E "docker|containerd" || true)
if [ -z "$upgradable" ]; then
    log_message "[INFO] Docker and Docker Compose are already up-to-date."
else
    if [ "$AUTO_YES" = false ]; then
        log_message "[INFO] Updates available:"
        echo "$upgradable" | while read -r line; do log_message "[INFO] $line"; done
        read -p "[INFO] Install updates to Docker & Docker Compose? (y/N): " update_choice
    fi
    if [[ "$AUTO_YES" = true || "$update_choice" =~ ^[Yy]$ ]]; then
        run_command sudo apt upgrade -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin
        if [ $? -ne 0 ]; then
            log_message "[ERROR] Update failed. Check $LOG_FILE."
            exit 1
        fi
        new_docker_ver=$(docker --version | cut -d' ' -f3- | sed 's/,//')
        new_compose_ver=$(docker compose version | cut -d' ' -f4-)
        if [ "$docker_ver" != "Docker version $new_docker_ver" ] || [ "$compose_ver" != "Docker Compose version $new_compose_ver" ]; then
            log_message "[SUCCESS] Docker updated to $new_docker_ver"
            log_message "[SUCCESS] Docker Compose updated to $new_compose_ver"
        else
            log_message "[INFO] No version changes detected after update."
        fi
    else
        log_message "[INFO] Update installation skipped."
    fi
fi

exit 0