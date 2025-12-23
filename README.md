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
        mode: "rsync"
        upload_bwlimit: "50M"
```

## Updating

Run the installer and select option 2 for binary-only updates:

```bash
./install-wings.sh
```

## Commands

```bash
journalctl -u wings -f          # View logs
systemctl restart wings         # Restart
nano /etc/pterodactyl/config.yml  # Edit config
```

## Support

Discord: https://discord.gg/ZssvBxPK6e
