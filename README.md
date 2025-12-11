# Deduplicated Backups for Pterodactyl — Installation Guide

Thank you for purchasing! You can install the enhanced Wings with native deduplication using either of the two methods below.

---

## Method 1 (Recommended): One-Line Auto Installer

Always installs the latest stable version.

1. Connect to your VPS using SSH
2. Run this command:

```bash <(curl -sL https://github.com/srvl/deduplicated-backups/raw/main/install-wings.sh)```

3. Follow the interactive setup to complete installation.

---

## Method 2: Manual Installation

1. Upload or copy the "wings" binary and "install-wings.sh" to your VPS
2. Make the installer executable:

chmod +x install-wings.sh

3. Run the installer:

./install-wings.sh

4. Follow the interactive setup.

---

## After Installation

• Wings will restart automatically  
• The dedup repository will initialize on first run  
• Backups will now use deduplication unless the system auto-falls back to standard backups  

For support or questions, join the Discord:  
https://discord.gg/9RNXfZ2Hsm
