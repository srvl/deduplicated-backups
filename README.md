# Wings-Dedup

Deduplicated backups for Pterodactyl using Borg or Kopia.

See [CONFIGURATION.md](CONFIGURATION.md) for detailed setup tutorials.

## Installation

### One-Line Installer

```bash
bash <(curl -sL https://github.com/srvl/deduplicated-backups/raw/main/install-wings.sh)
```

### Manual Installation

```bash
chmod +x install-wings.sh
./install-wings.sh
```

The installer will prompt for your license key, backup backend, and storage configuration.

## Configuration

Configuration is stored in `/etc/pterodactyl/config.yml`:

```yaml
license:
  license_key: "your-license-key"

system:
  backups:
    backend: "borg"
    storage_mode: "hybrid"
    
    borg:
      local_repository: "/var/lib/pterodactyl/backups/borg-repo"
      compression: "lz4"
      
      remote:
        repository: "ssh://user@host:port/./path"
        ssh_key: "/root/.ssh/id_ed25519"
        ssh_port: 23
      sync:
        mode: "native"
        upload_bwlimit: "50M"
```

## Updating

Put the `wings_amd` / `wings_arm` from your latest download next to the installer, run it and
select option 2 (binary-only update):

```bash
./install-wings.sh
```

The installer uses a binary next to it before anything else. Without one it falls back to this
repository's latest release, which can be older than your download, so it refuses to replace a
newer installed version (`FORCE_DOWNGRADE=1` overrides). Option 1 on a node that is already set up
also runs the update instead of rebuilding your backup settings (`FULL_SETUP_FORCE=1` overrides).

## Commands

```bash
journalctl -u wings -f          # View logs
systemctl restart wings         # Restart
nano /etc/pterodactyl/config.yml  # Edit config
```

## Support

Discord: https://discord.gg/9RNXfZ2Hsm
