# Configuration Guide

> This page documents the current wings-dedup build. Settings such as `trim`, `delete_grace_days`
> and kopia `auto_maintenance_enabled` need a newer build than this repository's public release;
> an older binary ignores keys it does not know.

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

Backups stored locally first, then synced to remote in background. Recommended for most setups.

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
3. The recovery console shows sync status at `/admin/recovery`

**Pros:** Fast local backups + disaster recovery  
**Cons:** Uses more disk space (local + remote)

---

## Configuration Reference

### Top-Level Settings

| Setting | Values | Description |
|---------|--------|-------------|
| `backend` | `borg`, `kopia` | Which backup tool to use (borg recommended) |
| `storage_mode` | `local`, `remote`, `hybrid` | Where backups are stored |
| `transfer_grace_days` | integer (default: `30`) | Days to keep a transferred-away server's backup archives before orphan cleanup can delete them. Prevents archives from being immediately reaped after a server is transferred out. `0` means UNLIMITED: the archives are kept indefinitely and orphan cleanup never reaps them (remove them by hand or via the admin purge endpoint). A negative value is treated as unset and falls back to 30. |
| `delete_grace_days` | integer (default: `7`) | Days the **remote** disaster-recovery repository keeps a **deleted** server's archives after the panel deletes the server. Local archives are still removed immediately; this is purely the remote recovery window, covering a server deleted by mistake or by a billing lapse the customer then settles. Without it the remote copy is protected only by `remote_retention_days`, which is measured from the archive's **creation** date, so an archive made shortly before its server was deleted would outlive it only by the remainder of its own window. `0` means UNLIMITED. A negative value is treated as unset and falls back to 7. |

### Filesystem Trim

For nodes that mount their volumes `nodiscard`. With online `discard` in fstab, every unlink becomes a discard issued at journal commit; one large delete (a restore with truncate, a server delete, a borg compact) then queues in front of every other write and every server on the node stalls on fsync. Mounting `nodiscard` makes the delete a metadata update, and this job hands the freed space back to the disk once a day in bounded ranges, waiting while IO pressure is high and never overlapping a remote maintenance pass.

```yaml
system:
  backups:
    trim:
      enabled: true
      schedule: "0 4 * * *"       # cron, node local time; pick the quietest hour
      path: /var/lib/pterodactyl  # any path on the filesystem; the whole filesystem is trimmed
      chunk_gib: 64               # one FITRIM call per chunk; bounds the longest single stall
      pause_seconds: 2            # rest between chunks
      max_io_pressure: 15         # /proc/pressure/io "some avg10" % above which the next chunk waits
      max_duration_minutes: 120   # a run cut short is fine; the next one starts over cheaply
```

After enabling, remove `discard` from the root (or volumes) entry in `/etc/fstab` and `mount -o remount,nodiscard /`. Keep the distro `fstrim.timer` as a weekly safety net if you like; move it to the same quiet hour.

`GET /api/system/fstrim` reports the schedule and the last run. `POST /api/system/fstrim` starts a run now (202), or 409 while one is in progress. Both take the node token.

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
    remote_retention_days: 7       # Days a locally-deleted backup stays on the remote
    stale_worker_minutes: 5        # Alert threshold for stuck workers
    disable_auto_prune: false      # true stops the nightly remote prune+compact
```

### Remote maintenance

The remote disaster-recovery repository is maintained by a nightly pass (3 AM
plus a per-node jitter of up to 90 minutes, so a fleet pointed at one storage
box does not start seven concurrent compacts at the same instant). The pass
deletes archives that are past retention and then compacts, because **borg frees
no disk space on delete** until a compact rewrites the segments.

Two settings can switch it off, and both used to fail silently:

- `disable_auto_prune: true` stops the pass entirely. The remote then grows
  without bound while the local repository, which the panel prunes, stays
  healthy. It defaults to `false`; a node whose config carries `true` from an
  older default keeps that behaviour until the value is changed.
- `remote_retention_days: 0` disables **deletion** (the append-only-SSH case).
  It no longer disables the compact: a repository configured this way still gets
  its overdue compact, so segments left behind by earlier deletes are reclaimed.

The pass records when it last ran in `remote-maintenance.json`, beside
`sync-queue.json`. Two things follow from that:

- If the last recorded pass is over a day old, wings runs a **catch-up** five
  minutes after start rather than waiting for the next 3 AM window. A node that
  never happens to be running at 3 AM used to never prune at all.
- A **compact runs at least weekly** even when the pass deleted nothing, so
  reclaim is not stranded by a run that deleted archives and then aborted before
  its compact.

To confirm the pass is working on a node:

```sh
cat /var/lib/pterodactyl/backups/remote-maintenance.json
journalctl -u wings --no-pager -n 200 | grep -i 'remote retention\|compact'
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
| No cache conflicts | Cannot resume interrupted syncs |
| Immediate sync after backup | Full archive re-transfer on failure |
| Works with restricted SSH (borg-serve) | Slightly slower for very large archives |
| Dedup preserved on both ends | |

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
| Can resume interrupted transfers | "Cache is newer" errors possible |
| Efficient for incremental changes | Requires SFTP/rsync SSH access |
| Familiar rsync semantics | May sync incomplete data if backup in progress |
| | Scans entire repo (slow for large repos) |

**Best for:** Very large repos (500GB+) where resume capability matters, or providers without borg-serve support.

> **Important:** If your storage provider (e.g., Hetzner Storage Box) uses **different SSH keys** for borg-serve mode vs SFTP/rsync access, set `rsync_ssh_key` to the SFTP key path.

### Maintenance Settings

Configure automated maintenance tasks. They live under each backend's own block
(`system.backups.borg.maintenance` / `system.backups.kopia.maintenance`); a top-level
`system.maintenance` block is not read.

```yaml
system:
  backups:
    borg:
      maintenance:
        orphan_cleanup_enabled: true          # Remove backups for deleted servers
        orphan_cleanup_schedule: "0 3 * * *"  # Cron: 3 AM daily (also runs compact)
        check_on_startup: false               # Run borg check at startup (slow for large repos)
    kopia:
      maintenance:
        orphan_cleanup_enabled: true
        orphan_cleanup_schedule: "0 3 * * *"
        deleted_grace_days: 7                 # days a deleted backup stays recoverable (0 = immediate)
        auto_maintenance_enabled: true        # kopia's own quick/full maintenance schedule
        quick_interval: "1h"
        full_interval: "24h"
```

| Setting | Default | Description |
|---------|---------|-------------|
| `orphan_cleanup_enabled` | `true` | Automatically cleanup backups for deleted servers |
| `orphan_cleanup_schedule` | `0 3 * * *` | Cron expression for cleanup + compact job |
| `check_on_startup` | `false` | (borg) Run borg check when Wings starts |
| `deleted_grace_days` | `7` | (kopia) Days a deleted backup stays recoverable before its snapshot is removed |
| `auto_maintenance_enabled` | `true` | (kopia) Let wings enable kopia's own maintenance schedule |

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

Direct backups to remote object storage.

```yaml
system:
  backups:
    backend: "kopia"
    storage_mode: "remote"
    
    kopia:
      enabled: true                  # required: kopia refuses to run without it
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
        password: "a-long-random-secret"   # required; keep a copy, the repository is unreadable without it
```

**Supported providers:** AWS S3, Backblaze B2, Cloudflare R2, Wasabi, MinIO

---

## DRC (Disaster Recovery Console)

The console is served at **`https://your-node:8591/admin/recovery`**. This path
is fixed and is not configurable.

```yaml
system:
  backups:
    # Disaster recovery reads the REMOTE repository, which requires:
    storage_mode: hybrid          # or "remote"; with "local" there is nothing to recover from

    drc:
      enabled: true
      download_bwlimit: "50M"     # rate limit for archive downloads from the console
      drc_password: "your-secret" # password sign-in

      # Refuse the node's daemon token as a console credential. Recommended on
      # deployments where several nodes share one remote repository, so one
      # node's token cannot reach another node's archives. Ignored unless a
      # drc_password or Discord OAuth is configured, so it cannot lock you out.
      exclusive_recovery_token: false

      # Or sign in with Discord
      discord_oauth:
        enabled: true
        client_id: ""
        client_secret: ""
        redirect_url: "https://your-node:8591/api/admin/auth/discord/callback"
        allowed_user_ids: ["your-discord-id"]   # empty list = nobody is allowed
```

### Authentication

Signing in exchanges the password (or a Discord identity) for a session held in
an `HttpOnly` cookie; the credential itself is never stored in the browser.
State-changing requests additionally carry a CSRF token.

Failed sign-in attempts are counted per source address and logged. After 8
failures inside 15 minutes that address is locked out, with the lockout
doubling on each repeat up to an hour. A successful sign-in clears the count,
so mistyping the password a few times costs nothing.

The node's daemon token also authenticates to `/api/admin/*` (this is what the
panel's Auto Backup extension uses) unless `exclusive_recovery_token` is set.

### Keys that do nothing

`system.backups.drc` also accepts `access_path`, `remote_repository`,
`ssh_key`, `ssh_port`, `borg_path`, `upload_bwlimit`, `sync_mode`,
`sync_workers`, `batch_delay_seconds`, `timeout_hours`, `lock_wait_seconds`,
`rsync_concurrency`, `rsync_delete` and `remote_retention_days`.

**None of them are read.** Disaster recovery runs off
`system.backups.borg.remote.*` and `system.backups.borg.sync.*`. Setting
`drc.remote_retention_days: 30` changes nothing. The live key is
`system.backups.borg.sync.remote_retention_days`. Wings logs a warning naming
the replacement for each of these it finds in your configuration at startup.

---

## Troubleshooting

### Check Borg repository
```bash
borg info /var/lib/pterodactyl/backups/borg-repo
```

### Check sync status
```bash
curl -s -H "Authorization: Bearer $DAEMON_TOKEN" \
  http://localhost:8591/api/admin/backups/sync-status
```

### Check remote repository health
Reports the corruption circuit breaker, the sync queue depth and any rebuild in
progress. The recovery console shows the same information under
**Remote repository health**.
```bash
curl -s -H "Authorization: Bearer $DAEMON_TOKEN" \
  http://localhost:8591/api/admin/remote-health
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

### Recover from a corrupt remote repository

When the remote repository loses segments its index still references, every
sync fails identically. Wings trips a circuit breaker: it alerts once, stops
syncing (queued archives are kept, local backups are unaffected) and re-tests
the repository every 15 minutes, resuming on its own if it becomes readable.

`borg check --repair` is deliberately never run automatically. Over SSH
against a large remote it reliably fails to finish, and an interrupted repair
damages the repository further.

If the repository will not recover, rebuild it from the **Remote repository
health** panel in the console, or:

```bash
curl -X POST -H "Authorization: Bearer $DAEMON_TOKEN" \
  -H 'Content-Type: application/json' -d '{"confirm":"REBUILD"}' \
  http://localhost:8591/api/admin/remote-health/rebuild
```

This **deletes the entire remote repository**, re-initialises it and queues
every local archive for re-upload. It requires `storage_mode: hybrid`, because
that is the only mode where the local repository is the authoritative copy to
rebuild from. Until the queue drains, the node has no off-site DR coverage.
```

---


## Full Configuration Example

Full `backups` block for `config.yml`:

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
      maintenance:
        orphan_cleanup_enabled: true
        orphan_cleanup_schedule: "0 3 * * *"
        deleted_grace_days: 7
        auto_maintenance_enabled: true
        quick_interval: "1h"
        full_interval: "24h"

    # Disaster Recovery Console, served at /admin/recovery
    drc:
      enabled: true
      download_bwlimit: "50M"
      drc_password: ""
      exclusive_recovery_token: false
      discord_oauth:
        enabled: false
        client_id: ""
        client_secret: ""
        redirect_url: ""
        allowed_user_ids: []

    notifications:
      discord_webhook: ""
```

### Kopia repository maintenance

| Key | Default | Description |
|-----|---------|-------------|
| `auto_maintenance_enabled` | `true` | Write kopia's own maintenance schedule into the repository at startup |
| `quick_interval` | `1h` | Quick maintenance, the cycle that compacts index blobs |
| `full_interval` | `24h` | Full maintenance, which also collects unreferenced blobs |

Wings does not run these itself. It records the intervals in the repository and
kopia runs them on its own lock, at the end of commands wings already issues.
Both intervals are kopia's own defaults.

Maintenance previously ran only after an orphan cleanup that actually deleted
something, so a node that never deleted a backup never ran it. Its index blob
count then climbed until kopia began printing

```
Found too many index blobs (N), this may result in degraded performance.
```

on **every** invocation, which is a real outage rather than a performance note:
that line is written to stderr on every command, and any wings code merging
stderr into the JSON it parses would fail to read backup listings, sizes, orphan
detection, prune and restore lookups. Wings reads the payload off stdout so the
banner cannot corrupt it, but the underlying repository still wants maintaining.

Ownership is claimed only when the repository records no owner. A repository
owned by another node is left alone and logged; wings never takes ownership from
it, because two nodes running maintenance over one repository is how a
repository gets damaged. Set the owner to `nobody` with `kopia maintenance set`
to keep wings out of it entirely.

---

## Database Backups

The panel addon posts a gzip-compressed mysqldump stream to Wings, which stores it in the dedup repository (Borg or Kopia) without using server file space.

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/servers/{uuid}/db-backup/{backupUUID}` | Archive a dump stream into Borg/Kopia |
| `GET` | `/api/servers/{uuid}/db-backup/{backupUUID}` | Stream the dump back out |
| `DELETE` | `/api/servers/{uuid}/db-backup/{backupUUID}` | Remove the archive/snapshot |

The backend used (Borg or Kopia) and storage mode are determined by your existing `backend` and `storage_mode` settings. No extra configuration is needed.

- **Borg:** the dump is stored as archive `db-{backupUUID}` inside the same repository as file backups, using `borg create --stdin-name dump.sql.gz`.
- **Kopia:** the dump is stored as a snapshot tagged `backup_uuid:{backupUUID}`, using `kopia snapshot create --stdin-file dump.sql.gz`.
- In hybrid mode, Kopia triggers a remote sync after each database backup.
- Database backups are pruned and deleted through the panel addon; Wings deletes the corresponding archive/snapshot on request.

---

## Legacy Configuration


> The `disaster_recovery` section under `borg` is deprecated. New installations should use the structure above.

```yaml
# DEPRECATED - use borg.remote and borg.sync instead
borg:
  disaster_recovery:
    enabled: true
    remote_repository: "..."
    ssh_key: "..."
    # ... other settings
```

