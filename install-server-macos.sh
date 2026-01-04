#!/bin/bash
# ============================================================================
# myTech.Today RMM Server - macOS Installation Script
# Enterprise-grade system-wide installer with launchd daemon
# ============================================================================
# For CLIENT-ONLY installation (managed endpoint), use: ./install-client-macos.sh
# ============================================================================

set -e

# Script metadata
SCRIPT_TITLE="RMM"
VERSION="2.1.0"
BUNDLE_ID="com.mytech.today.rmm"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Options
SILENT=false
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --silent|-s) SILENT=true; shift ;;
        --force|-f) FORCE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "  --silent, -s    Silent mode (no prompts)"
            echo "  --force, -f     Force reinstall"
            echo "  --help, -h      Show this help"
            exit 0 ;;
        *) shift ;;
    esac
done

# Detect privileges
IS_ROOT=false
[ "$EUID" -eq 0 ] && IS_ROOT=true

# Set installation paths based on privileges
if [ "$IS_ROOT" = true ]; then
    INSTALL_MODE="system"
    INSTALL_DIR="/usr/local/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="/Library/Application Support/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$DATA_ROOT/config"
    LOG_DIR="/Library/Logs/myTech.Today/$SCRIPT_TITLE"
    MODULE_DIR="/usr/local/microsoft/powershell/7/Modules/RMM"
    LAUNCH_PLIST="/Library/LaunchDaemons/$BUNDLE_ID.plist"
    BIN_LINK="/usr/local/bin/rmm"
else
    INSTALL_MODE="user"
    INSTALL_DIR="$HOME/Library/Application Support/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="$INSTALL_DIR"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$HOME/Library/Preferences/myTech.Today/$SCRIPT_TITLE"
    LOG_DIR="$HOME/Library/Logs/myTech.Today/$SCRIPT_TITLE"
    MODULE_DIR="$HOME/.local/share/powershell/Modules/RMM"
    LAUNCH_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
    BIN_LINK="$HOME/.local/bin/rmm"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log_info() { [ "$SILENT" = false ] && echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok() { [ "$SILENT" = false ] && echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Banner
show_banner() {
    [ "$SILENT" = true ] && return
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}myTech.Today RMM Server - macOS Installer${NC}   v$VERSION  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ "$IS_ROOT" = true ]; then
        echo -e "  ${GREEN}●${NC} Running with root privileges - ${GREEN}System-wide installation${NC}"
    else
        echo -e "  ${YELLOW}●${NC} Running without root - ${YELLOW}Per-user installation${NC}"
        echo -e "    ${YELLOW}Run with sudo for system-wide install with launchd daemon${NC}"
    fi
    echo ""
}

show_banner

# Step 1: Check Homebrew
log_info "[1/7] Checking Homebrew..."
if ! command -v brew &>/dev/null; then
    if [ "$IS_ROOT" = false ]; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        [ -f "/opt/homebrew/bin/brew" ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        log_warn "Homebrew should be installed as non-root user"
    fi
else
    log_ok "Homebrew is installed"
fi

# Step 2: Check/Install PowerShell
log_info "[2/7] Checking PowerShell Core..."
if ! command -v pwsh &>/dev/null; then
    if command -v brew &>/dev/null; then
        log_info "Installing PowerShell via Homebrew..."
        brew install --cask powershell
    else
        log_error "PowerShell not found. Install via: brew install --cask powershell"
        exit 1
    fi
else
    log_ok "PowerShell $(pwsh --version) is installed"
fi

# Step 3: Create directories
log_info "[3/7] Creating directories..."
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" "$LOG_DIR"
mkdir -p "$(dirname "$MODULE_DIR")"
mkdir -p "$MODULE_DIR"
mkdir -p "$(dirname "$BIN_LINK")"
if [ "$IS_ROOT" = true ]; then
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$DATA_ROOT" "$DATA_DIR" "$CONFIG_DIR" 2>/dev/null || true
    chmod 755 "$LOG_DIR"
fi
log_ok "Directories created"

# Step 4: Copy files
log_info "[4/7] Copying RMM files..."
if [ -d "$SCRIPT_DIR/scripts" ]; then
    rsync -a --exclude='.git' --exclude='.augment' --exclude='ai-prompts' --exclude='tests' \
        --exclude='secrets' --exclude='*.md' --exclude='LICENSE' \
        --exclude='install-*.sh' --exclude='uninstall-*.sh' \
        "$SCRIPT_DIR/scripts" "$INSTALL_DIR/" 2>/dev/null || cp -R "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"
    [ -d "$SCRIPT_DIR/config" ] && { rsync -a "$SCRIPT_DIR/config" "$INSTALL_DIR/" 2>/dev/null || cp -R "$SCRIPT_DIR/config" "$INSTALL_DIR/"; }
    [ -d "$SCRIPT_DIR/docs" ] && { rsync -a "$SCRIPT_DIR/docs" "$INSTALL_DIR/" 2>/dev/null || cp -R "$SCRIPT_DIR/docs" "$INSTALL_DIR/"; }
    log_ok "Files copied to $INSTALL_DIR"
else
    log_error "scripts directory not found in $SCRIPT_DIR"
    exit 1
fi

# Step 5: Install PowerShell module
log_info "[5/7] Installing PowerShell module..."
cp "$INSTALL_DIR/scripts/core/RMM-Core.psm1" "$MODULE_DIR/RMM.psm1"
cp "$INSTALL_DIR/scripts/core/RMM.psd1" "$MODULE_DIR/RMM.psd1"
log_ok "Module installed to $MODULE_DIR"

# Step 6: Install dependencies and create launcher
log_info "[6/7] Installing dependencies..."
SCOPE=$([ "$IS_ROOT" = true ] && echo "AllUsers" || echo "CurrentUser")
pwsh -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'SilentlyContinue'
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    @('PSSQLite','ImportExcel','PSWriteHTML') | ForEach-Object {
        if (-not (Get-Module -ListAvailable -Name \$_)) {
            Install-Module -Name \$_ -Scope $SCOPE -Force -AllowClobber
        }
    }
" 2>/dev/null
cat > "$BIN_LINK" << 'LAUNCHER'
#!/bin/bash
pwsh -NoProfile -Command "Import-Module RMM -Force; $args" -- "$@"
LAUNCHER
chmod +x "$BIN_LINK"
log_ok "Dependencies installed, launcher at $BIN_LINK"

# Step 7: Create launchd daemon (root only)
if [ "$IS_ROOT" = true ]; then
    log_info "[7/7] Creating launchd daemon..."
    cat > "$LAUNCH_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/pwsh</string>
        <string>-NoProfile</string>
        <string>-File</string>
        <string>$INSTALL_DIR/scripts/ui/Start-WebDashboard.ps1</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/service.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/service-error.log</string>
</dict>
</plist>
EOF
    chmod 644 "$LAUNCH_PLIST"
    launchctl load "$LAUNCH_PLIST" 2>/dev/null || true
    log_ok "Daemon '$BUNDLE_ID' created and loaded"
else
    log_info "[7/7] Skipping daemon (requires root)"
fi

# Initialize
log_info "Initializing RMM..."
pwsh -NoProfile -NonInteractive -Command "
    Import-Module RMM -Force
    Initialize-RMM
" 2>/dev/null && log_ok "RMM initialized"

# Summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Installation Complete!                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Installation Mode:${NC}  $INSTALL_MODE"
echo -e "  ${BOLD}Install Directory:${NC} $INSTALL_DIR"
echo -e "  ${BOLD}Data Directory:${NC}    $DATA_DIR"
echo -e "  ${BOLD}Config Directory:${NC}  $CONFIG_DIR"
echo -e "  ${BOLD}Log Directory:${NC}     $LOG_DIR"
echo ""
if [ "$IS_ROOT" = true ]; then
    echo -e "  ${BOLD}Start daemon:${NC}      ${YELLOW}sudo launchctl start $BUNDLE_ID${NC}"
    echo -e "  ${BOLD}Stop daemon:${NC}       ${YELLOW}sudo launchctl stop $BUNDLE_ID${NC}"
fi
echo -e "  ${BOLD}Use RMM CLI:${NC}       ${YELLOW}rmm${NC}"
echo -e "  ${BOLD}Import module:${NC}     ${YELLOW}pwsh -c 'Import-Module RMM'${NC}"
echo ""
exit 0
