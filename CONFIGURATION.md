# Configuration Guide

This guide covers all Wings-Dedup configuration options with examples for common setups.

---

## Table of Contents

1. [Configuration Reference](#configuration-reference)
2. [Borg Tutorials](#borg-tutorials)
   - [Local Only](#borg-local-only)
   - [Remote Only (SSH)](#borg-remote-only)
   - [Local + Remote Sync](#borg-local--remote-sync)
3. [Kopia Tutorials](#kopia-tutorials)
   - [Local Only](#kopia-local-only)
   - [Remote Only (S3)](#kopia-remote-only-s3)
   - [Local + Remote Sync](#kopia-local--remote-sync)

---

## Configuration Reference

All settings go in `/etc/pterodactyl/config.yml` under the `system.backups` section.

### Top-Level Settings

| Setting | Values | Description |
|---------|--------|-------------|
| `backend` | `borg`, `kopia` | Which backup tool to use |
| `storage_mode` | `local`, `remote`, `hybrid` | Where backups are stored |

### Borg Settings

```yaml
borg:
  enabled: true
  local_repository: "/var/lib/pterodactyl/backups/borg-repo"
  compression: "lz4"  # Options: none, lz4, zstd, zlib
  
  encryption:
    enabled: false
    passphrase: ""  # Required if encryption enabled
  
  performance:
    chunk_params: "auto"
    upload_buffer_mb: 100
  
  remote:
    repository: "ssh://user@host:port/./path"
    ssh_key: "/root/.ssh/id_ed25519"
    ssh_port: 23
    borg_path: "borg-1.4"
  
  sync:
    mode: "rsync"  # Options: rsync, export-tar
    workers: 1
    upload_bwlimit: "50M"
    stale_worker_minutes: 5
```

### Kopia Settings

```yaml
kopia:
  enabled: true
  
  s3:
    endpoint: "s3.amazonaws.com"
    region: "us-east-1"
    bucket: "my-bucket"
    access_key: "AKIAXXXXXXXX"
    secret_key: "secret"
    prefix: "backups/"
  
  cache:
    enabled: true
    path: "/var/lib/pterodactyl/backups/kopia-cache"
    size_mb: 5000
  
  encryption:
    enabled: true
    password: ""  # Auto-generated if empty
```

---

## Borg Tutorials

### Borg: Local Only

Backups stored only on the local disk. Simple setup, no external dependencies.

```yaml
system:
  backups:
    backend: "borg"
    storage_mode: "local"
    
    borg:
      enabled: true
      local_repository: "/var/lib/pterodactyl/backups/borg-repo"
      compression: "lz4"
      encryption:
        enabled: false
```

**Pros:** Fast, simple, no network latency  
**Cons:** No disaster recovery if disk fails

---

### Borg: Remote Only

Backups go directly to remote storage (SSH). No local copy kept.

**Requirements:**
- SSH access to remote storage (Hetzner Storage Box, NAS, etc.)
- SSH key configured

```yaml
system:
  backups:
    backend: "borg"
    storage_mode: "remote"
    
    borg:
      enabled: true
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

**Setup SSH key (Hetzner Storage Box):**
```bash
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""
cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
scp -P 23 /root/.ssh/authorized_keys u123456@u123456.your-storagebox.de:.ssh/
```

**Pros:** Offsite backups, survives node failure  
**Cons:** Slower backups due to network latency

---

### Borg: Local + Remote Sync

Backups stored locally, then synced to remote in background. Best of both worlds.

```yaml
system:
  backups:
    backend: "borg"
    storage_mode: "hybrid"
    
    borg:
      enabled: true
      local_repository: "/var/lib/pterodactyl/backups/borg-repo"
      compression: "lz4"
      encryption:
        enabled: false
      
      remote:
        repository: "ssh://u123456@u123456.your-storagebox.de:23/./borg-repo"
        ssh_key: "/root/.ssh/id_ed25519"
        ssh_port: 23
        borg_path: "borg-1.4"
      
      sync:
        mode: "rsync"
        workers: 1
        upload_bwlimit: "50M"
```

**How it works:**
1. Backup completes instantly to local repo
2. Background worker syncs to remote using rsync
3. Admin dashboard shows sync status at `/drc`

**Pros:** Fast local backups + disaster recovery  
**Cons:** Uses more disk space (local + remote)

---

## Kopia Tutorials

### Kopia: Local Only

Backups stored in local filesystem using Kopia.

```yaml
system:
  backups:
    backend: "kopia"
    storage_mode: "local"
    
    kopia:
      enabled: true
      
      filesystem:
        path: "/var/lib/pterodactyl/backups/kopia-repo"
      
      cache:
        enabled: true
        path: "/var/lib/pterodactyl/backups/kopia-cache"
        size_mb: 5000
```

---

### Kopia: Remote Only (S3)

Backups go directly to S3-compatible storage.

**Supported providers:**
- AWS S3
- Backblaze B2
- Cloudflare R2
- Wasabi
- MinIO

**AWS S3 Example:**
```yaml
system:
  backups:
    backend: "kopia"
    storage_mode: "remote"
    
    kopia:
      enabled: true
      
      s3:
        endpoint: "s3.amazonaws.com"
        region: "us-east-1"
        bucket: "my-pterodactyl-backups"
        access_key: "AKIAIOSFODNN7EXAMPLE"
        secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        prefix: "wings/"
      
      encryption:
        enabled: true
```

**Backblaze B2 Example:**
```yaml
system:
  backups:
    backend: "kopia"
    storage_mode: "remote"
    
    kopia:
      enabled: true
      
      s3:
        endpoint: "s3.us-west-004.backblazeb2.com"
        region: "us-west-004"
        bucket: "my-bucket"
        access_key: "your-key-id"
        secret_key: "your-application-key"
      
      encryption:
        enabled: true
```

**Cloudflare R2 Example:**
```yaml
system:
  backups:
    backend: "kopia"
    storage_mode: "remote"
    
    kopia:
      enabled: true
      
      s3:
        endpoint: "account-id.r2.cloudflarestorage.com"
        region: "auto"
        bucket: "my-bucket"
        access_key: "your-access-key"
        secret_key: "your-secret-key"
      
      encryption:
        enabled: true
```

---

### Kopia: Local + Remote Sync

Local cache with S3 backend for fast restores.

```yaml
system:
  backups:
    backend: "kopia"
    storage_mode: "hybrid"
    
    kopia:
      enabled: true
      
      s3:
        endpoint: "s3.amazonaws.com"
        region: "us-east-1"
        bucket: "my-pterodactyl-backups"
        access_key: "AKIAIOSFODNN7EXAMPLE"
        secret_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
      
      cache:
        enabled: true
        path: "/var/lib/pterodactyl/backups/kopia-cache"
        size_mb: 10000  # 10GB cache
      
      encryption:
        enabled: true
```

**How the cache works:**
- Recent backups stay in local cache for fast restores
- Older data fetched from S3 on demand
- Cache size limits prevent filling local disk

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

### Test SSH connection (Borg remote)
```bash
ssh -i /root/.ssh/id_ed25519 -p 23 u123456@u123456.your-storagebox.de
```
