#!/bin/bash

UTILITY_NAME="NeXdocMan"
SCRIPT_NAME="nexdocman.sh"
VERSION="v1.4"
UTILITY_VERSION="v1.0.0"
UTILITY_DIR=${UTILITY_DIR:-"$(dirname "$(realpath "$0")")"}
LOG_DIR="/var/log/$UTILITY_NAME"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}"
SYSTEM_DIR="/usr/local/lib/nexdocman"

log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME $VERSION] $message" | sudo tee -a "$LOG_FILE" >/dev/null
    echo "$message"
}

setup_dirs() {
    if [ ! -d "$LOG_DIR" ]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
        sudo chown root:root "$LOG_DIR"
    fi
    if [ ! -f "$LOG_FILE" ]; then
        sudo touch "$LOG_FILE"
        sudo chmod 644 "$LOG_FILE"
        sudo chown root:root "$LOG_FILE"
    fi
    sudo mkdir -p "$SYSTEM_DIR"
    sudo chmod 755 "$SYSTEM_DIR"
    sudo chown root:root "$SYSTEM_DIR"
    for script in "$UTILITY_DIR"/*.sh; do
        if [ -f "$script" ]; then
            sudo chmod +x "$script"
        fi
    done
}

show_versions() {
    echo "$UTILITY_NAME $UTILITY_VERSION"
    for script in "$UTILITY_DIR"/*.sh; do
        if [ -f "$script" ]; then
            script_name=$(grep '^SCRIPT_NAME=' "$script" | cut -d'"' -f2)
            script_version=$(grep '^VERSION=' "$script" | cut -d'"' -f2)
            if [ -n "$script_name" ] && [ -n "$script_version" ]; then
                echo "- $script_name $script_version"
            fi
        fi
    done
}

install_utility() {
    setup_dirs
    for script in purge.sh setup.sh check_update.sh; do
        sudo cp -v "$UTILITY_DIR/$script" "$SYSTEM_DIR/" 2>&1 | while read -r line; do log_message "$line"; done
        if [ ${PIPESTATUS[0]} -ne 0 ]; then
            log_message "[ERROR] Failed to copy $script to $SYSTEM_DIR/$script"
            exit 1
        fi
        sudo chmod +x "$SYSTEM_DIR/$script"
    done

    sed "s|^UTILITY_DIR=.*$|UTILITY_DIR=\"$SYSTEM_DIR\"|" "$UTILITY_DIR/nexdocman.sh" > /tmp/nexdocman.sh
    sudo cp -v /tmp/nexdocman.sh "/usr/local/bin/nexdocman" 2>&1 | while read -r line; do log_message "$line"; done
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_message "[ERROR] Copy failed: /tmp/nexdocman.sh to /usr/local/bin/nexdocman"
        exit 1
    fi
    sudo chmod +x "/usr/local/bin/nexdocman"
    rm -f /tmp/nexdocman.sh
    if [ -f "/usr/local/bin/nexdocman" ] && [ -x "/usr/local/bin/nexdocman" ]; then
        log_message "[SUCCESS] Verified: /usr/local/bin/nexdocman exists and is executable"
        log_message "Utility installed to /usr/local/bin/nexdocman. Run 'nexdocman' to start."
    else
        log_message "[ERROR] /usr/local/bin/nexdocman does not exist or is not executable"
        exit 1
    fi
}

setup_dirs

auto_yes=false
verbose=false
install_docker=false
purge_docker=false
manage_docker=false
initiate_install=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -y) auto_yes=true ;;
        -v) show_versions; exit 0 ;;
        -h) echo "Usage: $UTILITY_NAME [--install|--manage|--purge|--initiate|-v|-h]"; exit 0 ;;
        --verbose) verbose=true ;;
        --install) install_docker=true ;;
        --purge) purge_docker=true ;;
        --manage) manage_docker=true ;;
        --initiate) initiate_install=true ;;
        *) echo "[ERROR] Unknown parameter: $1" | sudo tee -a "$LOG_FILE" >/dev/null; echo "[ERROR] Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

USER=$(whoami)
REFRESHED=${REFRESHED:-false}

show_menu() {
    clear
    echo "🐧 $UTILITY_NAME - Docker and Compose Manager ($UTILITY_VERSION)"
    echo "--------------------------------------------------"
    echo "1. Install Docker & Docker Compose"
    echo "2. Check and Update Docker & Docker Compose"
    echo "3. Create Container Directory"
    echo "4. Purge Docker & Docker Compose"
    echo "0. Exit"
    echo -n "Choose an option [0-4]: "
}

if [ "$install_docker" = true ] || [ "$purge_docker" = true ] || [ "$manage_docker" = true ] || [ "$initiate_install" = true ]; then
    echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION" | sudo tee -a "$LOG_FILE" >/dev/null
    echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION"
    if [ "$purge_docker" = true ] && [ "$manage_docker" = true ]; then
        echo "[ERROR] Cannot use --purge and --manage together!" | sudo tee -a "$LOG_FILE" >/dev/null
        echo "[ERROR] Cannot use --purge and --manage together!"
        exit 1
    fi
    if [ "$install_docker" = true ]; then
        export AUTO_YES="$auto_yes" VERBOSE="$verbose" USER="$USER" LOG_FILE="$LOG_FILE" REFRESHED="$REFRESHED" UTILITY_DIR="$UTILITY_DIR"
        "$UTILITY_DIR/setup.sh"
    elif [ "$purge_docker" = true ]; then
        export AUTO_YES="$auto_yes" VERBOSE="$verbose" USER="$USER" LOG_FILE="$LOG_FILE" UTILITY_DIR="$UTILITY_DIR"
        "$UTILITY_DIR/purge.sh"
    elif [ "$manage_docker" = true ]; then
        export AUTO_YES="$auto_yes" VERBOSE="$verbose" LOG_FILE="$LOG_FILE" UTILITY_DIR="$UTILITY_DIR"
        "$UTILITY_DIR/check_update.sh"
    elif [ "$initiate_install" = true ]; then
        install_utility
    fi
    exit 0
else
    while true; do
        show_menu
        read choice
        case $choice in
            1)
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION" | sudo tee -a "$LOG_FILE" >/dev/null
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION"
                export AUTO_YES="$auto_yes" VERBOSE="$verbose" USER="$USER" LOG_FILE="$LOG_FILE" REFRESHED="$REFRESHED" UTILITY_DIR="$UTILITY_DIR"
                "$UTILITY_DIR/setup.sh"
                ;;
            2)
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION" | sudo tee -a "$LOG_FILE" >/dev/null
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION"
                export AUTO_YES="$auto_yes" VERBOSE="$verbose" LOG_FILE="$LOG_FILE" UTILITY_DIR="$UTILITY_DIR"
                "$UTILITY_DIR/check_update.sh"
                ;;
            3)
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION" | sudo tee -a "$LOG_FILE" >/dev/null
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION"
                echo -n "Enter directory name to create under $HOME: "
                read dir_name
                if [ -n "$dir_name" ]; then
                    dir_path="$HOME/$dir_name"
                    if [ -d "$dir_path" ]; then
                        echo "[INFO] Directory $dir_path is already present." | sudo tee -a "$LOG_FILE" >/dev/null
                        echo "[INFO] Directory $dir_path is already present."
                    else
                        mkdir -p "$dir_path"
                        if [ $? -eq 0 ]; then
                            echo "[SUCCESS] Directory $dir_path created." | sudo tee -a "$LOG_FILE" >/dev/null
                            echo "[SUCCESS] Directory $dir_path created."
                        else
                            echo "[ERROR] Failed to create $dir_path." | sudo tee -a "$LOG_FILE" >/dev/null
                            echo "[ERROR] Failed to create $dir_path."
                        fi
                    fi
                else
                    echo "[ERROR] No directory name provided." | sudo tee -a "$LOG_FILE" >/dev/null
                    echo "[ERROR] No directory name provided."
                fi
                ;;
            4)
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION" | sudo tee -a "$LOG_FILE" >/dev/null
                echo "[INFO] Running $UTILITY_NAME $UTILITY_VERSION"
                export AUTO_YES="$auto_yes" VERBOSE="$verbose" USER="$USER" LOG_FILE="$LOG_FILE" UTILITY_DIR="$UTILITY_DIR"
                "$UTILITY_DIR/purge.sh"
                ;;
            0)
                echo "[INFO] Exiting." | sudo tee -a "$LOG_FILE" >/dev/null
                echo "[INFO] Exiting."
                exit 0
                ;;
            *)
                echo "[ERROR] Invalid option: $choice" | sudo tee -a "$LOG_FILE" >/dev/null
                echo "[ERROR] Invalid option: $choice"
                ;;
        esac
        echo "Press any key to continue..."
        read -n 1 -s
        clear
    done
fi