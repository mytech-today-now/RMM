#!/bin/bash
#
# myTech.Today RMM - MacOS Server Installation Script
# Installs PowerShell Core and the full RMM server module on MacOS
#
# For CLIENT-ONLY installation (to be managed by an RMM server), use:
#   ./install-client-macos.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  myTech.Today RMM - MacOS Installer${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Installation paths
INSTALL_DIR="$HOME/myTech.Today/RMM"
DATA_DIR="$HOME/myTech.Today/data"
SECRETS_DIR="$HOME/myTech.Today/secrets"
LOGS_DIR="$HOME/myTech.Today/logs"
MODULE_DIR="$HOME/.local/share/powershell/Modules/RMM"

# Check if running as root (not recommended)
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}[WARNING] Running as root is not recommended.${NC}"
    echo -e "${YELLOW}          Consider running as a regular user.${NC}"
    echo ""
fi

# Check for Homebrew
echo -e "${CYAN}[1/6] Checking for Homebrew...${NC}"
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}Homebrew not found. Installing...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo -e "${GREEN}Homebrew is installed.${NC}"
fi

# Install PowerShell Core
echo -e "${CYAN}[2/6] Checking for PowerShell Core...${NC}"
if ! command -v pwsh &> /dev/null; then
    echo -e "${YELLOW}PowerShell not found. Installing via Homebrew...${NC}"
    brew install --cask powershell
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

# Copy config
if [ -d "$SCRIPT_DIR/config" ]; then
    cp -R "$SCRIPT_DIR/config" "$INSTALL_DIR/"
fi

# Copy docs
if [ -d "$SCRIPT_DIR/docs" ]; then
    cp -R "$SCRIPT_DIR/docs" "$INSTALL_DIR/"
fi

# Install PowerShell module
echo -e "${CYAN}[5/6] Installing PowerShell module...${NC}"
cp "$INSTALL_DIR/scripts/core/RMM-Core.psm1" "$MODULE_DIR/RMM.psm1"
cp "$INSTALL_DIR/scripts/core/RMM.psd1" "$MODULE_DIR/RMM.psd1"

# Update module paths for Unix
sed -i '' 's|\\|/|g' "$MODULE_DIR/RMM.psm1" 2>/dev/null || true

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
echo -e "Module Directory:       ${CYAN}$MODULE_DIR${NC}"
echo ""
echo -e "To use RMM, run:"
echo -e "  ${YELLOW}pwsh${NC}"
echo -e "  ${YELLOW}Import-Module RMM${NC}"
echo -e "  ${YELLOW}Get-RMMDevice${NC}"
echo ""
echo -e "To start the web dashboard:"
echo -e "  ${YELLOW}pwsh $INSTALL_DIR/scripts/ui/Start-WebDashboard.ps1${NC}"
echo ""

