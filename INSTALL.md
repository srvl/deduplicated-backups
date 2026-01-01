# Wings-Dedup Installation Guide

**Version:** 1.0
**Support:** Contact ATB Hosting for assistance

## What You'll Receive

When you purchase Wings-Dedup, you'll receive:

1. **Your unique license key** - Required to activate Wings-Dedup
2. **Wings-Dedup binary** - Pre-compiled Wings executable (`wings`)
3. **Install script** - Automated installation script (`install-wings.sh`)
4. **Borg install script** (optional) - For installing BorgBackup (`install-borg.sh`)

## Prerequisites

- Ubuntu 20.04+ or Debian 11+ (CentOS/Rocky Linux 8+ also supported)
- Root access to your server
- Existing Pterodactyl Panel installation
- Node configured on the Panel (with token and UUID)
- Docker installed and running

## Quick Installation

### Step 1: Download Installation Files

Upload the files you received to your server:

```bash
# Create installation directory
mkdir -p /root/wings-dedup-install
cd /root/wings-dedup-install

# Upload files here (via SCP, SFTP, or direct download link)
# - wings (the binary)
# - install-wings.sh
# - install-borg.sh (if using Borg backups)
```

### Step 2: Make Scripts Executable

```bash
chmod +x install-wings.sh install-borg.sh wings
```

### Step 3: Install Borg Backup (Recommended)

Wings-Dedup uses BorgBackup for advanced deduplication. Install it:

```bash
./install-borg.sh
```

This will install BorgBackup 1.2.8+ on your system.

### Step 4: Install Wings-Dedup

Run the installation script:

```bash
./install-wings.sh
```

The script will:
- Stop the existing Wings service (if running)
- Install the Wings-Dedup binary to `/usr/local/bin/wings`
- Set proper permissions
- Install systemd service with license failure protection

### Step 5: Configure Your Node

Edit `/etc/pterodactyl/config.yml` and configure your Panel connection and license:

```yaml
# Panel Authentication (get these from your Panel's node configuration)
uuid: "your-node-uuid-from-panel"
token_id: "your-token-id-from-panel"
token: "your-token-from-panel"
remote: "https://your-panel-domain.com"

# API Configuration
api:
  host: 0.0.0.0
  port: 8080
  ssl:
    enabled: true
    cert: /etc/letsencrypt/live/your-domain.com/fullchain.pem
    key: /etc/letsencrypt/live/your-domain.com/privkey.pem

# System Configuration
system:
  root_directory: /var/lib/pterodactyl
  log_directory: /var/log/pterodactyl
  data: /var/lib/pterodactyl/volumes
  archive_directory: /var/lib/pterodactyl/archives
  backup_directory: /var/lib/pterodactyl/backups
  username: pterodactyl
  timezone: America/New_York  # Your timezone

  sftp:
    bind_port: 2022
    bind_address: 0.0.0.0

  # Borg Backup Configuration
  backups:
    write_limit: 0
    compression_level: best_speed
    borg:
      enabled: true
      repository_path: /var/lib/pterodactyl/backups/borg-repo
      compression: lz4
      
      # Encryption (optional but recommended)
      encryption:
        enabled: true
        passphrase: "YOUR-SECURE-PASSPHRASE-HERE"
        mode: repokey-blake2
      
      # Retention policy
      prune_keep_last: 7
      prune_keep_daily: 7
      prune_keep_weekly: 4
      
      # Notifications (optional)
      notifications:
        discord_webhook: ""

# Docker Configuration
docker:
  network:
    name: pterodactyl_nw
    interfaces:
      v4:
        subnet: 172.18.0.0/16
        gateway: 172.18.0.1

# ⚠️ LICENSE CONFIGURATION (REQUIRED) ⚠️
license:
  license_key: "YOUR-LICENSE-KEY-HERE"
```

**Important License Notes:**
- The `license_key` field is **REQUIRED** - Wings will not start without it
- Replace `YOUR-LICENSE-KEY-HERE` with the license key provided to you
- The following settings are hardcoded and cannot be changed:
  - Product Name: `Wings-Dedup`
  - Validation URL: `https://api.atbphosting.com/api/validate`
  - Revalidation: Every 60 minutes
  - Grace Period: 24 hours

### Step 6: Start Wings-Dedup

```bash
systemctl daemon-reload
systemctl enable wings
systemctl start wings
```

### Step 7: Verify Installation

Check the logs to confirm Wings-Dedup started successfully:

```bash
journalctl -u wings -f
```

**Expected output:**
```
INFO validating Wings-Dedup license...
INFO license validated successfully
INFO started periodic license revalidation interval=60 minutes
INFO initializing Borg backup system
INFO Borg repository initialized successfully
INFO configuring internal webserver
```

If you see these messages, congratulations! Wings-Dedup is running successfully.

---

## Advanced Configuration

### Option A: Local Borg Storage (Default)

This stores backups on the same server. Simple and fast:

```yaml
system:
  backups:
    borg:
      enabled: true
      repository_path: /var/lib/pterodactyl/backups/borg-repo
      compression: lz4
      
      # Encryption (optional - set enabled: false for no encryption)
      encryption:
        enabled: true
        passphrase: "YOUR-SECURE-PASSPHRASE-HERE"
```

**Pros:**
- Simple setup
- No additional costs
- Fast backups

**Cons:**
- Backups stored on same server (risk of data loss if server fails)
- Uses local disk space

---

### Option B: Remote Borg Storage (SSH)

Store backups on a remote server like Hetzner Storage Box, rsync.net, or your own SSH server.

#### B1. Set Up SSH Keys

Generate an SSH key for Wings to connect to the remote server:

```bash
# Generate SSH key (no passphrase)
ssh-keygen -t ed25519 -f /root/.ssh/borg_backup -N ""

# Copy public key to remote server
ssh-copy-id -i /root/.ssh/borg_backup.pub user@backup-server.com
```

#### B2. Test SSH Connection

```bash
# Test connection (should work without password)
ssh -i /root/.ssh/borg_backup user@backup-server.com
```

#### B3. Configure Remote Borg in config.yml

Update your `/etc/pterodactyl/config.yml`:

```yaml
system:
  backups:
    borg:
      enabled: true
      compression: lz4
      
      # Encryption
      encryption:
        enabled: true
        passphrase: "YOUR-SECURE-PASSPHRASE-HERE"
      
      # Remote repository configuration (Remote-Only mode)
      remote:
        enabled: true
        # SSH repository format: ssh://user@host:port/./path
        repository_path: "ssh://u123456@u123456.your-storagebox.de:23/./borg-repo"
        ssh_key: "/root/.ssh/borg_backup"
        ssh_port: 23  # Hetzner uses port 23
        borg_path: "borg-1.4"  # Borg version on remote
        upload_limit_kb: 0  # KB/s, 0 = unlimited
      
      # Retention
      prune_keep_last: 7
      prune_keep_daily: 7
      prune_keep_weekly: 4
      
      # Notifications
      notifications:
        discord_webhook: "https://discord.com/api/webhooks/your-webhook-url"
```

#### B4. Restart Wings

```bash
systemctl restart wings
journalctl -u wings -f
```

You should see:
```
INFO Borg repository initialized successfully repository=ssh://user@host:23/./borg-repo
INFO backup scheduler started
```

### Hetzner Storage Box: Complete Setup Guide

This step-by-step guide shows how to set up Wings-Dedup with Hetzner Storage Box for remote-only backups.

#### Step 1: Enable SSH on Hetzner Storage Box

In the Hetzner Robot panel:
1. Go to your Storage Box settings
2. Enable **SSH Support**
3. Enable **External Reachability**

#### Step 2: Create SSH Key on Your Wings Node

```bash
# Run on your Wings VPS (not Storage Box)
ssh-keygen -t ed25519 -f ~/.ssh/storage_ssh -N ""
```

#### Step 3: Upload Public Key to Storage Box

```bash
# Download existing authorized_keys (if any)
sftp -P 23 uXXXXX@uXXXXX.your-storagebox.de
get .ssh/authorized_keys
quit

# Append your new public key
cat ~/.ssh/storage_ssh.pub >> authorized_keys

# Upload back to Storage Box
sftp -P 23 uXXXXX@uXXXXX.your-storagebox.de
put authorized_keys .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
quit
```

#### Step 4: Test SSH Connection

```bash
ssh -p 23 -i ~/.ssh/storage_ssh uXXXXX@uXXXXX.your-storagebox.de
# You should connect successfully, then type 'exit'
```

#### Step 5: Initialize Borg Repository (One Per Node!)

> **IMPORTANT:** Each Wings node needs its own separate borg repository!

```bash
# From Node 1 - create repo for node 1
BORG_RSH="ssh -i ~/.ssh/storage_ssh" borg init --encryption=none --remote-path=borg-1.4 ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./node1-repo

# From Node 2 - create repo for node 2  
BORG_RSH="ssh -i ~/.ssh/storage_ssh" borg init --encryption=none --remote-path=borg-1.4 ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./node2-repo

# And so on for each node...
```

#### Step 6: Copy SSH Key to All Nodes

```bash
# Download the private key from your first node
# Location: /root/.ssh/storage_ssh

# Upload it to same location on all other nodes
# /root/.ssh/storage_ssh
```

#### Step 7: Run the Install Script

```bash
bash <(curl -sL https://github.com/srvl/deduplicated-backups/raw/main/install-wings.sh)
```

When prompted:
- **License Key**: Get from Discord bot (click "Wings-Dedup" button in #💾│deduplicated-backups)
- **Storage Mode**: Choose `remote` for Hetzner Storage Box
- **Remote Repository**: `ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./node1-repo`
- **SSH Port**: `23`
- **SSH Key Path**: `/root/.ssh/storage_ssh`
- **Remote Borg Path**: `borg-1.4`

#### Step 8: Verify Configuration

After install, check `/etc/pterodactyl/config.yml`:

```yaml
system:
  backups:
    backend: "borg"
    storage_mode: "remote"    # Must be "remote" for remote-only
    
    borg:
      enabled: true
      compression: lz4
      encryption:
        enabled: false
      
      remote:
        repository: "ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./node1-repo"
        ssh_key: "/root/.ssh/storage_ssh"
        ssh_port: 23
        borg_path: "borg-1.4"
```

> **If values are empty**, manually edit the config and add them!

#### Step 9: Restart and Test

```bash
systemctl restart wings
journalctl -u wings -f
```

Create a backup from the Panel and watch the logs for success.

#### Hetzner Quick Reference

| Setting | Value |
|---------|-------|
| SSH Port | `23` (not 22!) |
| Remote Borg Path | `borg-1.4` (or `borg-1.2`, `borg-1.1`) |
| Repository Format | `ssh://uXXXXX@uXXXXX.your-storagebox.de:23/./repo-name` |
| Path Prefix | `./` (dot-slash required) |

#### FAQ: "Disaster Recovery is DISABLED"

This warning is **normal** for remote-only mode. It means:
- Your backups go directly to Hetzner (remote)
- There's no local→remote sync (that's hybrid mode)
- This is expected behavior, not an error!

---

## Backup Features

Wings-Dedup provides advanced backup capabilities:

### Deduplication
- **Content-defined chunking** - Only stores unique data blocks
- **Cross-backup deduplication** - Data shared between backups is stored once
- **Compression** - LZ4 compression for speed, ZSTD available for better compression

### Retention Policies
Automatically prune old backups:
- Keep last 7 backups
- Keep 7 daily backups
- Keep 4 weekly backups

Configured in `prune_keep_*` settings.

### Discord Notifications
Get notified of backup events:
- Successful backups with deduplication ratio
- Failed backups with error details
- Repository health alerts

Configure via `discord_webhook` setting.

---

## Disaster Recovery

Wings-Dedup includes a disaster recovery system that automatically syncs your local backups to a remote repository. This protects against scenarios where an attacker gains Panel access and deletes files and backups.

### Sync Modes

Wings-Dedup supports two sync modes:

| Mode | Description | Best For |
|------|-------------|----------|
| **`rsync`** (default) | Syncs entire Borg repository using rsync | Enterprise scale (100+ servers), high reliability |
| **`export-tar`** (legacy) | Per-archive export-tar\|import-tar via Borg | Small deployments, specific use cases |

**Recommendation:** Use `rsync` mode (default) for production deployments. It eliminates lock contention issues and is significantly faster for batch operations.

### Enable Disaster Recovery

Add the `disaster_recovery` section to your config:

```yaml
system:
  backups:
    borg:
      enabled: true
      repository_path: "/var/lib/pterodactyl/backups/borg-repo"
      encryption:
        enabled: true
        passphrase: "your-strong-passphrase"
      
      # Disaster Recovery Configuration
      disaster_recovery:
        enabled: true
        
        # --- Connection (same SSH key works for both borg and rsync) ---
        remote_repository: "ssh://u123456@u123456.your-storagebox.de:23/./borg-repo-dr"
        ssh_key: "/root/.ssh/borg_backup"
        ssh_port: 23
        borg_path: "borg-1.4"
        
        # --- Sync Mode ---
        # "rsync" (default) - Repository-level sync, no lock contention
        # "export-tar" - Legacy per-archive sync (has lock issues at scale)
        sync_mode: "rsync"
        
        # --- Rsync Settings (only used when sync_mode: rsync) ---
        # Seconds to wait after last backup before starting rsync
        # Higher values batch more backups into one sync operation
        rsync_batch_delay: 300
        # Remove deleted archives from remote (clean mirror)
        rsync_delete: true
        
        # --- Bandwidth Limits ---
        upload_limit_kb: 51200  # 50 MB/s (0 = unlimited)
        download_limit_mb: 50   # For DRC restores
        
        # --- Recovery Console Access ---
        recovery_password: "your-drc-password"
        
        # Or use Discord OAuth:
        # discord_oauth:
        #   enabled: true
        #   client_id: "your-discord-app-client-id"
        #   client_secret: "your-discord-app-client-secret"
        #   redirect_url: "https://your-wings:8080/drc/oauth/callback"
        #   allowed_user_ids: ["123456789", "987654321"]
```

### How Rsync Mode Works

```
┌─────────────────────────────────────────────────────────────────────┐
│  3:00 AM - 4:00 AM: Backup Window                                   │
│  ───────────────────────────────────────────────────────────────    │
│  [Server 1 backup] → [Server 2] → [Server 3] → ... → [Server 200]   │
│                                                                      │
│  Each backup creates archive in local Borg repo (fast, <30s each)   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ (rsync_batch_delay: 300s)
┌─────────────────────────────────────────────────────────────────────┐
│  4:05 AM: Rsync Sync to Remote                                      │
│  ───────────────────────────────────────────────────────────────    │
│  rsync -avz --partial /local/borg-repo/ → remote:/borg-repo-dr/     │
│                                                                      │
│  • ONE rsync for ALL archives (not per-archive)                     │
│  • NO Borg locks (reads filesystem directly)                        │
│  • Resumable if interrupted                                         │
│  • ~20-40 GB incremental = 30-60 min over WAN                       │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Advantages of Rsync Mode

| Feature | Rsync Mode | Export-Tar Mode |
|---------|-----------|-----------------|
| **Lock contention** | None | High (per-archive exports) |
| **Batch efficiency** | One sync for all archives | N syncs for N archives |
| **Resumable** | Yes (--partial) | Complex checkpoint system |
| **Speed for 200 servers** | ~30-60 min | ~2-4 hours |
| **WAN reliability** | Excellent | Prone to timeouts |

### Important: Same SSH Key for Borg and Rsync

**You only need ONE SSH key!** Both Borg and rsync use the same SSH key to connect to Hetzner Storage Box (or any SSH-based remote storage).

```bash
# The same key works for both:
ssh -i /root/.ssh/borg_backup -p 23 u123456@u123456.your-storagebox.de

# Borg uses it for: borg list, borg extract, etc.
# Rsync uses it for: rsync -e "ssh -i /root/.ssh/borg_backup -p 23" ...
```

### Migration from Export-Tar to Rsync Mode

If you're upgrading from an older version that used export-tar:

1. **Clear the remote repository** (rsync will recreate it):
   ```bash
   # SSH to remote and clear the DR directory
   ssh -i /root/.ssh/borg_backup -p 23 u123456@u123456.your-storagebox.de
   rm -rf ./borg-repo-dr/*
   ```

2. **Update your config.yml**:
   ```yaml
   disaster_recovery:
     sync_mode: "rsync"  # Add this line
   ```

3. **Restart Wings**:
   ```bash
   systemctl restart wings
   ```

4. **First rsync will copy entire local repo** (may take a while depending on size)

### Verify Remote Sync

Check sync status:

```bash
# View Wings logs for sync activity
journalctl -u wings | grep -i rsync

# Manually list remote archives (proves remote is a valid Borg repo)
export BORG_PASSPHRASE="your-passphrase"
borg list --remote-path=borg-1.4 ssh://user@host:23/./borg-repo-dr
```

### Admin Recovery Console

Access the disaster recovery admin UI at:

```
https://your-wings-server:8080/drc
```

**Features:**
- Browse all backups across all servers
- Search by server UUID or date range
- One-click download as `.tar.gz`
- Restore any backup to any server
- View and clean up orphan backups
- Repository statistics and sync status

**Authentication:** Password or Discord OAuth (configured in disaster_recovery section)

---


## Troubleshooting

### License Validation Failed

**Problem:**
```
FATAL Wings-Dedup requires a valid license. Please configure 'license_key' in your config.yml
```

**Solution:**
- Verify your license key is correctly entered in `/etc/pterodactyl/config.yml`
- Ensure there are no extra spaces or quotes
- Contact ATB Hosting if your license is invalid

---

### License Server Unreachable

**Problem:**
```
WARN periodic license validation failed error="connection refused"
```

**Solution:**
- This is normal during temporary network issues
- Wings-Dedup has a 24-hour grace period
- Operations will continue normally during the grace period
- If issue persists beyond 24 hours, backups will be blocked
- Check your firewall allows HTTPS to `api.atbphosting.com`

---

### Borg Repository Locked

**Problem:**
```
ERROR failed to create borg backup error="repository is locked"
```

**Solution:**
```bash
# Break the lock (only if no other backup is running!)
borg break-lock /var/lib/pterodactyl/backups/borg-repo

# For remote repositories:
borg break-lock ssh://user@host/path/to/repo
```

---

### SSH Connection Failed (Remote Borg)

**Problem:**
```
ERROR failed to initialize borg repository error="ssh: connect to host backup-server.com port 23: Connection refused"
```

**Solution:**
1. Verify SSH key is correct:
   ```bash
   ssh -i /root/.ssh/borg_backup user@backup-server.com
   ```

2. Check SSH port (Hetzner uses 23, standard SSH uses 22)

3. Verify firewall allows outbound SSH connections

4. Check remote server is accessible:
   ```bash
   ping backup-server.com
   ```

---

### Wings Won't Start

**Problem:**
Wings exits immediately after starting.

**Solution:**
1. Check the logs:
   ```bash
   journalctl -u wings -n 50
   ```

2. Common issues:
   - Missing license key
   - Invalid license
   - Borg passphrase not configured
   - Port 8080 already in use
   - SSL certificate issues

3. Verify configuration syntax:
   ```bash
   # YAML is indent-sensitive, use spaces not tabs
   cat /etc/pterodactyl/config.yml | grep -A 5 "license:"
   ```

---

### High Disk Usage

**Problem:**
Borg backups are using too much disk space.

**Solution:**
1. Run manual prune:
   ```bash
   systemctl stop wings
   borg prune /var/lib/pterodactyl/backups/borg-repo \
     --keep-last=7 \
     --keep-daily=7 \
     --keep-weekly=4
   borg compact /var/lib/pterodactyl/backups/borg-repo
   systemctl start wings
   ```

2. Adjust retention in config:
   ```yaml
   prune_keep_last: 3    # Reduce from 7
   prune_keep_daily: 3   # Reduce from 7
   prune_keep_weekly: 2  # Reduce from 4
   ```

3. Use remote storage instead of local

---

### Permission Denied Errors

**Problem:**
```
ERROR borg create failed: exit status 2
WARN Permission denied: '/var/lib/pterodactyl/backups/borg-repo'
```

**Cause:**
Directories are not owned by the `pterodactyl` user, or the user's home directory is missing.

**Solution:**

1. Run the health check script:
   ```bash
   ./borg-health-check.sh --check  # Check for issues
   ./borg-health-check.sh --fix    # Automatically fix issues
   ```

2. Or fix manually:
   ```bash
   # Fix directory ownership
   chown -R pterodactyl:pterodactyl /var/lib/pterodactyl
   
   # Create home directory if missing
   mkdir -p /home/pterodactyl
   chown pterodactyl:pterodactyl /home/pterodactyl
   ```

3. Clear any stale Borg locks:
   ```bash
   systemctl stop wings
   borg break-lock /var/lib/pterodactyl/backups/borg-repo
   systemctl start wings
   ```

---

### Pre-flight Check Failures

Wings-Dedup runs pre-flight checks on startup to catch permission issues early. Common messages:

| Error Message | Meaning | Fix |
|--------------|---------|-----|
| `home directory does not exist` | Pterodactyl user needs a home dir | `mkdir -p /home/pterodactyl && chown pterodactyl:pterodactyl /home/pterodactyl` |
| `directory ownership issues` | Wrong owner on backup directories | `chown -R pterodactyl:pterodactyl /var/lib/pterodactyl` |
| `borg binary not found` | Borg not installed | `apt install borgbackup` |
| `repository lock file exists` | Stale lock from crashed process | `borg break-lock <repo-path>` |

---

### Using the Health Check Script

Wings-Dedup includes `borg-health-check.sh` for diagnosing and fixing common issues:

```bash
# Check for issues (read-only)
./borg-health-check.sh --check

# Automatically fix issues
./borg-health-check.sh --fix
```

The script checks:
- Pterodactyl user exists
- Home directory exists and has correct ownership
- Backup directories have correct ownership
- Borg is installed and working
- No stale repository locks
- Repository integrity (in --fix mode)


---

## Updating Wings-Dedup

When a new version is released:

1. Download the new Wings binary
2. Stop Wings:
   ```bash
   systemctl stop wings
   ```
3. Replace the binary:
   ```bash
   cp wings /usr/local/bin/wings
   chmod +x /usr/local/bin/wings
   ```
4. Start Wings:
   ```bash
   systemctl start wings
   journalctl -u wings -f
   ```

Your configuration and backups are preserved during updates.

---

## Support

For technical support or questions:

- **Email:** support@atbphosting.com
- **Discord:** [Your Discord Server]
- **Documentation:** [Your Documentation URL]

When contacting support, please provide:
1. Your license key (first 8 characters only)
2. Wings version: `wings version`
3. Error logs: `journalctl -u wings -n 100`
4. Configuration (with sensitive data removed)

---

## Security Best Practices

1. **Protect Your License Key**
   - Never share your license key
   - Don't commit it to version control
   - Use environment variables if possible

2. **Secure Your Borg Passphrase**
   - Use a strong, unique passphrase
   - Store it securely (password manager)
   - Don't lose it - you can't recover backups without it!

3. **Use SSL/TLS**
   - Configure SSL certificates for Wings API
   - Use HTTPS for your Panel

4. **Regular Backups**
   - Test restore procedures regularly
   - Verify backup integrity with `borg check`
   - Consider off-site backups (remote Borg)

5. **Monitor License Status**
   - Wings validates license every 60 minutes
   - Check logs for validation failures
   - Ensure `api.atbphosting.com` is accessible

---

## Frequently Asked Questions

### Can I use Wings-Dedup without Borg?

Yes, but you'll lose the deduplication benefits. Set `borg.enabled: false` in your config and standard tar.gz backups will be used instead.

### Can I change the validation URL or product name?

No, these settings are hardcoded to ensure licensing is enforced consistently. This protects your investment in Wings-Dedup.

### What happens if my license expires?

- Wings will continue running during the 24-hour grace period
- After grace period expires, new backups will be blocked
- Existing servers continue to run normally
- Contact ATB Hosting to renew your license

### Can I move Wings-Dedup to a different server?

Yes, simply:
1. Install Wings-Dedup on the new server
2. Use the same license key
3. Your license may track IPs - contact support if you need to reset IP tracking

### How much disk space will Borg save?

Typical deduplication ratios:
- First backup: 1:1 (full size)
- Subsequent backups: 10:1 to 50:1 depending on how much data changes
- Cross-server deduplication: 100:1+ if servers have similar files

### Can I use multiple Wings instances with one license?

No, each license is for a single Wings node. Contact ATB Hosting for multi-node licensing.

---

## License Information

This software is licensed by ATB Hosting. License validation is required for operation.

**License Terms:**
- Valid for one Wings-Dedup instance
- Online validation required (every 60 minutes)
- 24-hour grace period for temporary outages
- Non-transferable without authorization

For licensing questions, contact ATB Hosting.

---

**Thank you for choosing Wings-Dedup!**

Enjoy advanced backup capabilities with industry-leading deduplication technology.
