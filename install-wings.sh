#!/bin/bash

#############################################
# Wings-Dedup Installation Script
# Copyright (c) srvl Labs
#
# Complete Installation, Update, and Uninstall Utility
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# File locations
DEFAULT_BORG_REPO="/var/lib/pterodactyl/backups/borg-repo"
CONFIG_FILE="/etc/pterodactyl/config.yml"
WINGS_BINARY="/usr/local/bin/wings"
BACKUP_BINARY_PATH="/usr/local/bin/wings.original"

# --- Utility Functions ---

# Function to prompt for passphrase with minimum length and confirmation
prompt_passphrase() {
    local prompt="$1"
    local var_name="$2"
    local min_length="$3"
    local value=""

    while true; do
        echo -en "$prompt"
        read -s value
        echo ""
        if [ -z "$value" ]; then
            echo -e "${RED}  ✗ Passphrase is required.${NC}"
        elif [ ${#value} -lt $min_length ]; then
            echo -e "${RED}  ✗ Passphrase must be at least $min_length characters.${NC}"
        else
            echo -n "  Confirm passphrase: "
            read -s confirm
            echo ""
            if [ "$value" != "$confirm" ]; then
                echo -e "${RED}  ✗ Passphrases do not match. Try again.${NC}"
            else
                break
            fi
        fi
        echo ""
    done
    eval "$var_name='$value'"
}

# Function to prompt for required input
prompt_required() {
    local prompt="$1"
    local var_name="$2"
    local value=""

    while [ -z "$value" ]; do
        echo -en "$prompt"
        read -r value
        if [ -z "$value" ]; then
            echo -e "${RED}  ✗ This field is required.${NC}"
        fi
    done
    eval "$var_name='$value'"
}

# Function to prompt with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local value=""

    echo -en "$prompt [${CYAN}$default${NC}]: "
    read -r value
    if [ -z "$value" ]; then
        value="$default"
    fi
    eval "$var_name='$value'"
}

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ "$1" != "menu" ]; then
        echo ""
        echo -e "${RED}==========================================="
        echo "Operation failed!"
        echo -e "===========================================${NC}"
        if [ -f "$BACKUP_BINARY_PATH" ]; then
            echo -e "${YELLOW}A backup exists. You can restore the original Wings binary using the '2) Uninstall' option in the script menu.${NC}"
        fi
        echo -e "${YELLOW}For support, contact srvl Labs${NC}"
    fi
}
trap 'cleanup $1' EXIT

# --- Core Installation Logic ---

install_wings_dedup() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║               Wings-Dedup Installation/Update             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Step 1: Pre-flight Checks (Arch, Docker)
    echo -e "${BLUE}${BOLD}[Step 1/6] Pre-flight checks...${NC}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) EXPECTED_ARCH="x86-64";;
        aarch64|arm64) EXPECTED_ARCH="aarch64";;
        *) echo -e "  ${RED}✗ Unsupported architecture: ${ARCH}${NC}"; exit 1;;
    esac
    echo -e "  ${GREEN}✓${NC} Architecture: ${CYAN}${ARCH}${NC}"
    command -v docker &> /dev/null || { echo -e "  ${RED}✗ Docker is not installed${NC}"; exit 1; }
    docker info &> /dev/null || { echo -e "  ${RED}✗ Docker daemon is not running${NC}"; exit 1; }
    echo -e "  ${GREEN}✓${NC} Docker running"
    if [ ! -f "./wings" ]; then
        echo -e "  ${YELLOW}Binary not found. Downloading latest wings-dedup...${NC}"
        
        # Download the binary (Replace 'main' with your specific release tag if needed)
        curl -L -o wings https://github.com/srvl/wings-dedup-releases/raw/main/wings
        
        # Verify download succeeded
        if [ ! -f "./wings" ]; then
            echo -e "  ${RED}✗ Failed to download wings binary!${NC}"
            exit 1
        fi
        
        chmod +x wings
        echo -e "  ${GREEN}✓${NC} Download complete"
    fi
    
    # Check binary compatibility
    if ! file ./wings | grep -qE "(executable|ELF)"; then
        echo -e "  ${RED}✗ Invalid binary file${NC}"; exit 1;
    fi
    NEW_VERSION=$(./wings --version 2>/dev/null | head -1 || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Version: ${CYAN}${NEW_VERSION}${NC}"
    echo ""

    # Step 2: Stop Service and Backup Original Binary
    echo -e "${BLUE}${BOLD}[Step 2/6] Backup and Binary Installation...${NC}"

    # Stop Wings if running
    if systemctl is-active --quiet wings 2>/dev/null; then
        echo -e "  ${YELLOW}Stopping Wings service...${NC}"
        systemctl stop wings
        echo -e "  ${GREEN}✓${NC} Service stopped"
    fi
    
    # Backup old binary (if it exists and is not the backup itself)
    if [ -f "$WINGS_BINARY" ] && [ ! -f "$BACKUP_BINARY_PATH" ]; then
        cp "$WINGS_BINARY" "$BACKUP_BINARY_PATH"
        echo -e "  ${GREEN}✓${NC} Original Wings binary backed up to ${CYAN}${BACKUP_BINARY_PATH}${NC}"
    elif [ -f "$WINGS_BINARY" ] && [ -f "$BACKUP_BINARY_PATH" ]; then
        echo -e "  ${GREEN}✓${NC} Original backup already exists. Skipping new backup."
    fi

    # Install Wings-Dedup
    cp wings "$WINGS_BINARY"
    chmod +x "$WINGS_BINARY"
    rm -f  wings
    echo -e "  ${GREEN}✓${NC} Wings-Dedup installed to ${CYAN}${WINGS_BINARY}${NC}"

    # Create directories
    mkdir -p /etc/pterodactyl /var/lib/pterodactyl/{volumes,backups,archives} /var/log/pterodactyl /run/wings
    echo -e "  ${GREEN}✓${NC} Base directories ensured"
    echo ""


    # Step 3: Panel Configuration (using the newly installed binary)
    echo -e "${BLUE}${BOLD}[Step 3/6] Panel Configuration${NC}"

    if [ -f "$CONFIG_FILE" ]; then
        echo -e "  ${GREEN}✓${NC} Existing configuration found. Backup created."
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        NEED_AUTODEPLOY=false
    else
        NEED_AUTODEPLOY=true
    fi
    
    if [ "$NEED_AUTODEPLOY" = true ]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}Paste your 'wings configure' command from the Pterodactyl Panel${NC}"
        echo -e "  ${YELLOW}(Admin → Nodes → [Your Node] → Configuration tab)${NC}"
        echo ""
        echo -e "  ${CYAN}Example: cd /etc/pterodactyl && sudo $WINGS_BINARY configure --panel-url https://...${NC}"
        echo ""
        echo -e "  ${YELLOW}Paste the command and press Enter:${NC}"
        echo -n "  > "
        read -r AUTODEPLOY_CMD

        if [ -z "$AUTODEPLOY_CMD" ]; then
            echo -e "  ${RED}✗ No command provided${NC}"
            exit 1
        fi

        # We must replace 'wings' with the full path to ensure the *new* binary is used.
        if echo "$AUTODEPLOY_CMD" | grep -q "wings configure"; then
            AUTODEPLOY_CMD=$(echo "$AUTODEPLOY_CMD" | sed "s|wings configure|$WINGS_BINARY configure|g")
        fi

        echo ""
        echo -e "  ${YELLOW}Running configuration command...${NC}"
        eval "$AUTODEPLOY_CMD" || {
            echo -e "  ${RED}✗ Failed to run auto-deploy command${NC}"
            exit 1
        }

        # Verify config was created
        if [ ! -f "$CONFIG_FILE" ]; then
            echo -e "  ${RED}✗ Config file was not created by the command${NC}"
            exit 1
        fi

        echo -e "  ${GREEN}✓${NC} Panel configuration applied"
    else
        echo -e "  ${GREEN}✓${NC} Using existing configuration. Skipping Panel setup."
    fi
    echo ""

    # Step 4: Gather Additional Settings
    echo -e "${BLUE}${BOLD}[Step 4/6] Wings-Dedup Settings${NC}"
    echo -e "${CYAN}── License ──${NC}"
    prompt_required "  License Key: " LICENSE_KEY
    echo ""
    echo -e "${CYAN}── Borg Backup ──${NC}"
    prompt_with_default "  Repository Path" "$DEFAULT_BORG_REPO" BORG_REPO
    echo ""
    echo -e "  ${YELLOW}Choose a strong passphrase for encrypting backups.${NC}"
    echo -e "  ${RED}${BOLD}⚠ SAVE THIS! You cannot recover backups without it.${NC}"
    echo ""
    prompt_passphrase "  Borg Passphrase (min 10 chars): " BORG_PASSPHRASE 10
    echo ""
    # Discord Webhook prompt removed as requested.
    echo -e "${GREEN}✓ Settings collected${NC}"
    echo ""

    # Step 5: Install BorgBackup
    echo -e "${BLUE}${BOLD}[Step 5/6] Installing BorgBackup...${NC}"
    if command -v borg &> /dev/null; then
        BORG_VERSION=$(borg --version 2>/dev/null | head -1 || echo "unknown")
        echo -e "  ${GREEN}✓${NC} Already installed: ${CYAN}${BORG_VERSION}${NC}"
    else
        echo -e "  ${YELLOW}Installing BorgBackup...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get update -qq && apt-get install -y -qq borgbackup > /dev/null 2>&1
        elif command -v dnf &> /dev/null; then
            dnf install -y -q borgbackup > /dev/null 2>&1
        elif command -v yum &> /dev/null; then
            yum install -y -q epel-release > /dev/null 2>&1 || true
            yum install -y -q borgbackup > /dev/null 2>&1
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm borg > /dev/null 2>&1
        else
            echo -e "  ${RED}✗ Unknown package manager. Install BorgBackup manually.${NC}"; exit 1;
        fi
        BORG_VERSION=$(command -v borg &> /dev/null && borg --version 2>/dev/null || echo "installed")
        echo -e "  ${GREEN}✓${NC} Installed: ${CYAN}${BORG_VERSION}${NC}"
    fi
    mkdir -p "$BORG_REPO"
    echo ""

    # Step 6: Update Configuration and Start Service
    echo -e "${BLUE}${BOLD}[Step 6/6] Finalizing configuration and Starting Wings...${NC}"

    # Add/Update license
    if ! grep -q "^license:" "$CONFIG_FILE"; then
        echo -e "\n# Wings-Dedup License\nlicense:\n  license_key: \"${LICENSE_KEY}\"" >> "$CONFIG_FILE"
    else
        sed -i "s|license_key:.*|license_key: \"${LICENSE_KEY}\"|" "$CONFIG_FILE"
    fi
    echo -e "  ${GREEN}✓${NC} License key configured"

    # Add/Update borg settings
    BORG_CONFIG_TEXT="\n  borg:\n    enabled: true\n    repository_path: ${BORG_REPO}\n    passphrase: \"${BORG_PASSPHRASE}\""
    if ! grep -q "borg:" "$CONFIG_FILE"; then
        if grep -q "^backups:" "$CONFIG_FILE"; then
            # Inject borg config under existing 'backups:' section
            sed -i "/^backups:/a ${BORG_CONFIG_TEXT}" "$CONFIG_FILE"
        else
            # Create backups section and inject borg config
            sed -i "/^system:/a \ \ backups:" "$CONFIG_FILE"
            sed -i "/^backups:/a ${BORG_CONFIG_TEXT}" "$CONFIG_FILE"
        fi
    else
        # Update existing borg config
        sed -i "s|repository_path:.*|repository_path: ${BORG_REPO}|" "$CONFIG_FILE"
        sed -i "s|passphrase:.*|passphrase: \"${BORG_PASSPHRASE}\"|" "$CONFIG_FILE"
        sed -i "/borg:/,/enabled:/ s|enabled:.*|enabled: true|" "$CONFIG_FILE"
    fi
    echo -e "  ${GREEN}✓${NC} Borg backup configured"

    # Discord webhook configuration logic removed as requested.

    # Secure the config file
    chmod 600 "$CONFIG_FILE"
    echo -e "  ${GREEN}✓${NC} Config permissions secured"

    # Create/update systemd service
    cat > /etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon (Wings-Dedup)
After=docker.service network-online.target
Wants=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
RestartPreventExitStatus=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable wings > /dev/null 2>&1
    echo -e "  ${GREEN}✓${NC} Systemd service ready"
    echo ""

    # Start Wings section
    read -p "Start Wings now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        systemctl start wings
        sleep 2
        if systemctl is-active --quiet wings; then
            echo -e "${GREEN}✓ Wings-Dedup is running!${NC}"
            echo ""
        else
            echo -e "${RED}✗ Wings failed to start${NC}"
            echo -e "${YELLOW}Check logs: journalctl -u wings -e${NC}"
        fi
    else
        echo ""
        echo -e "${YELLOW}Start later: ${CYAN}systemctl start wings${NC}"
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Setup Complete!${NC}"
    echo -e "${YELLOW}Reminder: To enable Discord notifications for backups, manually edit:${NC}"
    echo -e "${CYAN}  ${CONFIG_FILE}${NC}"
    echo -e "${YELLOW}and add the webhook URL under the 'discord:' section like this:${NC}"
    echo -e "${CYAN}  discord:\n    webhook_url: \"YOUR_DISCORD_WEBHOOK_URL\"${NC}"
    echo -e "${BLUE}For support, contact srvl Labs${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    trap '' EXIT # Disable cleanup trap on success
    exit 0
}

# --- Core Uninstall/Restore Logic ---

uninstall_wings_dedup() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║               Wings-Dedup Uninstallation/Restore          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [ ! -f "$BACKUP_BINARY_PATH" ]; then
        echo -e "${RED}✗ Original Wings binary backup not found at ${CYAN}${BACKUP_BINARY_PATH}${NC}"
        echo -e "${YELLOW}Cannot proceed with restoration. You may need to manually reinstall standard Wings.${NC}"
        exit 1
    fi

    echo -e "${BLUE}${BOLD}[1/3] Stopping Wings service...${NC}"
    if systemctl is-active --quiet wings 2>/dev/null; then
        systemctl stop wings
        echo -e "  ${GREEN}✓${NC} Service stopped"
    else
        echo -e "  ${GREEN}✓${NC} Service was not running"
    fi
    echo ""

    echo -e "${BLUE}${BOLD}[2/3] Restoring original Wings binary...${NC}"
    cp "$BACKUP_BINARY_PATH" "$WINGS_BINARY"
    chmod +x "$WINGS_BINARY"
    rm -f "$BACKUP_BINARY_PATH"
    echo -e "  ${GREEN}✓${NC} Original binary restored to ${CYAN}${WINGS_BINARY}${NC}"
    echo -e "  ${GREEN}✓${NC} Backup file deleted"
    echo ""
    
    # Optional: Clean up Borg-Dedup configuration lines (license and borg sections)
    echo -e "${BLUE}${BOLD}[3/3] Cleaning up configuration...${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        # Remove license block
        sed -i '/# Wings-Dedup License/,+2d' "$CONFIG_FILE" 2>/dev/null
        
        # Remove borg block (under backups)
        sed -i '/^[[:space:]]*borg:/,/passphrase:.*"/d' "$CONFIG_FILE" 2>/dev/null

        echo -e "  ${GREEN}✓${NC} Wings-Dedup settings removed from config.yml"
        echo -e "  ${YELLOW}Note: The Borg repository data itself was NOT deleted.${NC}"
    else
        echo -e "  ${YELLOW}Note: Config file not found, skipping cleanup.${NC}"
    fi

    systemctl daemon-reload
    
    echo ""
    echo -e "${GREEN}==========================================="
    echo "Restoration Complete!"
    echo "===========================================${NC}"
    echo -e "${YELLOW}Your original Wings binary has been restored.${NC}"
    echo ""

    read -p "Start the original Wings service now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        systemctl start wings
        sleep 2
        if systemctl is-active --quiet wings; then
            echo -e "${GREEN}✓ Wings is running!${NC}"
        else
            echo -e "${RED}✗ Wings failed to start${NC}"
            echo -e "${YELLOW}Check logs: journalctl -u wings -e${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    trap '' EXIT # Disable cleanup trap on success
    exit 0
}

# --- Main Menu Logic ---

main_menu() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        echo -e "${YELLOW}Run with: sudo $0${NC}"
        exit 1
    fi

    while true; do
        echo -e "${GREEN}"
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║             srvl Labs Wings-Dedup Utility               ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        
        echo -e "${BOLD}Please select an option:${NC}"
        echo -e "  ${GREEN}1)${NC} ${BOLD}Install/Update${NC} Wings-Dedup"
        echo -e "  ${RED}2)${NC} ${BOLD}Uninstall/Restore${NC} Original Wings"
        echo -e "  ${YELLOW}3)${NC} Exit"
        echo ""
        
        read -p "Enter choice (1, 2, or 3): " -r CHOICE

        case "$CHOICE" in
            1)
                echo ""
                install_wings_dedup
                ;;
            2)
                echo ""
                uninstall_wings_dedup
                ;;
            3)
                echo -e "\n${BLUE}Exiting utility. Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
        echo ""
    done
}

# Run the main menu
main_menu "menu"
