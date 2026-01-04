#!/bin/bash
#
# myTech.Today RMM - Linux Client Installation Script
# Enterprise-grade installer for Linux client devices
# Supports: Ubuntu, Debian, CentOS, RHEL, Fedora, openSUSE, Arch
#
# System-wide installation (with sudo/root):
#   Program Files: /opt/myTech.Today/RMM-Client/
#   Data/Config:   /var/opt/myTech.Today/RMM-Client/
#   Logs:          /var/log/myTech.Today/RMM-Client/
#   Service:       /etc/systemd/system/mytech-rmm-client.service
#
# Per-user fallback (without sudo):
#   All files:     ~/.local/share/myTech.Today/RMM-Client/
#   Config:        ~/.config/myTech.Today/RMM-Client/
#
# Usage:
#   sudo ./install-client-linux.sh                    # System-wide (recommended)
#   ./install-client-linux.sh                         # Per-user fallback
#   sudo ./install-client-linux.sh --server URL --code ABC123 --silent
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
    INSTALL_DIR="/opt/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="/var/opt/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$DATA_ROOT/config"
    LOG_DIR="/var/log/myTech.Today/$SCRIPT_TITLE"
    SERVICE_FILE="/etc/systemd/system/mytech-rmm-client.service"
    BIN_LINK="/usr/local/bin/rmm-client"
else
    INSTALL_MODE="user"
    INSTALL_DIR="$HOME/.local/share/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="$INSTALL_DIR"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$HOME/.config/myTech.Today/$SCRIPT_TITLE"
    LOG_DIR="$DATA_ROOT/logs"
    SERVICE_FILE=""
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
    echo -e "${CYAN}  myTech.Today RMM - Linux Client Installer v$VERSION${NC}"
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

# Detect Linux distribution
DISTRO="unknown"
VERSION=""
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
    elif [ -f /etc/SuSE-release ] || [ -f /etc/SUSE-brand ]; then
        DISTRO="opensuse"
    fi
    log_info "Detected distribution: $DISTRO $VERSION"
}

# Install PowerShell based on distro
install_powershell() {
    log_info "Installing PowerShell Core..."
    case $DISTRO in
        ubuntu|debian|linuxmint|pop)
            apt-get update -qq
            apt-get install -y -qq wget apt-transport-https software-properties-common
            wget -q "https://packages.microsoft.com/config/$DISTRO/${VERSION:-22.04}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb 2>/dev/null || \
            wget -q "https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
            dpkg -i /tmp/packages-microsoft-prod.deb
            rm -f /tmp/packages-microsoft-prod.deb
            apt-get update -qq
            apt-get install -y -qq powershell
            ;;
        centos|rhel|fedora|rocky|alma)
            rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm 2>/dev/null || true
            if command -v dnf &> /dev/null; then
                dnf install -y -q powershell
            else
                yum install -y -q powershell
            fi
            ;;
        opensuse|sles)
            rpm --import https://packages.microsoft.com/keys/microsoft.asc
            zypper addrepo https://packages.microsoft.com/rhel/7/prod/ microsoft-prod 2>/dev/null || true
            zypper install -y powershell
            ;;
        arch|manjaro)
            if command -v yay &> /dev/null; then
                yay -S --noconfirm powershell-bin
            elif command -v paru &> /dev/null; then
                paru -S --noconfirm powershell-bin
            else
                log_warn "Install powershell-bin from AUR manually"
            fi
            ;;
        *)
            log_warn "Unknown distribution. Attempting snap install..."
            if command -v snap &> /dev/null; then
                snap install powershell --classic
            else
                log_error "Could not install PowerShell. Please install manually."
                log_info "Visit: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
                exit 1
            fi
            ;;
    esac
    log_ok "PowerShell installed: $(pwsh --version 2>/dev/null || echo 'version unknown')"
}

# Create systemd service file
create_systemd_service() {
    if [ "$IS_ROOT" = true ] && command -v systemctl &> /dev/null; then
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=myTech.Today RMM Client Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/pwsh -NoProfile -NonInteractive -File "$INSTALL_DIR/scripts/core/RMM-Client.ps1" -Daemon
Restart=on-failure
RestartSec=30
User=root
WorkingDirectory=$DATA_DIR
StandardOutput=append:$LOG_DIR/service.log
StandardError=append:$LOG_DIR/service-error.log

# Security hardening
NoNewPrivileges=false
ProtectSystem=strict
ReadWritePaths=$DATA_DIR $LOG_DIR $CONFIG_DIR

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        log_ok "Systemd service created: mytech-rmm-client.service"
    fi
}

# Main installation steps
TOTAL_STEPS=6
[ "$IS_ROOT" = true ] && TOTAL_STEPS=7

log_step "1/$TOTAL_STEPS" "Detecting Linux distribution..."
detect_distro

log_step "2/$TOTAL_STEPS" "Checking for PowerShell Core..."
if ! command -v pwsh &> /dev/null; then
    if [ "$IS_ROOT" = true ]; then
        install_powershell
    else
        log_error "PowerShell is not installed. Please run with sudo to install, or install manually."
        log_info "Visit: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
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

if [ "$IS_ROOT" = true ]; then
    log_step "6/$TOTAL_STEPS" "Configuring systemd service..."
    create_systemd_service
fi

# Device registration
STEP_NUM=$TOTAL_STEPS
log_step "$STEP_NUM/$TOTAL_STEPS" "Device registration..."
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
    if [ "$IS_ROOT" = true ]; then
        echo -e "Service Management:"
        echo -e "  ${YELLOW}sudo systemctl start mytech-rmm-client${NC}   # Start service"
        echo -e "  ${YELLOW}sudo systemctl enable mytech-rmm-client${NC}  # Enable at boot"
        echo -e "  ${YELLOW}sudo systemctl status mytech-rmm-client${NC}  # Check status"
        echo ""
    fi
    echo -e "To register with RMM server:"
    echo -e "  ${YELLOW}rmm-client --server http://your-server:8080 --code ABC123${NC}"
    echo ""
    echo -e "To uninstall:"
    if [ "$IS_ROOT" = true ]; then
        echo -e "  ${YELLOW}sudo ./uninstall-client-linux.sh${NC}"
    else
        echo -e "  ${YELLOW}./uninstall-client-linux.sh${NC}"
    fi
    echo ""
fi

exit 0
