#!/bin/bash
#
# myTech.Today RMM - Linux Client Uninstallation Script
# Removes the RMM client agent, service, and optionally all data
#
# Usage:
#   sudo ./uninstall-client-linux.sh           # Remove program, keep data
#   sudo ./uninstall-client-linux.sh --all     # Remove everything
#   ./uninstall-client-linux.sh                # Remove per-user installation
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
REMOVE_DATA=false
SILENT=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all|-a) REMOVE_DATA=true; shift ;;
        --silent) SILENT=true; shift ;;
        --force|-f) FORCE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "  --all, -a    Remove all data including logs and config"
            echo "  --silent     Silent uninstallation"
            echo "  --force, -f  Skip confirmation"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Detect privileges
IS_ROOT=false
[ "$EUID" -eq 0 ] && IS_ROOT=true

# Set paths based on privileges
SCRIPT_TITLE="RMM-Client"
if [ "$IS_ROOT" = true ]; then
    INSTALL_DIR="/opt/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="/var/opt/myTech.Today/$SCRIPT_TITLE"
    LOG_DIR="/var/log/myTech.Today/$SCRIPT_TITLE"
    SERVICE_FILE="/etc/systemd/system/mytech-rmm-client.service"
    BIN_LINK="/usr/local/bin/rmm-client"
    PARENT_OPT="/opt/myTech.Today"
    PARENT_VAR="/var/opt/myTech.Today"
    PARENT_LOG="/var/log/myTech.Today"
else
    INSTALL_DIR="$HOME/.local/share/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="$INSTALL_DIR/data"
    LOG_DIR="$INSTALL_DIR/logs"
    SERVICE_FILE=""
    BIN_LINK="$HOME/.local/bin/rmm-client"
    PARENT_OPT="$HOME/.local/share/myTech.Today"
    PARENT_VAR=""
    PARENT_LOG=""
fi

log_info() { [ "$SILENT" = false ] && echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok() { [ "$SILENT" = false ] && echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Banner
if [ "$SILENT" = false ]; then
    echo ""
    echo -e "${RED}============================================================${NC}"
    echo -e "${RED}  myTech.Today RMM - Linux Client Uninstaller${NC}"
    echo -e "${RED}============================================================${NC}"
    echo ""
fi

# Confirmation
if [ "$FORCE" = false ] && [ "$SILENT" = false ]; then
    echo -e "This will remove the RMM client from this system."
    [ "$REMOVE_DATA" = true ] && echo -e "${YELLOW}WARNING: All data, logs, and config will be deleted!${NC}"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
fi

# Step 1: Stop and disable service
log_info "[1/4] Stopping service..."
if [ "$IS_ROOT" = true ] && [ -f "$SERVICE_FILE" ]; then
    systemctl stop mytech-rmm-client 2>/dev/null || true
    systemctl disable mytech-rmm-client 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    log_ok "Service stopped and removed"
else
    log_info "No systemd service found"
fi

# Step 2: Remove binary link
log_info "[2/4] Removing command-line wrapper..."
[ -f "$BIN_LINK" ] && rm -f "$BIN_LINK" && log_ok "Removed: $BIN_LINK"

# Step 3: Remove program files
log_info "[3/4] Removing program files..."
[ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR" && log_ok "Removed: $INSTALL_DIR"

# Step 4: Remove data (if requested)
log_info "[4/4] Cleaning up..."
if [ "$REMOVE_DATA" = true ]; then
    [ -d "$DATA_DIR" ] && rm -rf "$DATA_DIR" && log_ok "Removed data: $DATA_DIR"
    [ -d "$LOG_DIR" ] && rm -rf "$LOG_DIR" && log_ok "Removed logs: $LOG_DIR"
else
    log_info "Data preserved at: $DATA_DIR"
fi

# Clean up empty parent directories
for dir in "$PARENT_OPT" "$PARENT_VAR" "$PARENT_LOG"; do
    [ -n "$dir" ] && [ -d "$dir" ] && [ -z "$(ls -A "$dir" 2>/dev/null)" ] && rmdir "$dir" 2>/dev/null
done

if [ "$SILENT" = false ]; then
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Uninstallation Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    if [ "$REMOVE_DATA" = false ]; then
        echo -e "\nData preserved. To remove all data, run:"
        echo -e "  ${YELLOW}$0 --all${NC}"
    fi
    echo ""
fi

exit 0

