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

# --- Config Migration ---

# Migrate legacy DisasterRecovery config to new Remote format
# This allows seamless upgrade from older Wings-Dedup versions
migrate_legacy_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 0
    fi

    # Check if legacy disaster_recovery section exists
    if ! grep -q "disaster_recovery:" "$CONFIG_FILE" 2>/dev/null; then
        return 0
    fi

    # Check if already migrated (has remote: section under borg:)
    if grep -q "^      remote:" "$CONFIG_FILE" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Config already using new format"
        return 0
    fi

    echo -e "  ${YELLOW}Migrating legacy config to new format...${NC}"

    # Create backup
    cp "$CONFIG_FILE" "${CONFIG_FILE}.pre-migration.$(date +%Y%m%d_%H%M%S)"

    # Extract legacy values using grep/sed
    LEGACY_REMOTE_REPO=$(grep -E "^\s+remote_repository:" "$CONFIG_FILE" | sed 's/.*remote_repository:\s*//' | tr -d '"' | tr -d "'" | head -1)
    LEGACY_SSH_KEY=$(grep -E "^\s+ssh_key:" "$CONFIG_FILE" | sed 's/.*ssh_key:\s*//' | tr -d '"' | tr -d "'" | head -1)
    LEGACY_SSH_PORT=$(grep -E "^\s+ssh_port:" "$CONFIG_FILE" | sed 's/.*ssh_port:\s*//' | head -1)
    LEGACY_BORG_PATH=$(grep -E "^\s+borg_path:" "$CONFIG_FILE" | sed 's/.*borg_path:\s*//' | tr -d '"' | tr -d "'" | head -1)
    LEGACY_SYNC_MODE=$(grep -E "^\s+sync_mode:" "$CONFIG_FILE" | sed 's/.*sync_mode:\s*//' | tr -d '"' | tr -d "'" | head -1)
    LEGACY_BW_LIMIT=$(grep -E "^\s+upload_bwlimit:" "$CONFIG_FILE" | sed 's/.*upload_bwlimit:\s*//' | tr -d '"' | tr -d "'" | head -1)

    # Only migrate if we found a remote repository
    if [ -z "$LEGACY_REMOTE_REPO" ]; then
        echo -e "  ${YELLOW}○${NC} No remote repository in legacy config, skipping migration"
        return 0
    fi

    # Set defaults
    LEGACY_SSH_PORT="${LEGACY_SSH_PORT:-23}"
    LEGACY_BORG_PATH="${LEGACY_BORG_PATH:-borg-1.4}"
    LEGACY_SYNC_MODE="${LEGACY_SYNC_MODE:-rsync}"
    LEGACY_BW_LIMIT="${LEGACY_BW_LIMIT:-50M}"

    # Build new config block
    NEW_REMOTE_CONFIG="      remote:
        repository: \"${LEGACY_REMOTE_REPO}\"
        ssh_key: \"${LEGACY_SSH_KEY}\"
        ssh_port: ${LEGACY_SSH_PORT}
        borg_path: \"${LEGACY_BORG_PATH}\"
      sync:
        mode: ${LEGACY_SYNC_MODE}
        workers: 1
        upload_bwlimit: \"${LEGACY_BW_LIMIT}\""

    # Insert new config after 'encryption:' block in borg section
    # This is a simple approach - append after the borg section header
    if grep -q "^    borg:" "$CONFIG_FILE" 2>/dev/null; then
        # Use a temp file approach for complex sed
        awk -v new_config="$NEW_REMOTE_CONFIG" '
            /^    borg:/ { in_borg=1 }
            in_borg && /^      encryption:/ { in_encryption=1 }
            in_encryption && /^      [a-z]/ && !/^      encryption/ { 
                print new_config
                in_encryption=0 
            }
            { print }
            END { if(in_encryption) print new_config }
        ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi

    # Remove old disaster_recovery section
    sed -i '/^      disaster_recovery:/,/^      [a-z]/{ /^      disaster_recovery:/d; /^        /d; }' "$CONFIG_FILE" 2>/dev/null || true

    echo -e "  ${GREEN}✓${NC} Config migrated to new format"
    echo -e "  ${CYAN}  Remote: ${LEGACY_REMOTE_REPO}${NC}"
    echo -e "  ${CYAN}  Sync mode: ${LEGACY_SYNC_MODE}${NC}"
}

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

    # Backend Selection
    echo -e "  ${CYAN}── Backup Backend ──${NC}"
    echo -e "  ${YELLOW}  Which backup technology to use:${NC}"
    echo -e "    ${GREEN}1)${NC} Borg (SSH/local storage) - Recommended for NAS/Storage Box"
    echo -e "    ${GREEN}2)${NC} Kopia (S3/object storage) - For AWS S3, Backblaze B2, Wasabi, R2"
    echo ""
    while true; do
        read -p "  Backend [1]: " BACKEND_CHOICE
        BACKEND_CHOICE="${BACKEND_CHOICE:-1}"
        if [[ "$BACKEND_CHOICE" == "1" ]]; then
            BACKUP_BACKEND="borg"
            break
        elif [[ "$BACKEND_CHOICE" == "2" ]]; then
            BACKUP_BACKEND="kopia"
            break
        else
            echo -e "  ${RED}  ✗ Choose 1 or 2${NC}"
        fi
    done
    echo -e "  ${GREEN}✓${NC} Backend: ${CYAN}${BACKUP_BACKEND}${NC}"
    echo ""

    # Storage Mode Selection
    echo -e "  ${CYAN}── Storage Mode ──${NC}"
    echo -e "  ${YELLOW}  Where to store backups:${NC}"
    echo -e "    ${GREEN}1)${NC} Local only - Backups stay on this node (fastest)"
    echo -e "    ${GREEN}2)${NC} Remote only - Backups go directly to remote storage (saves local disk)"
    echo -e "    ${GREEN}3)${NC} Hybrid - Local + synced to remote (best reliability, recommended)"
    echo ""
    while true; do
        read -p "  Storage mode [1]: " STORAGE_CHOICE
        STORAGE_CHOICE="${STORAGE_CHOICE:-1}"
        if [[ "$STORAGE_CHOICE" == "1" ]]; then
            STORAGE_MODE="local"
            break
        elif [[ "$STORAGE_CHOICE" == "2" ]]; then
            STORAGE_MODE="remote"
            break
        elif [[ "$STORAGE_CHOICE" == "3" ]]; then
            STORAGE_MODE="hybrid"
            break
        else
            echo -e "  ${RED}  ✗ Choose 1, 2, or 3${NC}"
        fi
    done
    echo -e "  ${GREEN}✓${NC} Storage mode: ${CYAN}${STORAGE_MODE}${NC}"
    echo ""

    # Backend-specific settings
    if [[ "$BACKUP_BACKEND" == "borg" ]]; then
        echo -e "  ${CYAN}── Borg Configuration ──${NC}"
        prompt_with_default "  Local Repository Path" "$DEFAULT_BORG_REPO" BORG_REPO
        
        if [[ "$STORAGE_MODE" != "local" ]]; then
            echo ""
            echo -e "  ${YELLOW}  Remote SSH storage (e.g., Hetzner Storage Box)${NC}"
            echo -e "  ${YELLOW}  Format: ssh://user@host:port/./path or user@host:path${NC}"
            prompt_optional "  Remote Repository: " REMOTE_REPO
            if [ -n "$REMOTE_REPO" ]; then
                prompt_with_default "  SSH Port" "23" SSH_PORT
                prompt_with_default "  SSH Key Path" "/root/.ssh/id_ed25519" SSH_KEY
                prompt_with_default "  Remote Borg Path" "borg-1.4" REMOTE_BORG_PATH
            fi
        fi
    else
        echo -e "  ${CYAN}── Kopia S3 Configuration ──${NC}"
        echo -e "  ${YELLOW}  Configure S3-compatible object storage${NC}"
        echo ""
        prompt_required "  S3 Endpoint (e.g., s3.amazonaws.com): " S3_ENDPOINT
        prompt_with_default "  S3 Region" "us-east-1" S3_REGION
        prompt_required "  S3 Bucket Name: " S3_BUCKET
        prompt_required "  Access Key: " S3_ACCESS_KEY
        prompt_required "  Secret Key: " S3_SECRET_KEY
        
        # Encryption password for Kopia
        echo ""
        echo -e "  ${YELLOW}Kopia encrypts all backups. A password is required.${NC}"
        echo -e "  ${YELLOW}Leave blank to auto-generate a secure password.${NC}"
        prompt_optional "  Encryption Password: " KOPIA_PASSWORD
        if [ -z "$KOPIA_PASSWORD" ]; then
            KOPIA_PASSWORD=$(openssl rand -base64 32)
            echo "$KOPIA_PASSWORD" > /root/.kopia-password
            chmod 600 /root/.kopia-password
            echo -e "  ${GREEN}✓${NC} Auto-generated password saved to ${CYAN}/root/.kopia-password${NC}"
            echo -e "  ${RED}  IMPORTANT: Back up this file! Loss = unrecoverable backups!${NC}"
        fi
        
        # Bandwidth limiting
        prompt_with_default "  Upload Bandwidth Limit" "50M" KOPIA_BWLIMIT
        
        # Local cache for Kopia
        prompt_with_default "  Local Cache Path" "/var/lib/pterodactyl/backups/kopia-cache" KOPIA_CACHE
        prompt_with_default "  Cache Size (MB)" "5000" KOPIA_CACHE_SIZE
    fi
    echo ""
    
    echo -e "  ${CYAN}── Discord Notifications (Optional) ──${NC}"
    echo -e "  ${YELLOW}  Leave blank to skip Discord notifications${NC}"
    prompt_optional "  Discord Webhook URL: " DISCORD_WEBHOOK
    echo ""

    echo -e "  ${GREEN}✓${NC} Settings collected"
    echo ""

    # Step 5: Install Borg, Configure, and Start
    echo -e "${BLUE}${BOLD}[Step 5/5] Finalizing...${NC}"
    
    # Install backend-specific tools
    if [[ "$BACKUP_BACKEND" == "borg" ]]; then
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
    else
        # Install Kopia
        if command -v kopia &> /dev/null; then
            KOPIA_VERSION=$(kopia --version 2>/dev/null | head -1 || echo "unknown")
            echo -e "  ${GREEN}✓${NC} Kopia: ${CYAN}${KOPIA_VERSION}${NC}"
        else
            echo -e "  ${YELLOW}Installing Kopia...${NC}"
            if command -v apt-get &> /dev/null; then
                # Add Kopia repository for Debian/Ubuntu
                curl -fsSL https://kopia.io/signing-key | gpg --dearmor -o /usr/share/keyrings/kopia-keyring.gpg 2>/dev/null || true
                echo "deb [signed-by=/usr/share/keyrings/kopia-keyring.gpg] https://packages.kopia.io/apt/ stable main" > /etc/apt/sources.list.d/kopia.list
                apt-get update -qq && apt-get install -y -qq kopia > /dev/null 2>&1
            elif command -v dnf &> /dev/null; then
                # Add Kopia repository for Fedora
                rpm --import https://kopia.io/signing-key 2>/dev/null || true
                cat > /etc/yum.repos.d/kopia.repo << 'KOPIAEOF'
[Kopia]
name=Kopia
baseurl=https://packages.kopia.io/rpm/stable/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://kopia.io/signing-key
KOPIAEOF
                dnf install -y -q kopia > /dev/null 2>&1
            elif command -v yum &> /dev/null; then
                # Add Kopia repository for RHEL/CentOS
                rpm --import https://kopia.io/signing-key 2>/dev/null || true
                cat > /etc/yum.repos.d/kopia.repo << 'KOPIAEOF'
[Kopia]
name=Kopia
baseurl=https://packages.kopia.io/rpm/stable/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://kopia.io/signing-key
KOPIAEOF
                yum install -y -q kopia > /dev/null 2>&1
            elif command -v pacman &> /dev/null; then
                # Arch Linux - install from AUR or binary
                echo -e "  ${YELLOW}Installing Kopia from binary...${NC}"
                KOPIA_LATEST=$(curl -s https://api.github.com/repos/kopia/kopia/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
                curl -fsSL -o /tmp/kopia.tar.gz "https://github.com/kopia/kopia/releases/download/v${KOPIA_LATEST}/kopia-${KOPIA_LATEST}-linux-${ARCH_NAME}.tar.gz"
                tar -xzf /tmp/kopia.tar.gz -C /tmp
                mv /tmp/kopia-${KOPIA_LATEST}-linux-${ARCH_NAME}/kopia /usr/local/bin/
                rm -rf /tmp/kopia* 
            else
                # Fallback: download binary
                echo -e "  ${YELLOW}Installing Kopia from binary...${NC}"
                KOPIA_LATEST=$(curl -s https://api.github.com/repos/kopia/kopia/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
                curl -fsSL -o /tmp/kopia.tar.gz "https://github.com/kopia/kopia/releases/download/v${KOPIA_LATEST}/kopia-${KOPIA_LATEST}-linux-${ARCH_NAME}.tar.gz"
                tar -xzf /tmp/kopia.tar.gz -C /tmp
                mv /tmp/kopia-${KOPIA_LATEST}-linux-${ARCH_NAME}/kopia /usr/local/bin/
                rm -rf /tmp/kopia*
            fi
            
            if command -v kopia &> /dev/null; then
                echo -e "  ${GREEN}✓${NC} Kopia installed"
            else
                echo -e "  ${RED}✗ Failed to install Kopia. Install manually from https://kopia.io${NC}"; exit 1;
            fi
        fi
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
    
    # Create directories based on backend
    if [[ "$BACKUP_BACKEND" == "borg" ]]; then
        mkdir -p "$BORG_REPO"
    else
        mkdir -p "$KOPIA_CACHE"
    fi

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

    # Generate backup configuration with new structure
    # Remove any existing borg/kopia config and replace with new structure
    if grep -q "^  backups:" "$CONFIG_FILE" 2>/dev/null; then
        # Will update in place
        echo -e "  ${YELLOW}Updating existing backup configuration...${NC}"
    fi

    # Build the backup config block based on selections
    if [[ "$BACKUP_BACKEND" == "borg" ]]; then
        BACKUP_CONFIG="
# Wings-Dedup Backup Configuration
  backups:
    backend: \"${BACKUP_BACKEND}\"
    storage_mode: \"${STORAGE_MODE}\"
    
    borg:
      enabled: true
      local_repository: \"${BORG_REPO}\"
      compression: lz4
      encryption:
        enabled: false"
        
        # Add remote config if provided
        if [ -n "$REMOTE_REPO" ]; then
            BACKUP_CONFIG+="
      remote:
        repository: \"${REMOTE_REPO}\"
        ssh_key: \"${SSH_KEY}\"
        ssh_port: ${SSH_PORT}
        borg_path: \"${REMOTE_BORG_PATH}\"
      sync:
        mode: rsync
        workers: 1
        upload_bwlimit: \"50M\""
        fi
        
        echo -e "  ${GREEN}✓${NC} Borg backup configured (${STORAGE_MODE} mode)"
    else
        # Kopia configuration
        BACKUP_CONFIG="
# Wings-Dedup Backup Configuration  
  backups:
    backend: \"${BACKUP_BACKEND}\"
    storage_mode: \"${STORAGE_MODE}\"
    
    kopia:
      enabled: true
      s3:
        endpoint: \"${S3_ENDPOINT}\"
        region: \"${S3_REGION}\"
        bucket: \"${S3_BUCKET}\"
        access_key: \"${S3_ACCESS_KEY}\"
        secret_key: \"${S3_SECRET_KEY}\"
      cache:
        enabled: true
        path: \"${KOPIA_CACHE}\"
        size_mb: ${KOPIA_CACHE_SIZE}
      performance:
        upload_bwlimit: \"${KOPIA_BWLIMIT}\"
      encryption:
        enabled: true
        password: \"${KOPIA_PASSWORD}\""
        
        echo -e "  ${GREEN}✓${NC} Kopia S3 backup configured"
    fi
    
    # Add notifications if webhook provided
    if [ -n "$DISCORD_WEBHOOK" ]; then
        BACKUP_CONFIG+="
    notifications:
      discord_webhook: \"${DISCORD_WEBHOOK}\""
        echo -e "  ${GREEN}✓${NC} Discord webhook configured"
    else
        echo -e "  ${YELLOW}○${NC} Discord webhook skipped"
    fi

    # Append to config file if system section exists, otherwise create it
    if grep -q "^system:" "$CONFIG_FILE" 2>/dev/null; then
        if grep -q "^  backups:" "$CONFIG_FILE" 2>/dev/null; then
            # Remove old backups section and replace
            # This is complex with sed, so we'll append and warn
            echo -e "  ${YELLOW}Note: Existing backups section preserved. Review config.yml to merge settings.${NC}"
            cat >> "$CONFIG_FILE" <<EOF
${BACKUP_CONFIG}
EOF
        else
            # Insert after system:
            sed -i "/^system:/a\\${BACKUP_CONFIG}" "$CONFIG_FILE" 2>/dev/null || \
            cat >> "$CONFIG_FILE" <<EOF
${BACKUP_CONFIG}
EOF
        fi
    else
        cat >> "$CONFIG_FILE" <<EOF

system:
${BACKUP_CONFIG}
EOF
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
        # Migrate legacy config if this was an upgrade
        migrate_legacy_config
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
    
    # Migrate legacy config if needed
    migrate_legacy_config
    
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

