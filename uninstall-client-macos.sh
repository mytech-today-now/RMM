#!/bin/bash
#
# myTech.Today RMM - macOS Client Uninstallation Script
# Removes the RMM client agent, launchd service, and optionally all data
#
# Usage:
#   sudo ./uninstall-client-macos.sh           # Remove program, keep data
#   sudo ./uninstall-client-macos.sh --all     # Remove everything
#   ./uninstall-client-macos.sh                # Remove per-user installation
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
BUNDLE_ID="com.mytech.today.rmm-client"

if [ "$IS_ROOT" = true ]; then
    INSTALL_DIR="/usr/local/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="/Library/Application Support/myTech.Today/$SCRIPT_TITLE"
    CONFIG_DIR="$DATA_DIR/config"
    LOG_DIR="/Library/Logs/myTech.Today/$SCRIPT_TITLE"
    LAUNCH_PLIST="/Library/LaunchDaemons/$BUNDLE_ID.plist"
    BIN_LINK="/usr/local/bin/rmm-client"
    PARENT_USR="/usr/local/myTech.Today"
    PARENT_LIB="/Library/Application Support/myTech.Today"
    PARENT_LOG="/Library/Logs/myTech.Today"
else
    INSTALL_DIR="$HOME/Library/Application Support/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="$INSTALL_DIR/data"
    CONFIG_DIR="$HOME/Library/Preferences/myTech.Today/$SCRIPT_TITLE"
    LOG_DIR="$HOME/Library/Logs/myTech.Today/$SCRIPT_TITLE"
    LAUNCH_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
    BIN_LINK="$HOME/.local/bin/rmm-client"
    PARENT_USR="$HOME/Library/Application Support/myTech.Today"
    PARENT_LIB="$HOME/Library/Preferences/myTech.Today"
    PARENT_LOG="$HOME/Library/Logs/myTech.Today"
fi

log_info() { [ "$SILENT" = false ] && echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok() { [ "$SILENT" = false ] && echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Banner
if [ "$SILENT" = false ]; then
    echo ""
    echo -e "${RED}============================================================${NC}"
    echo -e "${RED}  myTech.Today RMM - macOS Client Uninstaller${NC}"
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

# Step 1: Unload and remove launchd plist
log_info "[1/4] Stopping service..."
if [ -f "$LAUNCH_PLIST" ]; then
    if [ "$IS_ROOT" = true ]; then
        launchctl unload "$LAUNCH_PLIST" 2>/dev/null || true
    else
        launchctl unload "$LAUNCH_PLIST" 2>/dev/null || true
    fi
    rm -f "$LAUNCH_PLIST"
    log_ok "LaunchDaemon/Agent removed"
else
    log_info "No launchd plist found"
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
    [ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR" && log_ok "Removed config: $CONFIG_DIR"
    [ -d "$LOG_DIR" ] && rm -rf "$LOG_DIR" && log_ok "Removed logs: $LOG_DIR"
else
    log_info "Data preserved at: $DATA_DIR"
fi

# Clean up empty parent directories
for dir in "$PARENT_USR" "$PARENT_LIB" "$PARENT_LOG"; do
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

