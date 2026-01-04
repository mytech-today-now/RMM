#!/bin/bash
# ============================================================================
# myTech.Today RMM Server - Linux Uninstallation Script
# Removes system-wide or per-user RMM server installation
# ============================================================================

set -e

# Script metadata
SCRIPT_TITLE="RMM"
BUNDLE_ID="com.mytech.today.rmm"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Options
SILENT=false
REMOVE_ALL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --silent|-s) SILENT=true; shift ;;
        --all|-a) REMOVE_ALL=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "  --silent, -s    Silent mode (no prompts)"
            echo "  --all, -a       Remove data and config too"
            echo "  --help, -h      Show this help"
            exit 0 ;;
        *) shift ;;
    esac
done

# Detect privileges
IS_ROOT=false
[ "$EUID" -eq 0 ] && IS_ROOT=true

# Set paths based on privileges
if [ "$IS_ROOT" = true ]; then
    INSTALL_DIR="/opt/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="/var/opt/myTech.Today/$SCRIPT_TITLE"
    LOG_DIR="/var/log/myTech.Today/$SCRIPT_TITLE"
    MODULE_DIR="/opt/microsoft/powershell/7/Modules/RMM"
    SERVICE_FILE="/etc/systemd/system/mytech-rmm.service"
    BIN_LINK="/usr/local/bin/rmm"
    PARENT_OPT="/opt/myTech.Today"
    PARENT_VAR="/var/opt/myTech.Today"
    PARENT_LOG="/var/log/myTech.Today"
else
    INSTALL_DIR="$HOME/.local/share/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="$INSTALL_DIR"
    LOG_DIR="$INSTALL_DIR/logs"
    MODULE_DIR="$HOME/.local/share/powershell/Modules/RMM"
    SERVICE_FILE=""
    BIN_LINK="$HOME/.local/bin/rmm"
    PARENT_OPT="$HOME/.local/share/myTech.Today"
    PARENT_VAR=""
    PARENT_LOG=""
fi

log_info() { [ "$SILENT" = false ] && echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok() { [ "$SILENT" = false ] && echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Banner
show_banner() {
    [ "$SILENT" = true ] && return
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}myTech.Today RMM Server - Linux Uninstaller${NC}          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_banner

# Step 1: Stop and remove service
if [ "$IS_ROOT" = true ] && [ -f "$SERVICE_FILE" ]; then
    log_info "[1/6] Stopping and removing systemd service..."
    systemctl stop mytech-rmm 2>/dev/null || true
    systemctl disable mytech-rmm 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    log_ok "Service removed"
else
    log_info "[1/6] No service to remove"
fi

# Step 2: Clear PowerShell module cache
log_info "[2/6] Clearing PowerShell module cache..."
if command -v pwsh &>/dev/null; then
    pwsh -NoProfile -NonInteractive -Command "Remove-Module -Name RMM -Force -ErrorAction SilentlyContinue" 2>/dev/null || true
fi
log_ok "Module cache cleared"

# Step 3: Remove launcher
log_info "[3/6] Removing launcher..."
rm -f "$BIN_LINK"
log_ok "Launcher removed"

# Step 4: Remove PowerShell module
log_info "[4/6] Removing PowerShell module..."
rm -rf "$MODULE_DIR"
log_ok "Module removed"

# Step 5: Remove installation files
log_info "[5/6] Removing installation files..."
rm -rf "$INSTALL_DIR"
log_ok "Installation files removed"

# Step 6: Remove data (optional)
if [ "$REMOVE_ALL" = true ]; then
    log_info "[6/6] Removing data and logs..."
    rm -rf "$DATA_ROOT"
    rm -rf "$LOG_DIR"
    log_ok "Data and logs removed"
else
    log_info "[6/6] Preserving data at: $DATA_ROOT"
    log_info "      Use --all to remove data too"
fi

# Clean up empty parent directories
[ -d "$PARENT_OPT" ] && rmdir "$PARENT_OPT" 2>/dev/null || true
[ -n "$PARENT_VAR" ] && [ -d "$PARENT_VAR" ] && rmdir "$PARENT_VAR" 2>/dev/null || true
[ -n "$PARENT_LOG" ] && [ -d "$PARENT_LOG" ] && rmdir "$PARENT_LOG" 2>/dev/null || true

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Uninstallation Complete!                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
if [ "$REMOVE_ALL" = false ]; then
    echo -e "  ${YELLOW}Data preserved at:${NC} $DATA_ROOT"
    echo -e "  ${YELLOW}To remove data:${NC}    $0 --all"
fi
echo ""
exit 0

