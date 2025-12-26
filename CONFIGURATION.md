# Configuration Guide

This guide covers all Wings-Dedup configuration options with examples for common setups.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Backup Modes](#backup-modes)
   - [Local Only](#local-only-borg)
   - [Remote Only (SSH)](#remote-only-borg-ssh)
   - [Hybrid (Local + Remote Sync)](#hybrid-borg-with-rsync)
3. [Configuration Reference](#configuration-reference)
4. [SSH Key Setup](#ssh-key-setup)
5. [Kopia (S3) Tutorials](#kopia-s3-tutorials)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

Edit `/etc/pterodactyl/config.yml` and add your backup configuration under `system.backups`:

```yaml
system:
  backups:
    backend: "borg"           # "borg" (recommended) or "kopia"
    storage_mode: "hybrid"    # "local", "remote", or "hybrid"
```

---

## Backup Modes

### Local Only (Borg)

Backups stored only on the local disk. Simple setup, no external dependencies.

```yaml
system:
  backups:
    backend: "borg"
    storage_mode: "local"
    
    borg:
      local_repository: "/var/lib/pterodactyl/backups/borg-repo"
      compression: "lz4"
      encryption:
        enabled: false
```

**Pros:** Fast, simple, no network latency  
**Cons:** No disaster recovery if disk fails

---

### Remote Only (Borg SSH)

Backups go directly to remote storage via SSH. No local copy kept.

```yaml
system:
  backups:
    backend: "borg"
    storage_mode: "remote"
    
    borg:
      compression: "lz4"
      encryption:
        enabled: true
        passphrase: "your-secure-passphrase"
      
      remote:
        repository: "ssh://u123456@u123456.your-storagebox.de:23/./borg-repo"
        ssh_key: "/root/.ssh/id_ed25519"
        ssh_port: 23
        borg_path: "borg-1.4"
```

**Pros:** Offsite backups, survives node failure  
**Cons:** Slower backups due to network latency, requires always-on network access

---

### Hybrid (Borg with rsync)

**RECOMMENDED** - Backups stored locally first, then synced to remote in background.

```yaml
system:
  backups:
    backend: "borg"
    storage_mode: "hybrid"
    
    borg:
      local_repository: "/var/lib/pterodactyl/backups/borg-repo"
      compression: "lz4"
      encryption:
        enabled: false
      
      remote:
        repository: "ssh://u123456@u123456.your-storagebox.de:23/./borg-repo"
        ssh_key: "/root/.ssh/id_ed25519"    # For borg operations
        ssh_port: 23
        borg_path: "borg-1.4"
      
      sync:
        mode: "rsync"                  # "rsync" recommended
        workers: 1
        batch_delay_seconds: 10        # Wait before syncing (batches backups)
        upload_bwlimit: "50M"          # Limit upload speed (MB/s)
        timeout_hours: 4               # Max sync time
        lock_wait_seconds: 300         # Borg lock wait
        rsync_ssh_key: ""              # Optional: separate key for rsync
        rsync_delete: false            # DANGER: never sync deletions
        remote_retention_days: 0       # 0 = disabled (recommended)
```

**How it works:**
1. Backup completes instantly to local repo
2. Background worker syncs to remote using rsync
3. Admin dashboard shows sync status at `/drc`

**Pros:** Fast local backups + disaster recovery  
**Cons:** Uses more disk space (local + remote)

---

## Configuration Reference

### Top-Level Settings

| Setting | Values | Description |
|---------|--------|-------------|
| `backend` | `borg`, `kopia` | Which backup tool to use (borg recommended) |
| `storage_mode` | `local`, `remote`, `hybrid` | Where backups are stored |

### Borg Settings

#### Local Repository
```yaml
borg:
  local_repository: "/var/lib/pterodactyl/backups/borg-repo"
  compression: "lz4"  # Options: none, lz4, zstd, zlib
```

#### Encryption
```yaml
borg:
  encryption:
    enabled: false          # true to encrypt backups
    passphrase: ""          # Required if enabled
    mode: "repokey-blake2"  # Encryption algorithm
```

#### Remote Connection
```yaml
borg:
  remote:
    repository: "ssh://user@host:port/./path"
    ssh_key: "/root/.ssh/id_ed25519"
    ssh_port: 23
    borg_path: "borg-1.4"
```

#### Sync Settings (Hybrid mode)
```yaml
borg:
  sync:
    mode: "rsync"                  # "rsync" or "export-tar"
    workers: 1                     # Number of sync workers
    batch_delay_seconds: 10        # Wait before syncing
    upload_bwlimit: "50M"          # Upload speed limit
    timeout_hours: 4               # Max sync operation time
    lock_wait_seconds: 300         # Borg lock wait time
    rsync_ssh_key: ""              # Optional separate key for rsync
    rsync_delete: false            # DANGER: sync local deletions to remote
    remote_retention_days: 0       # Days before cleaning remote orphans (0=disabled)
    stale_worker_minutes: 5        # Alert threshold for stuck workers
```

> **Important:** If your storage provider (e.g., Hetzner Storage Box) uses **different SSH keys** for borg-serve mode vs SFTP/rsync access, set `rsync_ssh_key` to the SFTP key path.

---

## SSH Key Setup

### Hetzner Storage Box

Hetzner uses separate access modes:
- **Borg access:** Triggered by specific SSH key, allows `borg serve` commands
- **SFTP/rsync access:** Different SSH key, allows file operations

**Setup for Hybrid mode:**
```bash
# Generate key for borg operations
ssh-keygen -t ed25519 -f /root/.ssh/borg_backup -N ""

# Generate key for rsync operations (if needed)
ssh-keygen -t ed25519 -f /root/.ssh/storagebox_rsync -N ""

# Upload keys to Storage Box
echo 'command="borg serve --restrict-to-path ./borg-repo" ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys_new
echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys_new  # rsync key (no restriction)

scp -P 23 ~/.ssh/authorized_keys_new u123456@u123456.your-storagebox.de:.ssh/authorized_keys
```

**Config:**
```yaml
borg:
  remote:
    ssh_key: "/root/.ssh/borg_backup"  # For borg operations
  sync:
    rsync_ssh_key: "/root/.ssh/storagebox_rsync"  # For rsync sync
```

### Other Providers (Standard SSH)

If your provider allows all operations with one key:
```yaml
borg:
  remote:
    ssh_key: "/root/.ssh/id_ed25519"
  # No rsync_ssh_key needed - uses remote.ssh_key
```

---

## Kopia (S3) Tutorials

### Kopia: Remote Only (S3)

Direct backups to S3-compatible storage.

```yaml
system:
  backups:
    backend: "kopia"
    storage_mode: "remote"
    
    kopia:
      s3:
        endpoint: "s3.amazonaws.com"
        region: "us-east-1"
        bucket: "my-pterodactyl-backups"
        access_key: "AKIAIOSFODNN7EXAMPLE"
        secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        prefix: "wings/"
      
      cache:
        enabled: true
        path: "/var/lib/pterodactyl/backups/kopia-cache"
        size_mb: 5000
      
      encryption:
        enabled: true
```

**Supported providers:** AWS S3, Backblaze B2, Cloudflare R2, Wasabi, MinIO

---

## DRC (Disaster Recovery Console)

Access the DRC at `https://your-node:8591/admin/drc` (or custom path).

```yaml
system:
  backups:
    drc:
      enabled: true
      access_path: "/admin/drc"
      download_bwlimit: "50M"
      recovery_token: "your-secret-token"  # Static token auth
      
      # Or use Discord OAuth
      discord_oauth:
        enabled: true
        client_id: ""
        client_secret: ""
        redirect_url: "https://your-node:8591/admin/drc/oauth/callback"
        allowed_user_ids: ["your-discord-id"]
```

---

## Troubleshooting

### Check Borg repository
```bash
borg info /var/lib/pterodactyl/backups/borg-repo
```

### Check sync status
```bash
curl -s http://localhost:8591/drc/api/sync-status
```

### View Wings logs
```bash
journalctl -u wings -f
```

### Test SSH connection
```bash
# Test borg access
ssh -i /root/.ssh/borg_backup -p 23 u123456@u123456.your-storagebox.de borg --version

# Test rsync access
rsync --dry-run -avz -e "ssh -i /root/.ssh/storagebox_rsync -p 23" /tmp/ u123456@u123456.your-storagebox.de:./test/
```

### Clear sync queue
```bash
curl -X POST http://localhost:8591/drc/api/sync/clear-queue
```

### Reset circuit breaker
```bash
curl -X POST http://localhost:8591/drc/api/sync/reset-circuit-breaker
```

---

## Legacy Configuration

> **Note:** The `disaster_recovery` section under `borg` is deprecated but still supported for backwards compatibility. New installations should use the structure above.

```yaml
# DEPRECATED - use borg.remote and borg.sync instead
borg:
  disaster_recovery:
    enabled: true
    remote_repository: "..."
    ssh_key: "..."
    # ... other settings
```

The system automatically falls back to legacy settings if new settings are not defined.
