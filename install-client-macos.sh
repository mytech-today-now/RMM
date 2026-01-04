#!/bin/bash
#
# myTech.Today RMM - macOS Client Installation Script
# Enterprise-grade installer for macOS client devices
#
# System-wide installation (with sudo):
#   Program Files: /usr/local/myTech.Today/RMM-Client/
#   Data/Config:   /Library/Application Support/myTech.Today/RMM-Client/
#   Logs:          /Library/Logs/myTech.Today/RMM-Client/
#   LaunchDaemon:  /Library/LaunchDaemons/com.mytech.today.rmm-client.plist
#
# Per-user fallback (without sudo):
#   Program:       ~/Library/Application Support/myTech.Today/RMM-Client/
#   Config:        ~/Library/Preferences/myTech.Today/RMM-Client/
#   Logs:          ~/Library/Logs/myTech.Today/RMM-Client/
#   LaunchAgent:   ~/Library/LaunchAgents/com.mytech.today.rmm-client.plist
#
# Usage:
#   sudo ./install-client-macos.sh                    # System-wide (recommended)
#   ./install-client-macos.sh                         # Per-user fallback
#   sudo ./install-client-macos.sh --server URL --code ABC123 --silent
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Script info
SCRIPT_TITLE="RMM-Client"
VERSION="2.1.0"
BUNDLE_ID="com.mytech.today.rmm-client"

# Parse command line arguments
SERVER_URL=""
PAIRING_CODE=""
SILENT=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --server|-s) SERVER_URL="$2"; shift 2 ;;
        --code|-c) PAIRING_CODE="$2"; shift 2 ;;
        --silent) SILENT=true; shift ;;
        --force|-f) FORCE=true; shift ;;
        --help|-h)
            echo "myTech.Today RMM Client Installer v$VERSION"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --server, -s URL   RMM server URL (e.g., http://192.168.1.100:8080)"
            echo "  --code, -c CODE    6-character pairing code from administrator"
            echo "  --silent           Silent installation (no prompts)"
            echo "  --force, -f        Force reinstall even if already installed"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo $0                              # Interactive system-wide install"
            echo "  sudo $0 --server http://rmm:8080 --code ABC123 --silent"
            echo "  $0                                   # Per-user install (no sudo)"
            exit 0 ;;
        *) echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
    esac
done

# Detect if running as root/sudo
IS_ROOT=false
if [ "$EUID" -eq 0 ] || [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=true
fi

# Set installation paths based on privileges
if [ "$IS_ROOT" = true ]; then
    INSTALL_MODE="system"
    INSTALL_DIR="/usr/local/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="/Library/Application Support/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$DATA_ROOT/config"
    LOG_DIR="/Library/Logs/myTech.Today/$SCRIPT_TITLE"
    LAUNCH_PLIST="/Library/LaunchDaemons/$BUNDLE_ID.plist"
    BIN_LINK="/usr/local/bin/rmm-client"
else
    INSTALL_MODE="user"
    INSTALL_DIR="$HOME/Library/Application Support/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="$INSTALL_DIR"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$HOME/Library/Preferences/myTech.Today/$SCRIPT_TITLE"
    LOG_DIR="$HOME/Library/Logs/myTech.Today/$SCRIPT_TITLE"
    LAUNCH_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
    BIN_LINK="$HOME/.local/bin/rmm-client"
fi

# Output helpers
log_info() { [ "$SILENT" = false ] && echo -e "${CYAN}[INFO]${NC} $1"; }
log_ok() { [ "$SILENT" = false ] && echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { [ "$SILENT" = false ] && echo -e "${CYAN}[$1]${NC} $2"; }

# Banner
if [ "$SILENT" = false ]; then
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  myTech.Today RMM - macOS Client Installer v$VERSION${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    if [ "$IS_ROOT" = true ]; then
        echo -e "${GREEN}[OK] Running with elevated privileges - System-wide installation${NC}"
    else
        echo -e "${YELLOW}[WARN] Running without sudo - Per-user installation only${NC}"
        echo -e "${GRAY}     For full functionality, run: sudo $0${NC}"
    fi
    echo ""
    echo -e "Installation Paths:"
    echo -e "  ${GRAY}Program:${NC} $INSTALL_DIR"
    echo -e "  ${GRAY}Data:${NC}    $DATA_DIR"
    echo -e "  ${GRAY}Config:${NC}  $CONFIG_DIR"
    echo -e "  ${GRAY}Logs:${NC}    $LOG_DIR"
    echo ""
fi

# Check for Homebrew
check_homebrew() {
    if ! command -v brew &> /dev/null; then
        # Check common Homebrew locations
        if [ -f "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -f "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        else
            return 1
        fi
    fi
    return 0
}

install_homebrew() {
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# Create launchd plist
create_launchd_plist() {
    local plist_dir
    plist_dir=$(dirname "$LAUNCH_PLIST")
    mkdir -p "$plist_dir"

    if [ "$IS_ROOT" = true ]; then
        # LaunchDaemon (system-wide, runs as root)
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
        <string>-NonInteractive</string>
        <string>-File</string>
        <string>$INSTALL_DIR/scripts/core/RMM-Client.ps1</string>
        <string>-Daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/daemon-error.log</string>
    <key>WorkingDirectory</key>
    <string>$DATA_DIR</string>
</dict>
</plist>
EOF
        chmod 644 "$LAUNCH_PLIST"
        chown root:wheel "$LAUNCH_PLIST"
    else
        # LaunchAgent (per-user)
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
        <string>-NonInteractive</string>
        <string>-File</string>
        <string>$INSTALL_DIR/scripts/core/RMM-Client.ps1</string>
        <string>-Daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/agent.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/agent-error.log</string>
</dict>
</plist>
EOF
        chmod 644 "$LAUNCH_PLIST"
    fi
    log_ok "LaunchDaemon/Agent plist created"
}

# Main installation steps
TOTAL_STEPS=7

log_step "1/$TOTAL_STEPS" "Checking for Homebrew..."
if ! check_homebrew; then
    if [ "$IS_ROOT" = true ]; then
        log_warn "Homebrew not found. PowerShell may need to be installed manually."
    else
        install_homebrew
    fi
else
    log_ok "Homebrew is available"
fi

log_step "2/$TOTAL_STEPS" "Checking for PowerShell Core..."
if ! command -v pwsh &> /dev/null; then
    log_info "PowerShell not found. Installing via Homebrew..."
    if command -v brew &> /dev/null; then
        brew install --cask powershell
    else
        log_error "Cannot install PowerShell without Homebrew."
        log_info "Please install PowerShell manually from: https://github.com/PowerShell/PowerShell/releases"
        exit 1
    fi
else
    log_ok "PowerShell is installed: $(pwsh --version)"
fi

log_step "3/$TOTAL_STEPS" "Creating directory structure..."
mkdir -p "$INSTALL_DIR/scripts/core"
mkdir -p "$DATA_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

if [ "$IS_ROOT" = true ]; then
    chmod 755 "$INSTALL_DIR"
    chmod 750 "$DATA_DIR" "$CONFIG_DIR"
    chmod 750 "$LOG_DIR"
fi
log_ok "Directories created"

log_step "4/$TOTAL_STEPS" "Installing RMM Client Agent..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/core/RMM-Client.ps1" ]; then
    cp "$SCRIPT_DIR/scripts/core/RMM-Client.ps1" "$INSTALL_DIR/scripts/core/"
    log_ok "Client agent installed from local source"
else
    curl -sL "https://raw.githubusercontent.com/mytech-today-now/RMM/main/scripts/core/RMM-Client.ps1" \
         -o "$INSTALL_DIR/scripts/core/RMM-Client.ps1" 2>/dev/null || {
        log_error "Could not download client script"
        exit 1
    }
    log_ok "Client agent downloaded from repository"
fi

log_step "5/$TOTAL_STEPS" "Creating command-line wrapper..."
mkdir -p "$(dirname "$BIN_LINK")"
cat > "$BIN_LINK" << EOF
#!/bin/bash
# myTech.Today RMM Client wrapper
exec pwsh -NoProfile -File "$INSTALL_DIR/scripts/core/RMM-Client.ps1" "\$@"
EOF
chmod +x "$BIN_LINK"
log_ok "Wrapper created: $BIN_LINK"

log_step "6/$TOTAL_STEPS" "Configuring launchd service..."
create_launchd_plist

# Device registration
log_step "7/$TOTAL_STEPS" "Device registration..."
if [ -n "$SERVER_URL" ] && [ -n "$PAIRING_CODE" ]; then
    log_info "Registering with server..."
    pwsh -NoProfile -Command "& '$INSTALL_DIR/scripts/core/RMM-Client.ps1' -ServerUrl '$SERVER_URL' -PairingCode '$PAIRING_CODE'" || {
        log_warn "Registration failed. You can register later using: rmm-client --register"
    }
else
    log_info "Skipping registration (no server/code provided)"
fi

# Final summary
if [ "$SILENT" = false ]; then
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  Installation Complete!${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "Installation Summary:"
    echo -e "  ${GRAY}Mode:${NC}    $INSTALL_MODE"
    echo -e "  ${GRAY}Program:${NC} $INSTALL_DIR"
    echo -e "  ${GRAY}Data:${NC}    $DATA_DIR"
    echo -e "  ${GRAY}Logs:${NC}    $LOG_DIR"
    echo ""
    echo -e "Service Management:"
    if [ "$IS_ROOT" = true ]; then
        echo -e "  ${YELLOW}sudo launchctl load $LAUNCH_PLIST${NC}       # Start service"
        echo -e "  ${YELLOW}sudo launchctl unload $LAUNCH_PLIST${NC}     # Stop service"
    else
        echo -e "  ${YELLOW}launchctl load $LAUNCH_PLIST${NC}   # Start agent"
        echo -e "  ${YELLOW}launchctl unload $LAUNCH_PLIST${NC} # Stop agent"
    fi
    echo ""
    echo -e "To register with RMM server:"
    echo -e "  ${YELLOW}rmm-client --server http://your-server:8080 --code ABC123${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: macOS Security Permissions${NC}"
    echo -e "  You may need to grant Full Disk Access to PowerShell."
    echo -e "  See: docs/install-client-macos-instructions.html"
    echo ""
    echo -e "To uninstall:"
    if [ "$IS_ROOT" = true ]; then
        echo -e "  ${YELLOW}sudo ./uninstall-client-macos.sh${NC}"
    else
        echo -e "  ${YELLOW}./uninstall-client-macos.sh${NC}"
    fi
    echo ""
fi

exit 0
