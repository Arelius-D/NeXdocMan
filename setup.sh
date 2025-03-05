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
if ! command -v docker &>/dev/null; then
    log_message "[INFO] Installing Docker and Compose..."
    curl -sSL https://get.docker.com | sudo sh 2>&1 | sudo tee -a "$LOG_FILE" >/dev/null
    if [ $? -ne 0 ]; then
        log_message "[ERROR] Docker installation failed. Check $LOG_FILE for details."
        exit 1
    fi

    if ! command -v docker &>/dev/null; then
        log_message "[ERROR] Docker not found after installation. Check $LOG_FILE."
        exit 1
    fi

    log_message "[SUCCESS] Docker installed: $(docker --version)"
    log_message "[SUCCESS] Docker Compose installed: $(docker compose version)"
else
    log_message "[OK] Docker already installed: $(docker --version)"
    log_message "[OK] Docker Compose: $(docker compose version)"
fi

log_message "[INFO] Verifying Docker group exists..."
if ! getent group docker >/dev/null; then
    log_message "[ERROR] Docker group not found. Check $LOG_FILE."
    exit 1
fi

log_message "[INFO] Setting up $USER for Docker..."
if ! groups "$USER" | grep -q '\bdocker\b'; then
    run_command sudo usermod -aG docker "$USER"
    run_command sudo systemctl restart docker
    # Wait for Docker daemon to be ready
    log_message "[INFO] Waiting for Docker daemon to be ready..."
    for i in {1..30}; do
        if systemctl is-active --quiet docker; then
            log_message "[INFO] Docker service is active."
            if sudo docker info >/dev/null 2>&1; then
                log_message "[INFO] Docker daemon is ready."
                break
            fi
        fi
        log_message "[INFO] Waiting for Docker daemon ($i/30)..."
        sleep 2
    done
    if ! systemctl is-active --quiet docker; then
        log_message "[ERROR] Docker service not active after waiting. Check daemon status:"
        systemctl status docker | sudo tee -a "$LOG_FILE"
        journalctl -u docker --no-pager | tail -50 | sudo tee -a "$LOG_FILE"
        log_message "[INFO] Try manually starting Docker: 'sudo systemctl start docker'"
        exit 1
    fi
    if ! sudo docker info >/dev/null 2>&1; then
        log_message "[ERROR] Cannot connect to Docker daemon as root. Check daemon status:"
        systemctl status docker | sudo tee -a "$LOG_FILE"
        journalctl -u docker --no-pager | tail -50 | sudo tee -a "$LOG_FILE"
        log_message "[INFO] Try manually starting Docker: 'sudo systemctl start docker'"
        exit 1
    fi
    log_message "[INFO] Group membership updated."
    log_message "[INFO] To use Docker without sudo, run 'newgrp docker' to apply changes in this session."
    log_message "[INFO] Alternatively, start a new terminal session or log out and back in."
    log_message "[OK] $USER added to Docker group."
else
    log_message "[OK] $USER already in Docker group."
    # Check if group is active in the current session
    if ! id -nG | grep -qw "docker"; then
        log_message "[INFO] Docker group not active in this session."
        log_message "[INFO] Run 'newgrp docker' to apply changes, or start a new terminal session."
        exit 0
    fi
    # Test Docker since user is in the group and it's active
    log_message "[INFO] Testing Docker..."
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_message "[SUCCESS] Docker test passed!"
    else
        log_message "[WARNING] Docker test failed. Run 'newgrp docker' to apply changes, or log out and back in."
        journalctl -u docker --no-pager | tail -50 | sudo tee -a "$LOG_FILE"
        exit 1
    fi
fi

log_message "[INFO] Docker installation complete."
exit 0
