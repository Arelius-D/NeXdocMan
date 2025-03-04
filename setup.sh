#!/bin/bash

SCRIPT_NAME="setup.sh"
VERSION="v1.0"

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

log_message "[INFO] Checking for Docker..."
if command -v docker &>/dev/null; then
    log_message "[OK] Docker already installed: $(docker --version)"
    log_message "[OK] Docker Compose: $(docker compose version)"
    exit 0
fi

log_message "[INFO] Installing Docker and Compose..."
curl -sSL https://get.docker.com | sudo sh 2>&1 | sudo tee -a "$LOG_FILE" >/dev/null
if [ $? -ne 0 ]; then
    log_message "[ERROR] Installation failed. Check $LOG_FILE for details."
    exit 1
fi

if ! command -v docker &>/dev/null; then
    log_message "[ERROR] Docker not found after installation. Check $LOG_FILE."
    exit 1
fi

log_message "[SUCCESS] Docker installed: $(docker --version)"
log_message "[SUCCESS] Docker Compose installed: $(docker compose version)"

log_message "[INFO] Setting up $USER for Docker..."
if ! groups "$USER" | grep -q '\bdocker\b'; then
    run_command sudo usermod -aG docker "$USER"
    run_command sudo systemctl restart docker
    if [ "$REFRESHED" = false ]; then
        log_message "[INFO] Refreshing session to apply Docker group membership... (Run with sudo to avoid password prompt)"
        export REFRESHED=true
        exec su - "$USER" -c "$UTILITY_DIR/nexdocman.sh --install"
    fi
    log_message "[OK] $USER now in Docker group."
else
    log_message "[OK] $USER already in Docker group."
fi

log_message "[INFO] Testing Docker..."
if docker run hello-world &>/dev/null; then
    log_message "[SUCCESS] Docker test passed!"
else
    log_message "[ERROR] Docker test failed. Check permissions or daemon status."
    exit 1
fi

exit 0