#!/bin/bash
#
# myTech.Today RMM - MacOS Client Installation Script
# Lightweight installer for client devices that will be managed by an RMM server
#
# Usage:
#   ./install-client-macos.sh
#   ./install-client-macos.sh --server http://192.168.1.100:8080 --code ABC123
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
echo -e "${CYAN}  myTech.Today RMM - MacOS Client${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Installation paths
INSTALL_DIR="$HOME/myTech.Today/RMM"
MODULE_DIR="$HOME/.local/share/powershell/Modules/RMM"

# Check for Homebrew
echo -e "${CYAN}[1/4] Checking for Homebrew...${NC}"
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}Homebrew not found. Installing...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -f "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo -e "${GREEN}Homebrew is installed.${NC}"
fi

# Install PowerShell Core
echo -e "${CYAN}[2/4] Checking for PowerShell Core...${NC}"
if ! command -v pwsh &> /dev/null; then
    echo -e "${YELLOW}PowerShell not found. Installing via Homebrew...${NC}"
    brew install --cask powershell
else
    echo -e "${GREEN}PowerShell is installed: $(pwsh --version)${NC}"
fi

# Create directories and download client script
echo -e "${CYAN}[3/4] Installing RMM Client Agent...${NC}"
mkdir -p "$INSTALL_DIR/scripts/core"
mkdir -p "$MODULE_DIR"

# Download client script from GitHub or copy from local
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/scripts/core/RMM-Client.ps1" ]; then
    cp "$SCRIPT_DIR/scripts/core/RMM-Client.ps1" "$INSTALL_DIR/scripts/core/"
    echo -e "${GREEN}Client agent installed from local source.${NC}"
else
    # Download from GitHub
    curl -sL "https://raw.githubusercontent.com/mytech-today-now/RMM/main/scripts/core/RMM-Client.ps1" \
         -o "$INSTALL_DIR/scripts/core/RMM-Client.ps1" 2>/dev/null || {
        echo -e "${RED}[ERROR] Could not download client script.${NC}"
        echo -e "${YELLOW}Please copy RMM-Client.ps1 to: $INSTALL_DIR/scripts/core/${NC}"
    }
fi

# Create a convenience wrapper script
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
    echo -e "To register this device with an RMM server, run:"
    echo -e "  ${YELLOW}~/myTech.Today/rmm-client --help${NC}"
    echo ""
    echo -e "Or run interactively:"
    echo -e "  ${YELLOW}pwsh $INSTALL_DIR/scripts/core/RMM-Client.ps1 -Interactive${NC}"
    echo ""
    echo -e "Your administrator will provide:"
    echo -e "  1. The RMM server URL"
    echo -e "  2. A 6-character pairing code"
    echo ""
fi

