# Installation Guide

This document describes the recommended way to install and use **CachyOS AutoTune**
on a clean or existing CachyOS system.

---

## Prerequisites

Before running the script, ensure:

- CachyOS is installed and updated
- systemd is the active init system
- You have sudo privileges
- The system is booting normally

Optional but recommended:

- Btrfs filesystem
- systemd-boot
- KDE Plasma (Wayland)

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/<your-username>/cachyos-autotune.git
cd cachyos-autotune
```

### 2. Review the script

Always review automation scripts before execution:

```bash
less cachyos-autotune.sh
```

---

## Execution

### Dry-run (recommended first)

```bash
sudo ./cachyos-autotune.sh --dry-run
```

This mode shows all actions without applying changes.

---

### Standard execution

```bash
sudo ./cachyos-autotune.sh
```

---

### Minimal mode

Apply only package management and maintenance tuning:

```bash
sudo ./cachyos-autotune.sh --minimal
```

---

## Reboot

Some changes (bootloader, initramfs, kernel parameters) require a reboot
to take full effect.

Reboot when convenient:

```bash
reboot
```

---

## Troubleshooting

- Use `--dry-run` to validate behavior
- Check backups created next to modified files
- Review system logs if needed:
  ```bash
  journalctl -xe
  ```

---

## Uninstallation / Rollback

There is no destructive change applied automatically.

To rollback:

- Restore files from `.bak.<timestamp>` backups
- Select a previous entry in systemd-boot if needed
- Use initramfs fallback images

---

## Notes

This project intentionally avoids unsafe or experimental tweaks.
All applied configurations were tested in real desktop and workstation
environments.
