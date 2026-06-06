#!/bin/bash

# Configuration
UTILITY_NAME="NeXdocMan"
SCRIPT_FILE_NAME=$(basename "$0")
SCRIPT_NAME=$(basename "$0" .sh)
VERSION="v3.0"
UTILITY_DIR=${UTILITY_DIR:-"$(dirname "$(realpath "$0")")"}
LOG_DIR="/var/log/$UTILITY_NAME"
LOG_FILE="$LOG_DIR/${SCRIPT_NAME}.log"
CRON_LOG_FILE="$LOG_DIR/${SCRIPT_NAME}_cron.log"
SYSTEM_DIR="/usr/local/lib/nexdocman"
CFG_FILE="$SYSTEM_DIR/${SCRIPT_NAME}.cfg"

# Global variables
AUTO_YES=false
VERBOSE=false
ACTUAL_USER="${SUDO_USER:-$(whoami)}"
REFRESHED=${REFRESHED:-false}

# Default Config values
ENABLE_AUTO_CLEANUP=true
CLEANUP_CRON="0 3 */2 * *"
LOG_LEVEL="INFO"
LOGPRUNE_ENABLED=true
LOGPRUNE_MAX_AGE_DAYS=7

ENABLE_AUTO_IMAGE_UPDATE=false
IMAGE_UPDATE_CRON="0 4 * * 0"
EXCLUDE_CONTAINERS=""

if [ -f "$CFG_FILE" ]; then
    source "$CFG_FILE"
fi

display_status() {
    local DEFAULT_NETWORKS="bridge host none"

    if [[ -n "$(sudo docker ps -q)" ]]; then
        echo ""
        echo "[INFO] Running Containers:"
        sudo docker ps --format '  {{.Names}}\t{{.Status}}' | column -t
    else
        echo "[INFO] No running containers"
    fi

    echo ""

    if [[ -n "$(sudo docker ps -a -q --filter 'status=exited' --filter 'status=paused')" ]]; then
        echo "[INFO] Other Containers:"
        sudo docker ps -a --filter 'status=exited' --filter 'status=paused' --format '  {{.Names}}\t{{if eq .State "exited"}}Exited{{else if eq .State "paused"}}Paused{{end}}' | awk '{printf "  %-15s (%s)\n", $1, $2}' | column -t
    else
        echo "[INFO] No exited or paused containers"
    fi

    echo ""

    if [[ -n "$(sudo docker images -q -f dangling=true)" ]]; then
        echo "[INFO] Unused Images:"
        sudo docker images -f "dangling=true" --format '  Repository: {{.Repository}}, Tag: {{.Tag}}, ID: {{.ID}}'
    else
        echo "[INFO] No unused images"
    fi

    echo ""

    if [[ -n "$(sudo docker volume ls -qf dangling=true)" ]]; then
        echo "[INFO] Unused Volumes:"
        sudo docker volume ls -qf dangling=true --format '  Name: {{.Name}}'
    else
        echo "[INFO] No unused volumes"
    fi

    echo ""

    local all_networks=$(sudo docker network ls --format '{{.Name}}')
    local used_networks=$(sudo docker ps --format '{{.Networks}}' | tr ',' '\n' | sort | uniq)
    local unused_networks=$(comm -23 <(echo "$all_networks" | sort) <(echo "$used_networks" | sort) | grep -Ev "^(${DEFAULT_NETWORKS// /|})$")
    if [[ -n "$unused_networks" ]]; then
        echo "[INFO] Unused Networks:"
        echo "$unused_networks" | while read -r network; do
            echo "  Name: $network, Driver: $(sudo docker network inspect $network --format '{{.Driver}}')"
        done
    else
        echo "[INFO] No unused networks"
    fi
}

level_to_num() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO) echo 1 ;;
        WARNING) echo 2 ;;
        ERROR) echo 3 ;;
        *) echo 1 ;;
    esac
}

is_excluded() {
    local c_name="$1"
    local img_name="$2"

    [ -z "${EXCLUDE_CONTAINERS}" ] && return 1

    local exclude_clean="${EXCLUDE_CONTAINERS//,/ }"

    for item in $exclude_clean; do
        if [[ "$c_name" == $item ]] || [[ "$img_name" == $item ]]; then
            return 0
        fi
    done
    return 1
}

log_message() {
    local level="INFO"
    local message="$1"

    if [[ "$message" =~ ^\[(DEBUG|INFO|WARNING|ERROR)\](.*) ]]; then
        filter_level="${BASH_REMATCH[1]}"
    else
        filter_level="INFO"
    fi

    local current_level_num=$(level_to_num "${LOG_LEVEL:-INFO}")
    local msg_level_num=$(level_to_num "$filter_level")

    if [ "$msg_level_num" -ge "$current_level_num" ]; then
        local formatted_msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME $VERSION] ${message}"
        echo "$formatted_msg" | sudo tee -a "$LOG_FILE"
    fi
}

run_command() {
    local temp_out
    temp_out=$(mktemp)
    
    if [ "$VERBOSE" = true ]; then
        "$@" 2>&1 | tee "$temp_out"
    else
        "$@" > "$temp_out" 2>&1
    fi
    local exit_code=${PIPESTATUS[0]}
    
    if [ "$exit_code" -ne 0 ]; then
        log_message "[ERROR] Command failed with exit code $exit_code: $*"
        while IFS= read -r line; do
            [ -n "$line" ] && log_message "[ERROR]   $line"
        done < "$temp_out"
    elif [ "$(level_to_num "$LOG_LEVEL")" -le 0 ]; then
        log_message "[DEBUG] Executing: $*"
        while IFS= read -r line; do
            [ -n "$line" ] && log_message "[DEBUG]   $line"
        done < "$temp_out"
    fi
    rm -f "$temp_out"
    return $exit_code
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
    if [ ! -f "$CRON_LOG_FILE" ]; then
        sudo touch "$CRON_LOG_FILE"
        sudo chmod 644 "$CRON_LOG_FILE"
        sudo chown root:root "$CRON_LOG_FILE"
    fi

    if [ -f "$LOG_DIR/cron.log" ] && [ "$LOG_DIR/cron.log" != "$CRON_LOG_FILE" ]; then
        log_message "[INFO] Migrating legacy log file: $LOG_DIR/cron.log -> ${CRON_LOG_FILE}.bak"
        if [ -f "${CRON_LOG_FILE}.bak" ]; then
            sudo bash -c "cat '$LOG_DIR/cron.log' >> '${CRON_LOG_FILE}.bak'"
            sudo rm -f "$LOG_DIR/cron.log"
        else
            sudo mv "$LOG_DIR/cron.log" "${CRON_LOG_FILE}.bak"
        fi
    fi
}

manage_configuration() {
    sudo mkdir -p "$SYSTEM_DIR"
    sudo chmod 755 "$SYSTEM_DIR"
    sudo chown root:root "$SYSTEM_DIR"

    if [ -f "$CFG_FILE" ]; then
        log_message "[INFO] Existing configuration found. Creating backup..."
        sudo cp "$CFG_FILE" "${CFG_FILE}.bak"
        log_message "[INFO] Backup created at ${CFG_FILE}.bak"
    fi
    
    local exclude_line
    if [ -n "$EXCLUDE_CONTAINERS" ]; then
        exclude_line="EXCLUDE_CONTAINERS=\"$EXCLUDE_CONTAINERS\""
    else
        exclude_line="#EXCLUDE_CONTAINERS=\"\""
    fi

    sudo bash -c "cat > $CFG_FILE" <<EOF
# ==============================================================================
# $UTILITY_NAME Configuration File
# Auto-generated by $SCRIPT_FILE_NAME ($VERSION)
# ==============================================================================

# [ENABLE_AUTO_CLEANUP]
# Enable or disable the automated Docker system prune and cleanup cron job.
# Set to 'true' to enable, 'false' to disable.
ENABLE_AUTO_CLEANUP=$ENABLE_AUTO_CLEANUP

# [CLEANUP_CRON]
# Schedule for the automated cleanup using standard CRON format.
# Default: '0 3 */2 * *' (Every 2 days at 3:00 AM)
CLEANUP_CRON="$CLEANUP_CRON"

# [ENABLE_AUTO_IMAGE_UPDATE]
# Enable or disable automated pulling and recreation of Docker containers.
# Set to 'true' to enable, 'false' to disable.
ENABLE_AUTO_IMAGE_UPDATE=$ENABLE_AUTO_IMAGE_UPDATE

# [IMAGE_UPDATE_CRON]
# Schedule for the automated image updater using standard CRON format.
# Default: '0 4 * * 0' (Every Sunday at 4:00 AM)
IMAGE_UPDATE_CRON="$IMAGE_UPDATE_CRON"

# [EXCLUDE_CONTAINERS]
# Comma-separated list of container names, image names, or glob patterns to
# exclude from automated updates. Uncomment and define to activate.
# Example: EXCLUDE_CONTAINERS="pihole,production_db,mysql:8.0,db_*"
$exclude_line

# [LOG_FILE]
# The primary log file where operational events are recorded.
LOG_FILE="$LOG_FILE"

# [CRON_LOG_FILE]
# The log file where cron execution output is redirected.
CRON_LOG_FILE="$CRON_LOG_FILE"

# [LOG_LEVEL]
# Define the verbosity of the logging output written to the primary log file.
# Options: DEBUG, INFO, WARNING, ERROR
LOG_LEVEL="$LOG_LEVEL"

# [LOGPRUNE]
# Automatically clean old entries from the log files.
LOGPRUNE_ENABLED=$LOGPRUNE_ENABLED
LOGPRUNE_MAX_AGE_DAYS=$LOGPRUNE_MAX_AGE_DAYS
EOF
    sudo chmod 644 "$CFG_FILE"
    log_message "[INFO] Configuration saved to $CFG_FILE"
}

show_versions() {
    echo "$UTILITY_NAME $VERSION"
}

show_help() {
    echo "========================================================================="
    echo " 🐳 $UTILITY_NAME ($VERSION) - Intelligent Docker Orchestrator"
    echo "========================================================================="
    echo ""
    echo "USAGE:"
    echo "  $SCRIPT_NAME [OPTIONS]"
    echo ""
    echo "DESCRIPTION:"
    echo "  $UTILITY_NAME is an intelligent manager for Docker and Docker Compose."
    echo "  It handles installation, updates, scheduled system pruning, and"
    echo "  comprehensive teardowns."
    echo ""
    echo "OPTIONS:"
    echo "  [General]"
    echo "  -h, --help                      Show this comprehensive help message and exit."
    echo "  -v, --version                   Show utility and script version."
    echo "  -y, --yes                       Auto-confirm all prompts (Non-interactive mode)."
    echo "  -V, --verbose                   Run operations with verbose output to terminal."
    echo ""
    echo "  [Deployment & Removal]"
    echo "  -d, --deploy                    Initialize directories, config, and deploy $UTILITY_NAME globally."
    echo "  -r, --remove                    Uninstall $UTILITY_NAME, its logs, configs, and schedules entirely."
    echo ""
    echo "  [Docker Operations]"
    echo "  -i, --install                   Install Docker and Docker Compose and set up groups."
    echo "  -s, --status                    Display Docker and resource status."
    echo "  -m, --manage                    Check for Docker and Compose updates and apply them."
    echo "  -k, --check-images [target]     Audit local Docker images (Read-only). Optionally target a specific container/image."
    echo "  -u, --update-images [target]    Audit local Docker images and pull updates. Optionally target a specific container/image."
    echo "  -c, --cleanup                   Manually trigger a deep Docker system prune."
    echo "  -C, --configure-cron            Apply or Reload the automated schedules from $CFG_FILE."
    echo "  -p, --purge                     Completely uninstall Docker, Compose, and wipe all data."
    echo "  -U, --update-utility            Check for and apply updates to NeXdocMan utility."
    echo ""
    echo "EXAMPLES:"
    echo "  sudo $SCRIPT_NAME -d              # First-time setup on a new server"
    echo "  sudo $SCRIPT_NAME -i -y           # Install Docker cleanly with no prompts"
    echo "  $SCRIPT_NAME -s                   # Display Docker and resource status"
    echo "  $SCRIPT_NAME -c                   # Trigger an immediate runtime prune"
    echo "  $SCRIPT_NAME -r -y                # Uninstall $UTILITY_NAME but leave Docker running"
    echo "  sudo $SCRIPT_NAME -p -y           # Nuke and pave the Docker system silently"
    echo ""
    echo "For advanced configuration (scheduling, log levels), edit: $CFG_FILE"
}

setup_cron() {
    log_message "[INFO] Applying cron schedules from configuration..."

    if [[ "$ENABLE_AUTO_CLEANUP" == "true" || "$ENABLE_AUTO_CLEANUP" == true ]]; then
        local cron_cmd="$CLEANUP_CRON /usr/local/bin/$SCRIPT_NAME --cleanup >> $CRON_LOG_FILE 2>&1"
        local current_crontab
        current_crontab=$(sudo crontab -l 2>/dev/null || true)
        
        local new_crontab=$(echo "$current_crontab" | grep -vF "/usr/local/bin/$SCRIPT_NAME --cleanup")
        new_crontab+=$'\n'"$cron_cmd"
        
        if ! echo "$current_crontab" | grep -qF "$cron_cmd"; then
            echo "$new_crontab" | sudo crontab -
            log_message "[INFO] SUCCESS: Cleanup schedule updated ($CLEANUP_CRON)."
        else
            log_message "[INFO] Cleanup schedule is already up to date."
        fi
    else
        local current_crontab
        current_crontab=$(sudo crontab -l 2>/dev/null || true)
        if echo "$current_crontab" | grep -qF "/usr/local/bin/$SCRIPT_NAME --cleanup"; then
            local new_crontab=$(echo "$current_crontab" | grep -vF "/usr/local/bin/$SCRIPT_NAME --cleanup")
            echo "$new_crontab" | sudo crontab -
            log_message "[INFO] Automated cleanup disabled. Removed from crontab."
        fi
    fi

    if [[ "$ENABLE_AUTO_IMAGE_UPDATE" == "true" || "$ENABLE_AUTO_IMAGE_UPDATE" == true ]]; then
        local update_cmd="$IMAGE_UPDATE_CRON /usr/local/bin/$SCRIPT_NAME -u -y >> $CRON_LOG_FILE 2>&1"
        local current_crontab
        current_crontab=$(sudo crontab -l 2>/dev/null || true)
        
        local new_crontab=$(echo "$current_crontab" | grep -vF "/usr/local/bin/$SCRIPT_NAME -u -y")
        new_crontab+=$'\n'"$update_cmd"
        
        if ! echo "$current_crontab" | grep -qF "$update_cmd"; then
            echo "$new_crontab" | sudo crontab -
            log_message "[INFO] SUCCESS: Image update schedule updated ($IMAGE_UPDATE_CRON)."
        else
            log_message "[INFO] Image update schedule is already up to date."
        fi
    else
        local current_crontab
        current_crontab=$(sudo crontab -l 2>/dev/null || true)
        if echo "$current_crontab" | grep -qF "/usr/local/bin/$SCRIPT_NAME -u -y"; then
            local new_crontab=$(echo "$current_crontab" | grep -vF "/usr/local/bin/$SCRIPT_NAME -u -y")
            echo "$new_crontab" | sudo crontab -
            log_message "[INFO] Automated image update disabled. Removed from crontab."
        fi
    fi
}

install_utility() {
    setup_dirs
    manage_configuration
    
    sudo cp -v "$(realpath "$0")" "/usr/local/bin/$SCRIPT_NAME" 2>&1 | while read -r line; do log_message "[INFO] $line"; done
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_message "[ERROR] Failed to copy script to /usr/local/bin/$SCRIPT_NAME"
        exit 1
    fi
    sudo chmod +x "/usr/local/bin/$SCRIPT_NAME"
    
    if [ -f "/usr/local/bin/$SCRIPT_FILE_NAME" ]; then
        sudo rm -f "/usr/local/bin/$SCRIPT_FILE_NAME"
    fi
    
    if [ -f "/usr/local/bin/$SCRIPT_NAME" ] && [ -x "/usr/local/bin/$SCRIPT_NAME" ]; then
        log_message "[INFO] SUCCESS: Verified: /usr/local/bin/$SCRIPT_NAME exists and is executable"
        log_message "[INFO] Utility installed to /usr/local/bin/$SCRIPT_NAME. Run '$SCRIPT_NAME' to start."
        
        local orig_path
        orig_path=$(realpath "$0")
        local script_dir=$(dirname "$orig_path")
        if [[ "$orig_path" != "/usr/local/bin/"* ]] && [ ! -d "$script_dir/.git" ]; then
            log_message "[INFO] Removing deployment payload: $orig_path"
            sudo rm -f "$orig_path"
        fi
    else
        log_message "[ERROR] /usr/local/bin/$SCRIPT_NAME does not exist or is not executable"
        exit 1
    fi
}

uninstall_utility() {
    log_message "[INFO] Preparing to uninstall $UTILITY_NAME..."
    
    if [ "$AUTO_YES" = false ]; then
        log_message "[WARNING] This will remove $UTILITY_NAME, its logs, configuration, and scheduled cron jobs."
        log_message "[WARNING] Docker and Docker Compose will NOT be modified."
        read -p "[WARNING] Type 'YES' to continue uninstalling the utility: " confirm
        [[ "$confirm" != "YES" ]] && { log_message "[INFO] Uninstall cancelled."; return 0; }
    fi

    log_message "[INFO] Removing Crontab entries..."
    local current_crontab
    current_crontab=$(sudo crontab -l 2>/dev/null || true)
    
    if echo "$current_crontab" | grep -qF "/usr/local/bin/$SCRIPT_NAME --cleanup"; then
        current_crontab=$(echo "$current_crontab" | grep -vF "/usr/local/bin/$SCRIPT_NAME --cleanup")
        log_message "[INFO] Automated cleanup schedule removed from Crontab."
    fi
    
    if echo "$current_crontab" | grep -qF "/usr/local/bin/$SCRIPT_NAME -u -y"; then
        current_crontab=$(echo "$current_crontab" | grep -vF "/usr/local/bin/$SCRIPT_NAME -u -y")
        log_message "[INFO] Automated image update schedule removed from Crontab."
    fi
    
    echo "$current_crontab" | sudo crontab -

    log_message "[INFO] Removing configuration files..."
    if [ -d "$SYSTEM_DIR" ]; then
        sudo rm -rf "$SYSTEM_DIR"
        log_message "[INFO] System directory $SYSTEM_DIR removed."
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Removing log files..."
    if [ -d "$LOG_DIR" ]; then
        sudo rm -rf "$LOG_DIR"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Log directory $LOG_DIR removed."
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] SUCCESS: $UTILITY_NAME configuration, schedules, and logs have been removed."
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Removing script binary..."
    sudo rm -f "/usr/local/bin/$SCRIPT_NAME"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Uninstall complete."
    exit 0
}

update_utility() {
    log_message "[INFO] Checking for $UTILITY_NAME updates..."
    
    if ! command -v curl &>/dev/null; then
        log_message "[ERROR] curl is required for self-updates."
        return 1
    fi

    local latest_json
    latest_json=$(curl -s https://api.github.com/repos/Arelius-D/NeXdocMan/releases/latest)
    if [ $? -ne 0 ] || [ -z "$latest_json" ]; then
        log_message "[ERROR] Failed to connect to GitHub API."
        return 1
    fi

    local latest_version
    latest_version=$(echo "$latest_json" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$latest_version" ]; then
        log_message "[ERROR] Could not determine latest version from GitHub."
        return 1
    fi

    if [[ "$latest_version" == "$VERSION" ]]; then
        log_message "[INFO] $UTILITY_NAME is already up-to-date ($VERSION)."
        return 0
    fi

    log_message "[INFO] New version available: $latest_version (Current: $VERSION)"
    
    if [ "$AUTO_YES" = false ]; then
        read -p "[INFO] Update $UTILITY_NAME to $latest_version? (y/N): " update_choice
    fi

    if [[ "$AUTO_YES" = true || "$update_choice" =~ ^[Yy]$ ]]; then
        local download_url
        download_url=$(echo "$latest_json" | grep '"browser_download_url":' | grep "NeXdocMan.tar.gz" | sed -E 's/.*"([^"]+)".*/\1/')
        
        if [ -z "$download_url" ]; then
            log_message "[ERROR] Could not find download URL for NeXdocMan.tar.gz."
            return 1
        fi

        log_message "[INFO] Downloading update from $download_url..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        
        if ! curl -L "$download_url" -o "$tmp_dir/NeXdocMan.tar.gz"; then
            log_message "[ERROR] Failed to download update."
            rm -rf "$tmp_dir"
            return 1
        fi

        log_message "[INFO] Extracting update..."
        if ! tar -xzvf "$tmp_dir/NeXdocMan.tar.gz" -C "$tmp_dir" >/dev/null 2>&1; then
            log_message "[ERROR] Failed to extract update."
            rm -rf "$tmp_dir"
            return 1
        fi

        local new_script="$tmp_dir/nexdocman.sh"
        if [ ! -f "$new_script" ]; then
            new_script=$(find "$tmp_dir" -name "nexdocman.sh" | head -n 1)
        fi

        if [ -f "$new_script" ]; then
            log_message "[INFO] Applying update via deployment module..."
            sudo chmod +x "$new_script"
            if sudo "$new_script" -d; then
                log_message "[INFO] SUCCESS: $UTILITY_NAME updated to $latest_version."
                rm -rf "$tmp_dir"
                exit 0
            else
                log_message "[ERROR] Deployment of new version failed."
                rm -rf "$tmp_dir"
                return 1
            fi
        else
            log_message "[ERROR] Could not find nexdocman.sh in extracted archive."
            rm -rf "$tmp_dir"
            return 1
        fi
    else
        log_message "[INFO] Update cancelled."
    fi
}

prune_single_log_file() {
    local target_file="$1"
    local max_days="$2"
    local cutoff_str="$3"

    if [ ! -f "$target_file" ] || [ ! -s "$target_file" ]; then
        return 0
    fi

    local TEMP_FILE=$(mktemp)

    LC_ALL=C awk -v cutoff_str="$cutoff_str" '
    {
        if (match($0, /^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\]/)) {
            timestamp = substr($0, 2, 19)
            if (timestamp >= cutoff_str) {
                print $0
                keep = 1
            } else {
                keep = 0
            }
        } else {
            if (keep == 1 || keep == "") {
                print $0
            }
        }
    }' "$target_file" > "$TEMP_FILE"

    if [ ! -s "$TEMP_FILE" ] && [ -s "$target_file" ]; then
        log_message "[WARNING] Log pruning resulted in an empty file for $(basename "$target_file"). Keeping original log."
        rm -f "$TEMP_FILE"
        return 0
    fi

    local lines_before=$(wc -l < "$target_file")
    local lines_after=$(wc -l < "$TEMP_FILE")
    local lines_pruned=$((lines_before - lines_after))

    sudo mv "$TEMP_FILE" "$target_file"
    sudo chmod 644 "$target_file"
    
    if [ "$lines_pruned" -gt 0 ]; then
        log_message "[INFO] Pruned $lines_pruned log lines older than $max_days days from $(basename "$target_file")."
    fi
}

manage_logs() {
    if [[ "$LOGPRUNE_ENABLED" != "true" && "$LOGPRUNE_ENABLED" != true ]]; then
        log_message "[INFO] Log pruning is disabled in config. Skipping."
        return 0
    fi

    local max_days="${LOGPRUNE_MAX_AGE_DAYS:-7}"
    local CUTOFF_STRING
    CUTOFF_STRING=$(LC_ALL=C date -d "$max_days days ago" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    
    if [ -z "$CUTOFF_STRING" ]; then
        log_message "[ERROR] Failed to calculate cutoff date for log management."
        return 0
    fi

    prune_single_log_file "$LOG_FILE" "$max_days" "$CUTOFF_STRING"
    prune_single_log_file "$CRON_LOG_FILE" "$max_days" "$CUTOFF_STRING"
}

perform_cleanup() {
    log_message "[INFO] Performing a comprehensive system prune..."
    if ! command -v docker &>/dev/null; then
        log_message "[WARNING] Docker is not installed. Skipping cleanup."
        return 0
    fi
    
    local prune_output
    prune_output=$(sudo docker system prune -a --volumes -f 2>&1)
    
    local reclaimed
    reclaimed=$(echo "$prune_output" | grep "Total reclaimed space:" | sed 's/Total reclaimed space: //')
    
    local deleted_count
    deleted_count=$(echo "$prune_output" | grep -cE "^(deleted:|untagged:)")
    
    if [ "$(level_to_num "$LOG_LEVEL")" -le 0 ]; then
        log_message "[DEBUG] Raw Prune Dump Start:"
        echo "$prune_output" | while IFS= read -r line; do
            if [ -n "$line" ]; then
                log_message "[DEBUG]   $line"
            fi
        done
        log_message "[DEBUG] Raw Prune Dump End."
    fi

    if [ -n "$reclaimed" ]; then
        log_message "[INFO] PRUNE SUMMARY: Pruned $deleted_count items. Total reclaimed space: $reclaimed."
        log_message "[INFO] SUCCESS: Comprehensive system prune completed."
    else
        log_message "[ERROR] Prune completed but failed to parse reclaimed space."
    fi
    
    manage_logs
}

setup_docker() {

    log_message "[INFO] Checking for older conflicting Docker packages..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get purge -y $pkg >/dev/null 2>&1 || true
    done
    log_message "[INFO] Conflicting packages resolved."

    log_message "[INFO] Checking for Docker..."
    if ! command -v docker &>/dev/null; then
        log_message "[INFO] Installing Docker and Compose..."
        
        local fetch_cmd=""
        if command -v curl &>/dev/null; then
            fetch_cmd="curl -sSL https://get.docker.com | sudo sh"
        elif command -v wget &>/dev/null; then
            fetch_cmd="wget -qO- https://get.docker.com | sudo sh"
        else
            if [ "$AUTO_YES" = true ]; then
                log_message "[INFO] Neither curl nor wget found. Auto-installing curl via apt-get..."
                run_command sudo apt-get update
                run_command sudo apt-get install -y curl
                fetch_cmd="curl -sSL https://get.docker.com | sudo sh"
            else
                read -p "[WARNING] Neither curl nor wget is installed. Install curl to proceed? (y/N): " install_curl
                if [[ "$install_curl" =~ ^[Yy]$ ]]; then
                    run_command sudo apt-get update
                    run_command sudo apt-get install -y curl
                    fetch_cmd="curl -sSL https://get.docker.com | sudo sh"
                else
                    log_message "[ERROR] Cannot proceed without curl or wget."
                    exit 1
                fi
            fi
        fi

        log_message "[INFO] Downloading and executing official Docker installation script..."
        local dock_out
        dock_out=$(eval "$fetch_cmd" 2>&1)
        install_status=$?

        if [ "$(level_to_num "$LOG_LEVEL")" -le 0 ]; then
            log_message "[DEBUG] Docker Installation Script Output:"
            echo "$dock_out" | while IFS= read -r line; do
                [ -n "$line" ] && log_message "[DEBUG]   $line"
            done
        fi

        if [ "$install_status" -ne 0 ]; then
            log_message "[ERROR] Docker installation failed. Check $LOG_FILE for details."
            exit 1
        fi

        if ! command -v docker &>/dev/null; then
            log_message "[ERROR] Docker not found after installation. Check $LOG_FILE."
            exit 1
        fi

        log_message "[INFO] SUCCESS: Docker installed: $(docker --version)"
        log_message "[INFO] SUCCESS: Docker Compose installed: $(docker compose version)"
    else
        log_message "[INFO] OK: Docker already installed: $(docker --version)"
        log_message "[INFO] OK: Docker Compose: $(docker compose version)"
    fi

    log_message "[INFO] Verifying Docker group exists..."
    if ! getent group docker >/dev/null; then
        log_message "[ERROR] Docker group not found. Check $LOG_FILE."
        exit 1
    fi

    log_message "[INFO] Setting up $ACTUAL_USER for Docker..."
    if ! groups "$ACTUAL_USER" | grep -q '\bdocker\b'; then
        run_command sudo usermod -aG docker "$ACTUAL_USER"
        run_command sudo systemctl restart docker
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
        log_message "[INFO] OK: $ACTUAL_USER added to Docker group."
    else
        log_message "[INFO] OK: $ACTUAL_USER already in Docker group."
        if ! id -nG | grep -qw "docker"; then
            log_message "[INFO] Docker group not active in this session."
            log_message "[INFO] Run 'newgrp docker' to apply changes, or start a new terminal session."
            return 0
        fi
        log_message "[INFO] Testing Docker..."
        if docker run --rm hello-world >/dev/null 2>&1; then
            log_message "[INFO] SUCCESS: Docker test passed!"
        else
            log_message "[WARNING] Docker test failed. Run 'newgrp docker' to apply changes, or log out and back in."
            journalctl -u docker --no-pager | tail -50 | sudo tee -a "$LOG_FILE"
            exit 1
        fi
    fi

    log_message "[INFO] Docker installation complete."
}

check_update() {
    log_message "[INFO] Checking for Docker and Docker Compose..."
    if ! dpkg -l | grep -q docker; then
        log_message "[WARNING] Neither Docker nor Docker Compose is installed."
        return 0
    fi

    docker_ver=$(docker --version)
    compose_ver=$(docker compose version)
    log_message "[INFO] Current Docker: $docker_ver"
    log_message "[INFO] Current Docker Compose: $compose_ver"

    log_message "[INFO] Checking for updates..."
    run_command sudo apt-get update
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
            run_command sudo apt-get upgrade -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin
            if [ $? -ne 0 ]; then
                log_message "[ERROR] Update failed. Check $LOG_FILE."
                exit 1
            fi
            new_docker_ver=$(docker --version | cut -d' ' -f3- | sed 's/,//')
            clean_docker_ver=$(echo "$docker_ver" | cut -d' ' -f3- | sed 's/,//')
            new_compose_ver=$(docker compose version | cut -d' ' -f4-)
            
            if [ "$clean_docker_ver" != "$new_docker_ver" ] || [ "$compose_ver" != "Docker Compose version $new_compose_ver" ]; then
                log_message "[INFO] SUCCESS: Docker updated to $new_docker_ver"
                log_message "[INFO] SUCCESS: Docker Compose updated to $new_compose_ver"
            else
                log_message "[INFO] No version changes detected after update."
            fi
        else
            log_message "[INFO] Update installation skipped."
        fi
    fi
}

check_images() {
    local force_check_only="${1:-false}"
    local target="${2:-}"
    
    if [ -n "$target" ]; then
        log_message "[INFO] Scanning local Docker images targeting: '$target'..."
    else
        log_message "[INFO] Scanning local Docker images against remote manifests..."
    fi
    
    local update_count=0
    local images_to_update=()
    local containers_to_recreate=()
    
    for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>'); do
        if [ -n "$target" ]; then
            local matched=false
            if [[ "$img" == *"$target"* ]]; then
                matched=true
            else
                local active_containers
                active_containers=$(docker ps --filter "ancestor=$img" --format '{{.ID}}')
                if [ -n "$active_containers" ]; then
                    while read -r c_id; do
                        [ -z "$c_id" ] && continue
                        local c_name=$(docker inspect --format '{{.Name}}' "$c_id" 2>/dev/null | sed 's/^\///')
                        local compose_service=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$c_id" 2>/dev/null)
                        if [[ "$c_name" == *"$target"* || "$compose_service" == *"$target"* ]]; then
                            matched=true
                            break
                        fi
                    done <<< "$active_containers"
                fi
            fi
            if [ "$matched" = false ]; then
                continue
            fi
        fi

        local local_digest
        local_digest=$(docker inspect --format='{{if gt (len .RepoDigests) 0}}{{index .RepoDigests 0}}{{end}}' "$img" 2>/dev/null | grep -o 'sha256:.*')
        local remote_digest
        remote_digest=$(docker buildx imagetools inspect "$img" 2>/dev/null | grep "^Digest:" | head -n 1 | awk '{print $2}')
        
        local has_update=false
        if [[ -z "$local_digest" && -n "$remote_digest" ]]; then
            log_message "[WARNING] $img: UPDATE AVAILABLE (Missing local mapping)"
            has_update=true
        elif [[ -n "$remote_digest" && "$local_digest" != "$remote_digest" ]]; then
            log_message "[WARNING] $img: UPDATE AVAILABLE"
            log_message "[DEBUG] Local: $local_digest | Remote: $remote_digest"
            has_update=true
        elif [[ -z "$remote_digest" ]]; then
            log_message "[INFO] SKIP: $img: (No remote digest found. Locally built or private?)"
        else
            log_message "[INFO] OK: $img: CURRENT"
        fi

        if [ "$has_update" = true ]; then
            local active_containers
            active_containers=$(docker ps --filter "ancestor=$img" --format '{{.ID}}')
            
            local should_update_image=true
            if [ -n "$active_containers" ]; then
                local all_excluded=true
                while read -r c_id; do
                    [ -z "$c_id" ] && continue
                    local c_name=$(docker inspect --format '{{.Name}}' "$c_id" 2>/dev/null | sed 's/^\///')
                    if ! is_excluded "$c_name" "$img"; then
                        all_excluded=false
                        break
                    fi
                done <<< "$active_containers"
                
                if [ "$all_excluded" = true ]; then
                    should_update_image=false
                    log_message "[INFO] SKIP: $img (all active containers running it are excluded)."
                fi
            fi
            
            if [ "$should_update_image" = true ]; then
                images_to_update+=("$img")
                ((update_count++))
                
                while read -r c_id; do
                    [ -z "$c_id" ] && continue
                    local c_name=$(docker inspect --format '{{.Name}}' "$c_id" 2>/dev/null | sed 's/^\///')
                    local compose_service=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$c_id" 2>/dev/null)
                    
                    if [ -n "$target" ]; then
                        if [[ "$img" != *"$target"* && "$c_name" != *"$target"* && "$compose_service" != *"$target"* ]]; then
                            continue
                        fi
                    fi
                    
                    if ! is_excluded "$c_name" "$img"; then
                        if [[ ! " ${containers_to_recreate[@]} " =~ " ${c_id} " ]]; then
                            containers_to_recreate+=("$c_id")
                        fi
                    else
                        log_message "[INFO] EXCLUDE: Skipping container '$c_name' ($img) - matched auto-update blocklist."
                    fi
                done <<< "$active_containers"
            fi
        fi
    done
    
    if [ "$update_count" -gt 0 ]; then
        if [ "$force_check_only" = true ]; then
            log_message "[INFO] Audit complete. $update_count image(s) have available updates. Use --update-images to pull."
            return 0
        fi

        if [ "$AUTO_YES" = false ]; then
            log_message "[INFO] Options available for $update_count image(s)."
            read -p "[INFO] Pull latest versions for these images? (y/N): " pull_choice
        fi
        
        if [[ "$AUTO_YES" = true || "$pull_choice" =~ ^[Yy]$ ]]; then
            for img_to_pull in "${images_to_update[@]}"; do
                log_message "[INFO] Pulling $img_to_pull..."
                run_command sudo docker pull "$img_to_pull"
                if [ $? -eq 0 ]; then
                    log_message "[INFO] SUCCESS: $img_to_pull updated."
                else
                    log_message "[ERROR] Failed to pull $img_to_pull. Check $LOG_FILE."
                fi
            done
            log_message "[INFO] SUCCESS: Image update sequence complete."

            if [ ${#containers_to_recreate[@]} -gt 0 ]; then
                if [ "$AUTO_YES" = false ]; then
                    read -p "[INFO] Recreate ${#containers_to_recreate[@]} container(s) to apply updates? (y/N): " recreate_choice
                fi
                
                if [[ "$AUTO_YES" = true || "$recreate_choice" =~ ^[Yy]$ ]]; then
                    for c_id in "${containers_to_recreate[@]}"; do
                        local c_name=$(docker inspect --format '{{.Name}}' "$c_id" | sed 's/^\///')
                        local compose_dir=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}' "$c_id" 2>/dev/null)
                        local compose_service=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$c_id" 2>/dev/null)
                        local compose_file=$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$c_id" 2>/dev/null)

                        if [ -n "$compose_dir" ] && [ -n "$compose_service" ]; then
                            log_message "[INFO] Recreating Compose service: $compose_service ($c_name)..."
                            local compose_cmd="sudo docker compose"
                            [ -n "$compose_file" ] && compose_cmd+=" -f $compose_file"
                            if run_command bash -c "cd \"$compose_dir\" && $compose_cmd up -d --no-deps \"$compose_service\""; then
                                log_message "[INFO] SUCCESS: $c_name recreated."
                            else
                                log_message "[ERROR] Failed to recreate $c_name."
                            fi
                        else
                            log_message "[WARNING] $c_name is a standalone container. Recreate manually to apply update."
                        fi
                    done
                fi
            fi
        else
            log_message "[INFO] Image update skipped."
        fi
    else
        log_message "[INFO] SUCCESS: All local images are current."
    fi
}

purge_docker() {
    log_message "[INFO] Checking for Docker and Docker Compose..."
    if dpkg -l | grep -q docker || dpkg -l | grep -q docker-compose; then
        if [ "$AUTO_YES" = false ]; then
            log_message "[WARNING] This will COMPLETELY PURGE Docker & Docker Compose."
            read -p "[WARNING] Type 'YES' to continue: " final_confirm
            [[ "$final_confirm" != "YES" ]] && { log_message "[INFO] Purge cancelled."; return 0; }
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
        run_command sudo apt-get update
        run_command sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-ce-rootless-extras docker-buildx-plugin
        if [ $? -ne 0 ]; then
            log_message "[ERROR] Purge failed. Check $LOG_FILE."
            exit 1
        fi

        log_message "[INFO] Cleaning up Docker data..."
        run_command sudo rm -rf /var/lib/docker /var/lib/containerd ~/.docker /usr/local/bin/docker-compose

        log_message "[INFO] Removing $ACTUAL_USER from Docker group..."
        sudo gpasswd -d "$ACTUAL_USER" docker >/dev/null 2>&1 || true

        if getent group docker >/dev/null; then
            log_message "[INFO] Removing Docker group..."
            run_command sudo groupdel docker
        fi

        log_message "[INFO] Cleaning up packages..."
        run_command sudo apt-get autoremove --purge -y
        run_command sudo apt-get clean

        log_message "[INFO] SUCCESS: Docker and Docker Compose purged!"
        
        if echo "$(sudo crontab -l 2>/dev/null)" | grep -qF "/usr/local/bin/$SCRIPT_NAME --cleanup"; then
            local new_crontab=$(sudo crontab -l 2>/dev/null | grep -vF "/usr/local/bin/$SCRIPT_NAME --cleanup")
            echo "$new_crontab" | sudo crontab -
            log_message "[INFO] Remnant cron tasks removed."
        fi
        
        if [ -f "$CFG_FILE" ]; then
            sudo rm -f "$CFG_FILE"
            log_message "[INFO] Removed configuration file ($CFG_FILE)."
        fi
    else
        log_message "[INFO] OK: Nothing to purge."
    fi
}

# CLI PARSING & TUI

if [ "$EUID" -eq 0 ] && [[ "$(realpath "$0")" != "/usr/local/bin/"* ]]; then
    cp -f "$(realpath "$0")" "/usr/local/bin/$SCRIPT_NAME" 2>/dev/null || true
    chmod +x "/usr/local/bin/$SCRIPT_NAME" 2>/dev/null || true
    rm -f "/usr/local/bin/$SCRIPT_FILE_NAME" 2>/dev/null || true
fi

setup_dirs

image_target=""
do_install=false
do_status=false
do_purge=false
do_manage=false
initiate_install=false
do_cleanup=false
configure_cron=false
uninstall_utility_flag=false
do_check_images=false
do_update_images=false
do_update_utility=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -y|--yes) AUTO_YES=true ;;
        -v|--version) show_versions; exit 0 ;;
        -h|--help) show_help; exit 0 ;;
        -V|--verbose) VERBOSE=true ;;
        -i|--install) do_install=true ;;
        -s|--status) do_status=true ;;
        -p|--purge) do_purge=true ;;
        -m|--manage) do_manage=true ;;
        -k|--check-images)
            do_check_images=true
            if [[ -n "${2:-}" && "$2" != -* ]]; then
                image_target="$2"
                shift
            fi
            ;;
        -u|--update-images)
            do_update_images=true
            if [[ -n "${2:-}" && "$2" != -* ]]; then
                image_target="$2"
                shift
            fi
            ;;
        -c|--cleanup) do_cleanup=true ;;
        -C|--configure-cron) configure_cron=true ;;
        -d|--deploy) initiate_install=true ;;
        -r|--remove) uninstall_utility_flag=true ;;
        -U|--update-utility) do_update_utility=true ;;
        *)
            if [[ "$1" != -* ]]; then
                image_target="$1"
            else
                log_message "[ERROR] Unknown parameter: $1"
                exit 1
            fi
            ;;
    esac
    shift
done
select_target_container() {
    TUI_TARGET=""
    local -a container_names=()
    local -a container_details=()
    while IFS=$'\t' read -r name image service; do
        [ -z "$name" ] && continue
        container_names+=("$name")
        if [ -n "$service" ]; then
            container_details+=("$name\t($image)\t[Compose:\t$service]")
        else
            container_details+=("$name\t($image)")
        fi
    done <<< "$(docker ps --format '{{.Names}}\t{{.Image}}\t{{.Label "com.docker.compose.service"}}')"

    if [ "${#container_names[@]}" -gt 0 ]; then
        echo "Active Containers:"
        echo "--------------------------------------------------"
        local idx=1
        local formatted_list=""
        for i in "${!container_names[@]}"; do
            formatted_list+="${idx})\t${container_details[$i]}\n"
            ((idx++))
        done
        echo -e "$formatted_list" | column -t -s $'\t'
        echo "--------------------------------------------------"
        echo ""
        echo -n "Enter option number [1-$((idx-1))] or type target name: "
    else
        echo "No active containers running."
        echo ""
        echo -n "Enter target container, image, or service name: "
    fi

    local target_input
    read target_input
    if [[ "$target_input" =~ ^[0-9]+$ ]] && [ "$target_input" -ge 1 ] && [ "$target_input" -le "${#container_names[@]}" ]; then
        TUI_TARGET="${container_names[$((target_input-1))]}"
    else
        TUI_TARGET="$target_input"
    fi
}

show_menu() {
    clear
    echo "=================================================="
    echo " 🐳 $UTILITY_NAME - Docker Manager ($VERSION)"
    echo "=================================================="
    echo ""
    echo " [Core Operations]"
    echo "   1. Install Docker & Docker Compose"
    echo "   2. Check and Update Docker & Docker Compose"
    echo "   3. Display Docker & Resource Status"
    echo ""
    echo " [Maintenance & Automation]"
    echo "   4. Check Local Images for Available Updates"
    echo "   5. Run Automated System Cleanup (Prune)"
    echo "   6. Apply / Update Automated Schedules (Cron)"
    echo ""
    echo " [Advanced & Destructive]"
    echo "   7. Purge ALL Docker Installations & Volumes"
    echo "   8. Check and Update NeXdocMan Utility"
    echo ""
    echo "   0. Exit"
    echo "--------------------------------------------------"
    echo -n "Choose an option [0-8]: "
}

if [ "$do_install" = true ] || [ "$do_status" = true ] || [ "$do_purge" = true ] || [ "$do_manage" = true ] || [ "$do_check_images" = true ] || [ "$do_update_images" = true ] || [ "$do_cleanup" = true ] || [ "$configure_cron" = true ] || [ "$initiate_install" = true ] || [ "$uninstall_utility_flag" = true ] || [ "$do_update_utility" = true ]; then
    log_message "[INFO] Running $UTILITY_NAME $VERSION"
    if [ "$do_purge" = true ] && [ "$do_manage" = true ]; then
        log_message "[ERROR] Cannot use --purge and --manage together!"
        exit 1
    fi
    
    if [ "$do_status" = true ]; then
        display_status
    elif [ "$do_install" = true ]; then
        setup_docker
    elif [ "$do_purge" = true ]; then
        purge_docker
    elif [ "$do_manage" = true ]; then
        check_update
    elif [ "$do_check_images" = true ]; then
        check_images true "$image_target"
    elif [ "$do_update_images" = true ]; then
        check_images false "$image_target"
    elif [ "$do_cleanup" = true ]; then
        perform_cleanup
    elif [ "$configure_cron" = true ]; then
        setup_cron
    elif [ "$initiate_install" = true ]; then
        install_utility
    elif [ "$uninstall_utility_flag" = true ]; then
        uninstall_utility
    elif [ "$do_update_utility" = true ]; then
        update_utility
    fi
    exit 0
else
    while true; do
        show_menu
        read choice || exit 0
        case $choice in
            1)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                setup_docker
                ;;
            2)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                check_update
                ;;
            3)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                display_status
                ;;
            4)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                while true; do
                    clear
                    echo "=================================================="
                    echo " 🐳 $UTILITY_NAME - Image Audit & Update ($VERSION)"
                    echo "=================================================="
                    echo ""
                    echo "  [ Global Sweeps ]"
                    echo "    1. Audit All Container Images"
                    echo "    2. Update All Container Images"
                    echo ""
                    echo "  [ Targeted Operations ]"
                    echo "    3. Audit a Specific Container/Image"
                    echo "    4. Update a Specific Container/Image"
                    echo ""
                    echo "    0. Back to Main Menu"
                    echo "--------------------------------------------------"
                    echo -n "Choose an option [0-4]: "
                    read update_choice || break
                    case $update_choice in
                        1)
                            check_images true
                            break
                            ;;
                        2)
                            check_images false
                            break
                            ;;
                        3)
                            echo ""
                            select_target_container
                            if [ -n "$TUI_TARGET" ]; then
                                check_images true "$TUI_TARGET"
                            else
                                log_message "[WARNING] No target entered. Skipping."
                            fi
                            break
                            ;;
                        4)
                            echo ""
                            select_target_container
                            if [ -n "$TUI_TARGET" ]; then
                                check_images false "$TUI_TARGET"
                            else
                                log_message "[WARNING] No target entered. Skipping."
                            fi
                            break
                            ;;
                        0)
                            break
                            ;;
                        *)
                            echo "Invalid option: $update_choice"
                            sleep 1
                            ;;
                    esac
                done
                ;;
            5)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                perform_cleanup
                ;;
            6)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                setup_cron
                ;;
            7)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                purge_docker
                ;;
            8)
                log_message "[INFO] Running $UTILITY_NAME $VERSION"
                update_utility
                ;;
            0)
                log_message "[INFO] Exiting."
                exit 0
                ;;
            *)
                log_message "[ERROR] Invalid option: $choice"
                ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..." || exit 0
        echo ""
        clear
    done
fi
