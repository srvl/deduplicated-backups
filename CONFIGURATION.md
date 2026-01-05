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
        borg_path: "borg"
```

**Pros:** Offsite backups, survives node failure  
**Cons:** Slower backups due to network latency, requires always-on network access

---

### Hybrid (Borg with Remote Sync)

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
        borg_path: "borg"
      
      sync:
        mode: "native"                 # "native" (recommended) or "rsync"
        workers: 1
        upload_bwlimit: "50M"          # Limit upload speed (MB/s)
        timeout_hours: 4               # Max sync time
        lock_wait_seconds: 300         # Borg lock wait
```

**How it works:**
1. Backup completes instantly to local repo
2. Archive is synced to remote via borg export-tar/import-tar (native mode)
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
    borg_path: "borg"
```

#### Sync Settings (Hybrid mode)
```yaml
borg:
  sync:
    mode: "native"                 # "native" (recommended) or "rsync" (legacy)
    workers: 1                     # Number of sync workers
    upload_bwlimit: "50M"          # Upload speed limit
    timeout_hours: 4               # Max sync operation time
    lock_wait_seconds: 300         # Borg lock wait time
    # Rsync-specific options (only when mode: "rsync")
    batch_delay_seconds: 10        # Wait before syncing
    rsync_ssh_key: ""              # Optional separate key for rsync
    rsync_delete: false            # DANGER: sync local deletions to remote
    remote_retention_days: 0       # Days before cleaning remote orphans (0=disabled)
    stale_worker_minutes: 5        # Alert threshold for stuck workers
```

### Sync Mode: Native vs Rsync

Choose your sync mode based on your use case:

#### Native Mode (Recommended)
```yaml
borg:
  sync:
    mode: "native"
```

**How it works:** Each archive is exported via `borg export-tar`, streamed over SSH, and imported to remote via `borg import-tar`.

| Pros | Cons |
|------|------|
| ✅ No cache conflicts | ❌ Cannot resume interrupted syncs |
| ✅ Immediate sync after backup | ❌ Full archive re-transfer on failure |
| ✅ Works with restricted SSH (borg-serve) | ❌ Slightly slower for very large archives |
| ✅ Dedup preserved on both ends | |

**Best for:** Most users, Hetzner Storage Box, any provider supporting borg-serve.

---

#### Rsync Mode (Legacy)
```yaml
borg:
  sync:
    mode: "rsync"
    rsync_ssh_key: "/root/.ssh/storagebox_rsync"  # May need separate key
```

**How it works:** The entire local borg repository directory is synced to remote using rsync.

| Pros | Cons |
|------|------|
| ✅ Can resume interrupted transfers | ❌ "Cache is newer" errors possible |
| ✅ Efficient for incremental changes | ❌ Requires SFTP/rsync SSH access |
| ✅ Familiar rsync semantics | ❌ May sync incomplete data if backup in progress |
| | ❌ Scans entire repo (slow for large repos) |

**Best for:** Very large repos (500GB+) where resume capability matters, or providers without borg-serve support.

> **Important:** If your storage provider (e.g., Hetzner Storage Box) uses **different SSH keys** for borg-serve mode vs SFTP/rsync access, set `rsync_ssh_key` to the SFTP key path.

### Maintenance Settings

Configure automated maintenance tasks:

```yaml
system:
  maintenance:
    orphan_cleanup_enabled: true      # Remove backups for deleted servers
    orphan_cleanup_schedule: "0 3 * * *"  # Cron: 3 AM daily (also runs compact)
    check_on_startup: false           # Run borg check at startup (slow for large repos)
```

| Setting | Default | Description |
|---------|---------|-------------|
| `orphan_cleanup_enabled` | `true` | Automatically cleanup backups for deleted servers |
| `orphan_cleanup_schedule` | `0 3 * * *` | Cron expression for cleanup + compact job |
| `check_on_startup` | `false` | Run borg check when Wings starts |

**Manual Prune:** You can trigger maintenance manually from the Panel addon's "Prune Backups" button, or via API:
```bash
curl -X POST -H "Authorization: Bearer <wings-token>" https://your-node:8591/api/admin/backups/prune
```

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


## Complete Modern Configuration Example

Here is a full `backups` configuration block with all modern settings and no legacy fields. You can copy this into your `config.yml` under the `system` block.

```yaml
system:
  backups:
    write_limit: 0
    compression_level: "best_speed"
    
    # Backend: "borg" (recommended) or "kopia"
    backend: "borg"
    
    # Storage Mode: "local", "remote", or "hybrid"
    storage_mode: "hybrid"

    # Borg Configuration (when backend is "borg")
    borg:
      local_repository: "/var/lib/pterodactyl/backups/borg"
      compression: "lz4"
      
      encryption:
        enabled: true
        passphrase: "change-me"
        mode: "repokey-blake2"
      
      remote:
        repository: "ssh://user@host:port/./path"
        ssh_key: "/path/to/private/key"
        ssh_port: 23
        borg_path: "borg"
      
      sync:
        mode: "native"
        workers: 1
        batch_delay_seconds: 10
        upload_bwlimit: "50M"
        timeout_hours: 4
        lock_wait_seconds: 300
        rsync_ssh_key: ""
        remote_retention_days: 7
        stale_worker_minutes: 5
        rsync_concurrency: 4
      
      performance:
        max_concurrent: 1
        lock_timeout_seconds: 300
        backup_timeout_minutes: 0
        max_retries: 3
        retry_delay_seconds: 10
        chunk_params: "auto"
        upload_buffer_mb: 100
      
      maintenance:
        orphan_cleanup_enabled: true
        orphan_cleanup_schedule: "0 3 * * *"
        check_on_startup: false
        panel_url: ""
        panel_api_token: ""

    # Kopia Configuration (when backend is "kopia")
    kopia:
      enabled: false
      s3:
        endpoint: ""
        region: "us-east-1"
        bucket: ""
        prefix: "backups"
        access_key: ""
        secret_key: ""
      cache:
        enabled: true
        path: "/var/lib/pterodactyl/backups/kopia-cache"
        size_mb: 5000
      encryption:
        enabled: true
        password: ""
      performance:
        parallel_uploads: 4
        upload_bwlimit: "50M"

    # Disaster Recovery Console
    drc:
      enabled: true
      access_path: "/admin/drc"
      download_bwlimit: "50M"
      recovery_token: ""
      discord_oauth:
        enabled: false
        client_id: ""
        client_secret: ""
        redirect_url: ""
        allowed_user_ids: []

    notifications:
      discord_webhook: ""
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
