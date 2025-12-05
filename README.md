====================================================
 Deduplicated Backups for Pterodactyl – Installation
====================================================

Thank you for purchasing! You can install the enhanced
Wings with deduplication using either of the two methods
below.

----------------------------------------------------
 METHOD 1 (Recommended): One-Line Auto Installer
----------------------------------------------------

This always installs the latest stable version.

1. Connect to your VPS using SSH.
2. Run this command:

   bash <(curl -sL https://github.com/srvl/deduplicated-backups/raw/main/install-wings.sh)

3. Follow the interactive setup to complete installation.


----------------------------------------------------
 METHOD 2: Manual Installation
----------------------------------------------------

1. Extract or copy the wings and install.sh to your VPS.

2. Make the installer executable if needed:

   chmod +x install.sh

3. Run the installer:

   ./install.sh

4. Follow the interactive setup.


----------------------------------------------------
 AFTER INSTALLATION
----------------------------------------------------

• Wings will restart automatically.
• Your dedup repository will initialize on first run.
• Backups will now use deduplication unless the system
  auto-falls back to standard backups.

If you need help or have questions, join the Discord:
https://discord.gg/9RNXfZ2Hsm
