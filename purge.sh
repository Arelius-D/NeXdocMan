#!/bin/bash

SCRIPT_NAME="purge.sh"
VERSION="v0.4"

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
if dpkg -l | grep -q docker || dpkg -l | grep -q docker-compose; then
    if [ "$AUTO_YES" = false ]; then
        log_message "[WARNING] This will COMPLETELY PURGE Docker & Docker Compose."
        read -p "[WARNING] Type 'YES' to continue: " final_confirm
        [[ "$final_confirm" != "YES" ]] && { log_message "[INFO] Purge cancelled."; exit 0; }
    fi

    log_message "[INFO] Stopping Docker service..."
    run_command sudo systemctl stop docker
    run_command sudo systemctl disable docker

    log_message "[INFO] Checking for lingering processes..."
    if pgrep -x "dockerd" &>/dev/null; then
        log_message "[WARNING] Killing Docker daemon..."
        run_command sudo pkill -9 dockerd
    fi

    log_message "[INFO] Uninstalling Docker and Compose packages..."
    run_command sudo apt update
    run_command sudo apt remove --purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin
    if [ $? -ne 0 ]; then
        log_message "[ERROR] Purge failed. Check $LOG_FILE."
        exit 1
    fi

    log_message "[INFO] Cleaning up Docker data..."
    run_command sudo rm -rf /var/lib/docker /var/lib/containerd ~/.docker /usr/local/bin/docker-compose

    log_message "[INFO] Removing $USER from Docker group..."
    run_command sudo gpasswd -d "$USER" docker

    if getent group docker >/dev/null; then
        log_message "[INFO] Removing Docker group..."
        run_command sudo groupdel docker
    fi

    log_message "[INFO] Cleaning up packages..."
    run_command sudo apt autoremove -y
    run_command sudo apt autoclean

    log_message "[SUCCESS] Docker and Docker Compose purged!"
else
    log_message "[OK] Nothing to purge."
fi

exit 0