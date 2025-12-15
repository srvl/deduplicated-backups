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
    printf -v "$var_name" '%s' "$value"
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
    printf -v "$var_name" '%s' "$value"
}

# Function to prompt optional (can be empty)
prompt_optional() {
    local prompt="$1"
    local var_name="$2"
    local value=""

    echo -en "$prompt"
    read -r value
    printf -v "$var_name" '%s' "$value"
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
            echo -e "${YELLOW}A backup exists. You can restore the original Wings binary using the '2) Uninstall' option.${NC}"
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

    # Step 1: Pre-flight Checks
    echo -e "${BLUE}${BOLD}[Step 1/5] Pre-flight checks...${NC}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ARCH_NAME="amd64"
            BINARY_NAME="wings_amd"
            ;;
        aarch64|arm64)
            ARCH_NAME="arm64"
            BINARY_NAME="wings_arm"
            ;;
        *)
            echo -e "  ${RED}✗ Unsupported architecture: ${ARCH}${NC}"
            exit 1
            ;;
    esac
    echo -e "  ${GREEN}✓${NC} Architecture: ${CYAN}${ARCH} (${ARCH_NAME})${NC}"
    
    command -v docker &> /dev/null || { echo -e "  ${RED}✗ Docker is not installed${NC}"; exit 1; }
    docker info &> /dev/null || { echo -e "  ${RED}✗ Docker daemon is not running${NC}"; exit 1; }
    echo -e "  ${GREEN}✓${NC} Docker running"
    
    if [ ! -f "./wings" ]; then
        echo -e "  ${YELLOW}Binary not found. Downloading latest wings-dedup for ${ARCH_NAME}...${NC}"
        
        # Fetch latest release tag from GitHub API
        LATEST_TAG=$(curl -s https://api.github.com/repos/srvl/deduplicated-backups/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -z "$LATEST_TAG" ]; then
            echo -e "  ${RED}✗ Failed to fetch latest release tag${NC}"
            echo -e "  ${YELLOW}  Falling back to v2.2...${NC}"
            LATEST_TAG="v2.2"
        else
            echo -e "  ${GREEN}✓${NC} Latest release: ${CYAN}${LATEST_TAG}${NC}"
        fi
        
        DOWNLOAD_URL="https://github.com/srvl/deduplicated-backups/releases/download/${LATEST_TAG}/${BINARY_NAME}"
        CHECKSUM_URL="https://github.com/srvl/deduplicated-backups/releases/download/${LATEST_TAG}/${BINARY_NAME}.sha256"
        
        if curl -f -L -o wings "$DOWNLOAD_URL"; then
            echo -e "  ${GREEN}✓${NC} Download complete (${BINARY_NAME})"
            chmod +x wings
            
            # Verify SHA256 checksum if available
            if curl -f -s -L -o wings.sha256 "$CHECKSUM_URL" 2>/dev/null; then
                EXPECTED_SHA256=$(cat wings.sha256 | awk '{print $1}')
                ACTUAL_SHA256=$(sha256sum wings | awk '{print $1}')
                if [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
                    echo -e "  ${RED}✗ SHA256 checksum mismatch!${NC}"
                    echo -e "  ${YELLOW}  Expected: ${EXPECTED_SHA256}${NC}"
                    echo -e "  ${YELLOW}  Actual:   ${ACTUAL_SHA256}${NC}"
                    rm -f wings wings.sha256
                    exit 1
                fi
                echo -e "  ${GREEN}✓${NC} SHA256 checksum verified"
                rm -f wings.sha256
            else
                echo -e "  ${YELLOW}○${NC} No checksum file available, skipping verification"
            fi
        else
            echo -e "  ${RED}✗ Failed to download wings binary!${NC}"
            echo -e "  ${YELLOW}  URL: ${DOWNLOAD_URL}${NC}"
            echo -e "  ${YELLOW}  Possible causes: Repository is private or file name mismatch.${NC}"
            exit 1
        fi
    fi
    
    if ! file ./wings | grep -qE "(executable|ELF)"; then
        echo -e "  ${RED}✗ Invalid binary file${NC}"; exit 1;
    fi
    NEW_VERSION=$(./wings --version 2>/dev/null | head -1 || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Version: ${CYAN}${NEW_VERSION}${NC}"
    echo ""

    # Step 2: Stop Service and Install Binary
    echo -e "${BLUE}${BOLD}[Step 2/5] Installing Wings-Dedup binary...${NC}"

    if systemctl is-active --quiet wings 2>/dev/null; then
        echo -e "  ${YELLOW}Stopping Wings service...${NC}"
        systemctl stop wings
        echo -e "  ${GREEN}✓${NC} Service stopped"
    fi
    
    # Backup old binary
    if [ -f "$WINGS_BINARY" ] && [ ! -f "$BACKUP_BINARY_PATH" ]; then
        cp "$WINGS_BINARY" "$BACKUP_BINARY_PATH"
        echo -e "  ${GREEN}✓${NC} Original Wings backed up to ${CYAN}${BACKUP_BINARY_PATH}${NC}"
    elif [ -f "$WINGS_BINARY" ] && [ -f "$BACKUP_BINARY_PATH" ]; then
        echo -e "  ${GREEN}✓${NC} Backup already exists, skipping"
    fi

    cp wings "$WINGS_BINARY"
    chmod +x "$WINGS_BINARY"
    rm -f wings
    echo -e "  ${GREEN}✓${NC} Wings-Dedup installed to ${CYAN}${WINGS_BINARY}${NC}"

    mkdir -p /etc/pterodactyl /var/lib/pterodactyl/{volumes,backups,archives} /var/log/pterodactyl /run/wings
    echo -e "  ${GREEN}✓${NC} Directories created"

    # Create pterodactyl user if not exists and fix home directory
    if id "pterodactyl" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Pterodactyl user exists"
    else
        useradd --system --no-create-home --shell /bin/false pterodactyl 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Pterodactyl user created"
    fi

    # Ensure home directory exists (required for borg pre-flight)
    mkdir -p /home/pterodactyl
    chown pterodactyl:pterodactyl /home/pterodactyl
    echo -e "  ${GREEN}✓${NC} Pterodactyl home directory ready"

    # Fix directory ownership (required for borg pre-flight)
    chown -R pterodactyl:pterodactyl /var/lib/pterodactyl
    echo -e "  ${GREEN}✓${NC} Directory ownership fixed"
    echo ""

    # Step 3: Panel Configuration (FIRST - before asking for dedup settings)
    echo -e "${BLUE}${BOLD}[Step 3/5] Panel Configuration${NC}"

    if [ -f "$CONFIG_FILE" ]; then
        echo -e "  ${GREEN}✓${NC} Existing config.yml found"
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "  ${GREEN}✓${NC} Backup created"
        
        echo ""
        echo -e "  ${YELLOW}Do you want to re-run the panel auto-deploy command?${NC}"
        read -p "  Re-configure from panel? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            RUN_AUTODEPLOY=true
        else
            RUN_AUTODEPLOY=false
        fi
    else
        RUN_AUTODEPLOY=true
    fi
    
    if [ "$RUN_AUTODEPLOY" = true ]; then
        echo ""
        echo -e "  ${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${YELLOW}${BOLD}Paste the 'wings configure' command from your Pterodactyl Panel${NC}"
        echo -e "  ${YELLOW}(Admin → Nodes → [Your Node] → Configuration tab)${NC}"
        echo -e "  ${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -n "  > "
        read -r AUTODEPLOY_CMD

        if [ -z "$AUTODEPLOY_CMD" ]; then
            echo -e "  ${RED}✗ No command provided${NC}"
            exit 1
        fi

        # Replace 'wings' with full path
        AUTODEPLOY_CMD=$(echo "$AUTODEPLOY_CMD" | sed "s|wings configure|$WINGS_BINARY configure|g")
        AUTODEPLOY_CMD=$(echo "$AUTODEPLOY_CMD" | sed "s|sudo wings|sudo $WINGS_BINARY|g")

        echo ""
        echo -e "  ${YELLOW}Running configuration command...${NC}"
        # Execute the auto-deploy command safely using bash -c
        # This is necessary for the panel's configure command which uses shell features
        bash -c "$AUTODEPLOY_CMD" || {
            echo -e "  ${RED}✗ Failed to run auto-deploy command${NC}"
            exit 1
        }

        if [ ! -f "$CONFIG_FILE" ]; then
            echo -e "  ${RED}✗ Config file was not created${NC}"
            exit 1
        fi

        echo -e "  ${GREEN}✓${NC} Panel configuration applied"
    else
        echo -e "  ${GREEN}✓${NC} Using existing configuration"
    fi
    echo ""

    # Step 4: Wings-Dedup Specific Settings (AFTER panel config)
    echo -e "${BLUE}${BOLD}[Step 4/5] Wings-Dedup Settings${NC}"
    echo ""
    
    echo -e "  ${CYAN}── License ──${NC}"
    echo -e "  ${YELLOW}  Format: alphanumeric with optional hyphens (e.g., abc123-def456)${NC}"
    while true; do
        prompt_required "  License Key: " LICENSE_KEY
        # Validate license key format (letters, numbers, hyphens, 10-50 chars)
        if [[ "$LICENSE_KEY" =~ ^[a-zA-Z0-9-]{10,50}$ ]]; then
            break
        else
            echo -e "  ${RED}  ✗ Invalid format. Must be 10-50 alphanumeric characters (hyphens allowed).${NC}"
        fi
    done
    echo ""
    
    echo -e "  ${CYAN}── Borg Backup (Unencrypted for Speed) ──${NC}"
    prompt_with_default "  Repository Path" "$DEFAULT_BORG_REPO" BORG_REPO
    echo ""
    
    echo -e "  ${CYAN}── Discord Notifications (Optional) ──${NC}"
    echo -e "  ${YELLOW}  Leave blank to skip Discord notifications${NC}"
    prompt_optional "  Discord Webhook URL: " DISCORD_WEBHOOK
    echo ""

    echo -e "  ${GREEN}✓${NC} Settings collected"
    echo ""

    # Step 5: Install Borg, Configure, and Start
    echo -e "${BLUE}${BOLD}[Step 5/5] Finalizing...${NC}"
    
    # Install Borg
    if command -v borg &> /dev/null; then
        BORG_VERSION=$(borg --version 2>/dev/null | head -1 || echo "unknown")
        echo -e "  ${GREEN}✓${NC} BorgBackup: ${CYAN}${BORG_VERSION}${NC}"
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
        echo -e "  ${GREEN}✓${NC} BorgBackup installed"
    fi

    # Install rsync (required for DR sync to remote storage)
    if command -v rsync &> /dev/null; then
        RSYNC_VERSION=$(rsync --version 2>/dev/null | head -1 || echo "installed")
        echo -e "  ${GREEN}✓${NC} rsync: ${CYAN}${RSYNC_VERSION}${NC}"
    else
        echo -e "  ${YELLOW}Installing rsync (for disaster recovery sync)...${NC}"
        if command -v apt-get &> /dev/null; then
            apt-get install -y -qq rsync > /dev/null 2>&1
        elif command -v dnf &> /dev/null; then
            dnf install -y -q rsync > /dev/null 2>&1
        elif command -v yum &> /dev/null; then
            yum install -y -q rsync > /dev/null 2>&1
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm rsync > /dev/null 2>&1
        else
            echo -e "  ${YELLOW}○${NC} Could not install rsync. Install manually for DR sync."
        fi
        if command -v rsync &> /dev/null; then
            echo -e "  ${GREEN}✓${NC} rsync installed"
        fi
    fi
    
    mkdir -p "$BORG_REPO"

    # Update config.yml with Wings-Dedup settings
    # Add license section
    if ! grep -q "^license:" "$CONFIG_FILE"; then
        cat >> "$CONFIG_FILE" <<EOF

# Wings-Dedup License
license:
  license_key: "${LICENSE_KEY}"
EOF
    else
        sed -i "s|license_key:.*|license_key: \"${LICENSE_KEY}\"|" "$CONFIG_FILE"
    fi
    echo -e "  ${GREEN}✓${NC} License configured"

    # Add/update borg settings under system.backups
    # First check if system.backups.borg exists
    if grep -q "^  backups:" "$CONFIG_FILE" 2>/dev/null || grep -q "^system:" "$CONFIG_FILE" 2>/dev/null; then
        # Check if borg section exists
        if ! grep -q "borg:" "$CONFIG_FILE"; then
            # Add borg section - find backups: and add after it, or add whole section
            if grep -q "backups:" "$CONFIG_FILE"; then
                # Insert borg config after backups:
                sed -i '/backups:/a\    borg:\n      enabled: true\n      repository_path: "'"$BORG_REPO"'"\n      compression: lz4\n      encryption:\n        enabled: false' "$CONFIG_FILE"
            else
                # Add backups section with borg
                cat >> "$CONFIG_FILE" <<EOF

# Borg Backup Configuration
system:
  backups:
    borg:
      enabled: true
      repository_path: "${BORG_REPO}"
      compression: lz4
      encryption:
        enabled: false
EOF
            fi
        else
            # Update existing borg settings
            sed -i "s|repository_path:.*|repository_path: \"${BORG_REPO}\"|" "$CONFIG_FILE"
        fi
    else
        # No system section - append full config
        cat >> "$CONFIG_FILE" <<EOF

# Borg Backup Configuration  
system:
  backups:
    borg:
      enabled: true
      repository_path: "${BORG_REPO}"
      compression: lz4
      encryption:
        enabled: false
EOF
    fi
    echo -e "  ${GREEN}✓${NC} Borg backup configured (unencrypted)"

    # Add Discord webhook if provided (under notifications section)
    if [ -n "$DISCORD_WEBHOOK" ]; then
        if ! grep -q "notifications:" "$CONFIG_FILE"; then
            # Add notifications section under borg
            sed -i "/borg:/,/encryption:/ { /enabled: false/a\\      notifications:\\n        discord_webhook: \"${DISCORD_WEBHOOK}\" }" "$CONFIG_FILE" 2>/dev/null || \
            cat >> "$CONFIG_FILE" <<EOF
      notifications:
        discord_webhook: "${DISCORD_WEBHOOK}"
EOF
        else
            sed -i "s|discord_webhook:.*|discord_webhook: \"${DISCORD_WEBHOOK}\"|" "$CONFIG_FILE"
        fi
        echo -e "  ${GREEN}✓${NC} Discord webhook configured"
    else
        echo -e "  ${YELLOW}○${NC} Discord webhook skipped"
    fi

    chmod 600 "$CONFIG_FILE"
    echo -e "  ${GREEN}✓${NC} Config permissions secured"

    # Create systemd service
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
    echo -e "  ${GREEN}✓${NC} Systemd service configured"
    echo ""

    # Start Wings
    read -p "Start Wings now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo ""
        systemctl start wings
        sleep 3
        if systemctl is-active --quiet wings; then
            echo -e "${GREEN}✓ Wings-Dedup is running!${NC}"
        else
            echo -e "${RED}✗ Wings failed to start${NC}"
            echo -e "${YELLOW}Check logs: journalctl -u wings -f${NC}"
        fi
    else
        echo ""
        echo -e "${YELLOW}Start later: ${CYAN}systemctl start wings${NC}"
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}✓ Installation Complete!${NC}"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo -e "  View logs:    ${YELLOW}journalctl -u wings -f${NC}"
    echo -e "  Restart:      ${YELLOW}systemctl restart wings${NC}"
    echo -e "  Edit config:  ${YELLOW}nano /etc/pterodactyl/config.yml${NC}"
    echo ""
    echo -e "${BLUE}For support, contact srvl Labs${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    trap '' EXIT
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
        echo -e "${RED}✗ Original Wings backup not found at ${CYAN}${BACKUP_BINARY_PATH}${NC}"
        echo -e "${YELLOW}Cannot restore. You may need to manually reinstall standard Wings.${NC}"
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
    echo -e "  ${GREEN}✓${NC} Original binary restored"
    echo ""
    
    echo -e "${BLUE}${BOLD}[3/3] Cleaning up configuration...${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        # Remove Wings-Dedup specific sections
        sed -i '/# Wings-Dedup License/,/license_key:/d' "$CONFIG_FILE" 2>/dev/null || true
        sed -i '/# Borg Backup Configuration/,/compression:/d' "$CONFIG_FILE" 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Wings-Dedup settings removed"
        echo -e "  ${YELLOW}Note: Borg repository data was NOT deleted${NC}"
    fi

    systemctl daemon-reload
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Restoration Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

    read -p "Start original Wings now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        systemctl start wings
        sleep 2
        if systemctl is-active --quiet wings; then
            echo -e "${GREEN}✓ Wings is running!${NC}"
        else
            echo -e "${RED}✗ Wings failed to start${NC}"
            echo -e "${YELLOW}Check logs: journalctl -u wings -e${NC}"
        fi
    fi

    trap '' EXIT
    exit 0
}

# --- Update Only Logic ---

update_only() {
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║               Wings-Dedup Quick Update                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Step 1: Architecture detection
    echo -e "${BLUE}${BOLD}[Step 1/3] Detecting architecture...${NC}"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ARCH_NAME="amd64"
            BINARY_NAME="wings_amd"
            ;;
        aarch64|arm64)
            ARCH_NAME="arm64"
            BINARY_NAME="wings_arm"
            ;;
        *)
            echo -e "  ${RED}✗ Unsupported architecture: ${ARCH}${NC}"
            exit 1
            ;;
    esac
    echo -e "  ${GREEN}✓${NC} Architecture: ${CYAN}${ARCH} (${ARCH_NAME})${NC}"
    echo ""

    # Step 2: Get binary (local or download)
    echo -e "${BLUE}${BOLD}[Step 2/3] Getting Wings-Dedup binary...${NC}"
    
    if [ -f "./wings" ]; then
        echo -e "  ${GREEN}✓${NC} Using local binary: ${CYAN}./wings${NC}"
        if ! file ./wings | grep -qE "(executable|ELF)"; then
            echo -e "  ${RED}✗ Invalid binary file${NC}"
            exit 1
        fi
    else
        echo -e "  ${YELLOW}Downloading latest release...${NC}"
        
        API_URL="https://api.github.com/repos/srvl/deduplicated-backups/releases/latest"
        API_RESPONSE=$(curl -s "$API_URL")
        LATEST_TAG=$(echo "$API_RESPONSE" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        
        if [ -z "$LATEST_TAG" ]; then
            echo -e "  ${RED}✗ Failed to fetch latest release${NC}"
            # Show error details for debugging
            API_MESSAGE=$(echo "$API_RESPONSE" | grep '"message":' | sed -E 's/.*"message": *"([^"]+)".*/\1/')
            if [ -n "$API_MESSAGE" ]; then
                echo -e "  ${YELLOW}  GitHub API: ${API_MESSAGE}${NC}"
            fi
            echo -e "  ${YELLOW}  API URL: ${API_URL}${NC}"
            exit 1
        fi
        echo -e "  ${GREEN}✓${NC} Latest release: ${CYAN}${LATEST_TAG}${NC}"
        
        DOWNLOAD_URL="https://github.com/srvl/deduplicated-backups/releases/download/${LATEST_TAG}/${BINARY_NAME}"
        CHECKSUM_URL="https://github.com/srvl/deduplicated-backups/releases/download/${LATEST_TAG}/${BINARY_NAME}.sha256"
        
        if curl -f -L -o wings "$DOWNLOAD_URL"; then
            echo -e "  ${GREEN}✓${NC} Download complete"
            chmod +x wings
            
            # Verify SHA256 checksum if available
            if curl -f -s -L -o wings.sha256 "$CHECKSUM_URL" 2>/dev/null; then
                EXPECTED_SHA256=$(cat wings.sha256 | awk '{print $1}')
                ACTUAL_SHA256=$(sha256sum wings | awk '{print $1}')
                if [ "$EXPECTED_SHA256" != "$ACTUAL_SHA256" ]; then
                    echo -e "  ${RED}✗ SHA256 checksum mismatch!${NC}"
                    echo -e "  ${YELLOW}  Expected: ${EXPECTED_SHA256}${NC}"
                    echo -e "  ${YELLOW}  Actual:   ${ACTUAL_SHA256}${NC}"
                    rm -f wings wings.sha256
                    exit 1
                fi
                echo -e "  ${GREEN}✓${NC} SHA256 checksum verified"
                rm -f wings.sha256
            else
                echo -e "  ${YELLOW}○${NC} No checksum file available, skipping verification"
            fi
        else
            echo -e "  ${RED}✗ Failed to download${NC}"
            exit 1
        fi
    fi
    
    NEW_VERSION=$(./wings --version 2>/dev/null | head -1 || echo "unknown")
    echo -e "  ${GREEN}✓${NC} Version: ${CYAN}${NEW_VERSION}${NC}"
    echo ""

    # Step 3: Replace binary and restart
    echo -e "${BLUE}${BOLD}[Step 3/3] Installing and restarting...${NC}"
    
    if systemctl is-active --quiet wings 2>/dev/null; then
        echo -e "  ${YELLOW}Stopping Wings...${NC}"
        systemctl stop wings
    fi
    
    # Backup current if not already backed up
    if [ -f "$WINGS_BINARY" ] && [ ! -f "$BACKUP_BINARY_PATH" ]; then
        cp "$WINGS_BINARY" "$BACKUP_BINARY_PATH"
        echo -e "  ${GREEN}✓${NC} Original backed up"
    fi
    
    cp wings "$WINGS_BINARY"
    chmod +x "$WINGS_BINARY"
    rm -f wings
    echo -e "  ${GREEN}✓${NC} Binary replaced"
    
    systemctl start wings
    sleep 2
    
    if systemctl is-active --quiet wings; then
        echo -e "  ${GREEN}✓${NC} Wings-Dedup is running!"
    else
        echo -e "  ${RED}✗ Wings failed to start${NC}"
        echo -e "  ${YELLOW}Check logs: journalctl -u wings -f${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}✓ Update Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    trap '' EXIT
    exit 0
}

# --- Main Menu ---

main_menu() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        echo -e "${YELLOW}Run with: sudo $0${NC}"
        exit 1
    fi

    while true; do
        echo -e "${GREEN}"
        echo "╔═══════════════════════════════════════════════════════════╗"
        echo "║              srvl Labs Wings-Dedup Utility                ║"
        echo "╚═══════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        
        echo -e "${BOLD}Select an option:${NC}"
        echo -e "  ${GREEN}1)${NC} Install/Update Wings-Dedup (Full Setup)"
        echo -e "  ${CYAN}2)${NC} Update Only (Binary replacement, no config)"
        echo -e "  ${RED}3)${NC} Uninstall/Restore Original Wings"
        echo -e "  ${YELLOW}4)${NC} Exit"
        echo ""
        
        read -p "Choice (1-4): " -r CHOICE

        case "$CHOICE" in
            1) echo ""; install_wings_dedup ;;
            2) echo ""; update_only ;;
            3) echo ""; uninstall_wings_dedup ;;
            4) echo -e "\n${BLUE}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "\n${RED}Invalid choice${NC}" ;;
        esac
        echo ""
    done
}

main_menu "menu"

