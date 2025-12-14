#!/bin/bash
#
# myTech.Today RMM - Linux Server Installation Script
# Installs PowerShell Core and the full RMM server module on Linux
# Supports: Ubuntu, Debian, CentOS, RHEL, Fedora
#
# For CLIENT-ONLY installation (to be managed by an RMM server), use:
#   ./install-client-linux.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  myTech.Today RMM - Linux Installer${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Installation paths
INSTALL_DIR="$HOME/myTech.Today/RMM"
DATA_DIR="$HOME/myTech.Today/data"
SECRETS_DIR="$HOME/myTech.Today/secrets"
LOGS_DIR="$HOME/myTech.Today/logs"
MODULE_DIR="$HOME/.local/share/powershell/Modules/RMM"

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
    echo -e "${CYAN}Detected: $DISTRO $VERSION${NC}"
}

# Install PowerShell based on distro
install_powershell() {
    echo -e "${CYAN}[2/6] Installing PowerShell Core...${NC}"
    
    case $DISTRO in
        ubuntu|debian)
            # Install prerequisites
            sudo apt-get update
            sudo apt-get install -y wget apt-transport-https software-properties-common
            
            # Download and register Microsoft repository
            wget -q "https://packages.microsoft.com/config/$DISTRO/$VERSION/packages-microsoft-prod.deb"
            sudo dpkg -i packages-microsoft-prod.deb
            rm packages-microsoft-prod.deb
            
            # Install PowerShell
            sudo apt-get update
            sudo apt-get install -y powershell
            ;;
        centos|rhel|fedora)
            # Register Microsoft repository
            sudo rpm -Uvh https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm 2>/dev/null || true
            
            # Install PowerShell
            if command -v dnf &> /dev/null; then
                sudo dnf install -y powershell
            else
                sudo yum install -y powershell
            fi
            ;;
        *)
            echo -e "${YELLOW}Unknown distribution. Attempting snap install...${NC}"
            if command -v snap &> /dev/null; then
                sudo snap install powershell --classic
            else
                echo -e "${RED}[ERROR] Could not install PowerShell. Please install manually.${NC}"
                echo -e "Visit: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux"
                exit 1
            fi
            ;;
    esac
    
    echo -e "${GREEN}PowerShell installed: $(pwsh --version)${NC}"
}

# Main installation
echo -e "${CYAN}[1/6] Detecting Linux distribution...${NC}"
detect_distro

# Check for PowerShell
if ! command -v pwsh &> /dev/null; then
    install_powershell
else
    echo -e "${GREEN}PowerShell is installed: $(pwsh --version)${NC}"
fi

# Create directories
echo -e "${CYAN}[3/6] Creating directories...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$SECRETS_DIR"
mkdir -p "$LOGS_DIR"
mkdir -p "$MODULE_DIR"
chmod 700 "$SECRETS_DIR"
echo -e "${GREEN}Directories created.${NC}"

# Copy RMM files
echo -e "${CYAN}[4/6] Copying RMM files...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy scripts
if [ -d "$SCRIPT_DIR/scripts" ]; then
    cp -R "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"
    echo -e "${GREEN}Scripts copied.${NC}"
else
    echo -e "${RED}[ERROR] scripts directory not found!${NC}"
    exit 1
fi

# Copy config and docs
[ -d "$SCRIPT_DIR/config" ] && cp -R "$SCRIPT_DIR/config" "$INSTALL_DIR/"
[ -d "$SCRIPT_DIR/docs" ] && cp -R "$SCRIPT_DIR/docs" "$INSTALL_DIR/"

# Install PowerShell module
echo -e "${CYAN}[5/6] Installing PowerShell module...${NC}"
cp "$INSTALL_DIR/scripts/core/RMM-Core.psm1" "$MODULE_DIR/RMM.psm1"
cp "$INSTALL_DIR/scripts/core/RMM.psd1" "$MODULE_DIR/RMM.psd1"

# Install required PowerShell modules
echo -e "${CYAN}[6/6] Installing PowerShell dependencies...${NC}"
pwsh -NoProfile -Command "
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
        Install-Module -Name PSSQLite -Scope CurrentUser -Force
    }
    Write-Host 'Dependencies installed.' -ForegroundColor Green
"

# Initialize RMM
echo -e "${CYAN}Initializing RMM...${NC}"
pwsh -NoProfile -Command "
    Import-Module RMM -Force
    Initialize-RMM
    Write-Host 'RMM initialized successfully!' -ForegroundColor Green
"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Installation Directory: ${CYAN}$INSTALL_DIR${NC}"
echo -e "Data Directory:         ${CYAN}$DATA_DIR${NC}"
echo ""
echo -e "To use RMM: ${YELLOW}pwsh -c 'Import-Module RMM; Get-RMMDevice'${NC}"
echo -e "Web dashboard: ${YELLOW}pwsh $INSTALL_DIR/scripts/ui/Start-WebDashboard.ps1${NC}"
echo ""

