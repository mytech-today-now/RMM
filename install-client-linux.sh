#!/bin/bash
#
# myTech.Today RMM - Linux Client Installation Script
# Lightweight installer for client devices that will be managed by an RMM server
# Supports: Ubuntu, Debian, CentOS, RHEL, Fedora
#
# Usage:
#   ./install-client-linux.sh
#   ./install-client-linux.sh --server http://192.168.1.100:8080 --code ABC123
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
SERVER_URL=""
PAIRING_CODE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --server|-s) SERVER_URL="$2"; shift 2 ;;
        --code|-c) PAIRING_CODE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--server URL] [--code CODE]"
            echo "  --server, -s  RMM server URL (e.g., http://192.168.1.100:8080)"
            echo "  --code, -c    6-character pairing code from administrator"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  myTech.Today RMM - Linux Client${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Installation paths
INSTALL_DIR="$HOME/myTech.Today/RMM"

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
    echo -e "${CYAN}Installing PowerShell Core...${NC}"
    case $DISTRO in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y wget apt-transport-https software-properties-common
            wget -q "https://packages.microsoft.com/config/$DISTRO/$VERSION/packages-microsoft-prod.deb"
            sudo dpkg -i packages-microsoft-prod.deb
            rm packages-microsoft-prod.deb
            sudo apt-get update
            sudo apt-get install -y powershell
            ;;
        centos|rhel|fedora)
            sudo rpm -Uvh https://packages.microsoft.com/config/rhel/7/packages-microsoft-prod.rpm 2>/dev/null || true
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
                exit 1
            fi
            ;;
    esac
    echo -e "${GREEN}PowerShell installed: $(pwsh --version)${NC}"
}

# Main installation
echo -e "${CYAN}[1/4] Detecting Linux distribution...${NC}"
detect_distro

# Check for PowerShell
echo -e "${CYAN}[2/4] Checking for PowerShell Core...${NC}"
if ! command -v pwsh &> /dev/null; then
    install_powershell
else
    echo -e "${GREEN}PowerShell is installed: $(pwsh --version)${NC}"
fi

# Create directories and install client
echo -e "${CYAN}[3/4] Installing RMM Client Agent...${NC}"
mkdir -p "$INSTALL_DIR/scripts/core"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/core/RMM-Client.ps1" ]; then
    cp "$SCRIPT_DIR/scripts/core/RMM-Client.ps1" "$INSTALL_DIR/scripts/core/"
    echo -e "${GREEN}Client agent installed from local source.${NC}"
else
    curl -sL "https://raw.githubusercontent.com/mytech-today-now/RMM/main/scripts/core/RMM-Client.ps1" \
         -o "$INSTALL_DIR/scripts/core/RMM-Client.ps1" 2>/dev/null || {
        echo -e "${RED}[ERROR] Could not download client script.${NC}"
    }
fi

# Create convenience wrapper
cat > "$HOME/myTech.Today/rmm-client" << 'EOF'
#!/bin/bash
pwsh "$HOME/myTech.Today/RMM/scripts/core/RMM-Client.ps1" "$@"
EOF
chmod +x "$HOME/myTech.Today/rmm-client"

echo -e "${GREEN}Client agent installed.${NC}"

# Register with server if credentials provided
echo -e "${CYAN}[4/4] Device Registration...${NC}"
if [ -n "$SERVER_URL" ] && [ -n "$PAIRING_CODE" ]; then
    echo -e "${YELLOW}Registering with server...${NC}"
    pwsh -NoProfile -Command "& '$INSTALL_DIR/scripts/core/RMM-Client.ps1' -ServerUrl '$SERVER_URL' -PairingCode '$PAIRING_CODE'"
else
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "To register with RMM server: ${YELLOW}~/myTech.Today/rmm-client -Interactive${NC}"
    echo ""
fi

