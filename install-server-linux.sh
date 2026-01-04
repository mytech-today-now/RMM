#!/bin/bash
# ============================================================================
# myTech.Today RMM Server - Linux Installation Script
# Enterprise-grade system-wide installer with systemd service
# ============================================================================
# For CLIENT-ONLY installation (managed endpoint), use: ./install-client-linux.sh
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
    INSTALL_DIR="/opt/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="/var/opt/myTech.Today/$SCRIPT_TITLE"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$DATA_ROOT/config"
    LOG_DIR="/var/log/myTech.Today/$SCRIPT_TITLE"
    MODULE_DIR="/opt/microsoft/powershell/7/Modules/RMM"
    SERVICE_FILE="/etc/systemd/system/mytech-rmm.service"
    BIN_LINK="/usr/local/bin/rmm"
else
    INSTALL_MODE="user"
    INSTALL_DIR="$HOME/.local/share/myTech.Today/$SCRIPT_TITLE"
    DATA_ROOT="$INSTALL_DIR"
    DATA_DIR="$DATA_ROOT/data"
    CONFIG_DIR="$HOME/.config/myTech.Today/$SCRIPT_TITLE"
    LOG_DIR="$INSTALL_DIR/logs"
    MODULE_DIR="$HOME/.local/share/powershell/Modules/RMM"
    SERVICE_FILE=""
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
    echo -e "${CYAN}║${NC}   ${BOLD}myTech.Today RMM Server - Linux Installer${NC}   v$VERSION  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ "$IS_ROOT" = true ]; then
        echo -e "  ${GREEN}●${NC} Running with root privileges - ${GREEN}System-wide installation${NC}"
    else
        echo -e "  ${YELLOW}●${NC} Running without root - ${YELLOW}Per-user installation${NC}"
        echo -e "    ${YELLOW}Run with sudo for system-wide install with service${NC}"
    fi
    echo ""
}

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION_ID=${VERSION_ID:-"unknown"}
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
    log_info "Detected: $DISTRO $VERSION_ID"
}

# Install PowerShell
install_powershell() {
    log_info "Installing PowerShell Core..."
    case $DISTRO in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq wget apt-transport-https software-properties-common
            wget -q "https://packages.microsoft.com/config/$DISTRO/${VERSION_ID}/packages-microsoft-prod.deb" -O /tmp/packages-microsoft-prod.deb
            dpkg -i /tmp/packages-microsoft-prod.deb
            rm /tmp/packages-microsoft-prod.deb
            apt-get update -qq
            apt-get install -y -qq powershell
            ;;
        centos|rhel|rocky|almalinux)
            rpm -Uvh https://packages.microsoft.com/config/rhel/8/packages-microsoft-prod.rpm 2>/dev/null || true
            if command -v dnf &>/dev/null; then
                dnf install -y -q powershell
            else
                yum install -y -q powershell
            fi
            ;;
        fedora)
            rpm -Uvh https://packages.microsoft.com/config/fedora/${VERSION_ID}/packages-microsoft-prod.rpm 2>/dev/null || true
            dnf install -y -q powershell
            ;;
        opensuse*|sles)
            zypper --non-interactive install powershell
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm powershell-bin 2>/dev/null || {
                log_warn "PowerShell not in repos. Trying AUR..."
                if command -v yay &>/dev/null; then
                    yay -S --noconfirm powershell-bin
                else
                    log_error "Install yay or powershell-bin manually from AUR"
                    exit 1
                fi
            }
            ;;
        *)
            if command -v snap &>/dev/null; then
                snap install powershell --classic
            else
                log_error "Unknown distro. Please install PowerShell manually."
                exit 1
            fi
            ;;
    esac
    log_ok "PowerShell installed: $(pwsh --version 2>/dev/null || echo 'check manually')"
}

show_banner
detect_distro

# Step 1: Check/Install PowerShell
log_info "[1/7] Checking PowerShell Core..."
if ! command -v pwsh &>/dev/null; then
    if [ "$IS_ROOT" = true ]; then
        install_powershell
    else
        log_error "PowerShell not found. Run installer with sudo to auto-install."
        exit 1
    fi
else
    log_ok "PowerShell $(pwsh --version) is installed"
fi

# Step 2: Create directories
log_info "[2/7] Creating directories..."
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" "$LOG_DIR"
mkdir -p "$(dirname "$MODULE_DIR")"
mkdir -p "$MODULE_DIR"
if [ "$IS_ROOT" = true ]; then
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$DATA_ROOT" "$DATA_DIR" "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
fi
log_ok "Directories created"

# Step 3: Copy files
log_info "[3/7] Copying RMM files..."
EXCLUDES="--exclude=.git --exclude=.augment --exclude=ai-prompts --exclude=tests --exclude=secrets --exclude=*.md --exclude=LICENSE --exclude=install-*.sh --exclude=uninstall-*.sh"
if [ -d "$SCRIPT_DIR/scripts" ]; then
    rsync -a $EXCLUDES "$SCRIPT_DIR/scripts" "$INSTALL_DIR/" 2>/dev/null || cp -R "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"
    [ -d "$SCRIPT_DIR/config" ] && { rsync -a $EXCLUDES "$SCRIPT_DIR/config" "$INSTALL_DIR/" 2>/dev/null || cp -R "$SCRIPT_DIR/config" "$INSTALL_DIR/"; }
    [ -d "$SCRIPT_DIR/docs" ] && { rsync -a $EXCLUDES "$SCRIPT_DIR/docs" "$INSTALL_DIR/" 2>/dev/null || cp -R "$SCRIPT_DIR/docs" "$INSTALL_DIR/"; }
    log_ok "Files copied to $INSTALL_DIR"
else
    log_error "scripts directory not found in $SCRIPT_DIR"
    exit 1
fi

# Step 4: Install PowerShell module
log_info "[4/7] Installing PowerShell module..."
cp "$INSTALL_DIR/scripts/core/RMM-Core.psm1" "$MODULE_DIR/RMM.psm1"
cp "$INSTALL_DIR/scripts/core/RMM.psd1" "$MODULE_DIR/RMM.psd1"
log_ok "Module installed to $MODULE_DIR"

# Step 5: Install dependencies
log_info "[5/7] Installing PowerShell dependencies..."
pwsh -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'SilentlyContinue'
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    @('PSSQLite','ImportExcel','PSWriteHTML') | ForEach-Object {
        if (-not (Get-Module -ListAvailable -Name \$_)) {
            Install-Module -Name \$_ -Scope $([ "$IS_ROOT" = true ] && echo "AllUsers" || echo "CurrentUser") -Force -AllowClobber
        }
    }
" 2>/dev/null
log_ok "Dependencies installed"

# Step 6: Create wrapper script
log_info "[6/7] Creating launcher..."
mkdir -p "$(dirname "$BIN_LINK")"
cat > "$BIN_LINK" << 'LAUNCHER'
#!/bin/bash
pwsh -NoProfile -Command "Import-Module RMM -Force; $args" -- "$@"
LAUNCHER
chmod +x "$BIN_LINK"
log_ok "Launcher created at $BIN_LINK"

# Step 7: Create systemd service (root only)
if [ "$IS_ROOT" = true ]; then
    log_info "[7/7] Creating systemd service..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=myTech.Today RMM Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/pwsh -NoProfile -File $INSTALL_DIR/scripts/ui/Start-WebDashboard.ps1
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
RestartSec=10
User=root
Environment=HOME=/root
StandardOutput=append:$LOG_DIR/service.log
StandardError=append:$LOG_DIR/service-error.log

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable mytech-rmm 2>/dev/null
    log_ok "Service 'mytech-rmm' created and enabled"
else
    log_info "[7/7] Skipping service (requires root)"
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
    echo -e "  ${BOLD}Start service:${NC}     ${YELLOW}sudo systemctl start mytech-rmm${NC}"
    echo -e "  ${BOLD}Check status:${NC}      ${YELLOW}sudo systemctl status mytech-rmm${NC}"
fi
echo -e "  ${BOLD}Use RMM CLI:${NC}       ${YELLOW}rmm${NC}"
echo -e "  ${BOLD}Import module:${NC}     ${YELLOW}pwsh -c 'Import-Module RMM'${NC}"
echo ""
exit 0

