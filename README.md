# CachyOS AutoTune

![Arch Linux](https://img.shields.io/badge/Arch%20Linux-supported-blue?logo=arch-linux&logoColor=white)
![CachyOS](https://img.shields.io/badge/CachyOS-optimized-4CAF50)
![systemd](https://img.shields.io/badge/systemd-required-000000?logo=systemd&logoColor=white)
![Btrfs](https://img.shields.io/badge/Btrfs-supported-FF6F00)
![NVIDIA](https://img.shields.io/badge/NVIDIA-optional-76B900?logo=nvidia&logoColor=white)
![ShellCheck](https://img.shields.io/badge/ShellCheck-enabled-brightgreen?logo=gnu-bash&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-lightgrey)


**Author:** Fernando Albino  
*Safe, reproducible and automated system tuning for CachyOS (Arch Linux)*

---

## Overview

**CachyOS AutoTune** is a **production-grade, modular automation script** designed for  
**safe, efficient and reproducible system tuning** on **CachyOS (Arch Linux)**.

All configurations included in this project were **tested in real desktop and workstation
environments**, prioritizing **stability, performance and long-term maintainability**.

This repository aims to provide a **clean, auditable and portable baseline** for users who
want a well-tuned CachyOS system without relying on experimental or unsafe tweaks.

### Supported environments

- KDE Plasma (Wayland-friendly)
- AMD Ryzen and Intel CPUs
- NVIDIA GPUs (Wayland + KMS)
- Btrfs filesystem
- systemd + systemd-boot
- Development, build-heavy and virtualization workloads

---

## Design principles

CachyOS AutoTune follows strict engineering principles:

- **Idempotent execution**  
  Safe to run multiple times without side effects.

- **Automatic environment detection**  
  User, CPU, GPU, bootloader and filesystem are detected dynamically at runtime.

- **No hardcoded values**  
  No fixed UUIDs, interfaces, paths or credentials.

- **Safe by default**  
  Automatic backups are created before modifying any critical system file.

- **Modular architecture**  
  Each tuning area can be enabled or disabled independently.

---

## Features

### System maintenance
- Pacman optimization (parallel downloads, improved readability)
- Safe package cache cleanup
- Official CachyOS mirror ranking
- Post-update audit reporting

### Build & AUR optimization
- CPU-aware `makepkg` configuration
- Fast and efficient `zstd` compression
- Safe `yay` configuration (no sudo usage)

### Boot & kernel tuning
- Automatic **systemd-boot** entry adjustments
- AMD P-State configuration when supported
- `zswap` disabled when zram is in use
- Conservative and safe kernel mitigation flags
- NVIDIA DRM/KMS enabled **only when NVIDIA hardware is detected**

### Initramfs optimization
- Optimized `mkinitcpio` hooks for systemd-initramfs
- NVIDIA modules included when applicable
- `zstd -3` compression
- Fallback initramfs always preserved

### Filesystem & memory
- Btrfs mount option normalization
- Commit interval tuning with conservative defaults
- Desktop-oriented memory tuning:
  - `vm.swappiness`
  - `vm.vfs_cache_pressure`
- Transparent Huge Pages configured for low-latency workloads
- PSI kept for auditing and diagnostics

### Snapshot management
- Snapper configuration for `/home`
- Automatic snapshot cleanup
- Timer-based snapshot lifecycle management

### Networking & virtualization
- NetworkManager bridge (`br0`) for KVM/QEMU
- Automatic physical NIC detection
- Wake-on-LAN compatible configuration

### Hardware utilities
- NVIDIA driver cleanup and stabilization
- OpenRGB daemon setup
- Wayland-compatible OpenRGB GUI via X11 (`xcb`)
- Automatic user session startup

### Application support
- Flatpak installation with Flathub integration
- Snapd installation, socket activation and `/snap` symlink

---

## Intentionally excluded

The following items are **explicitly not automated** to preserve portability and safety
across different machines:

- Fixed monitor layouts (KDE Wayland)
- Hardcoded printer configurations
- Visual or subjective desktop tweaks
- Credentials, secrets or VPN configurations

Templates and examples can be provided separately when required.

---

## Repository structure

```text
.
├── cachyos-autotune.sh
├── README.en-US.md
├── README.pt-BR.md
├── CHANGELOG.md
└── docs/
```

---

## Usage

### Standard execution
```bash
chmod +x cachyos-autotune.sh
sudo ./cachyos-autotune.sh
```

### Dry-run mode (no changes applied)
```bash
sudo ./cachyos-autotune.sh --dry-run
```

### Minimal mode (packages and maintenance only)
```bash
sudo ./cachyos-autotune.sh --minimal
```

---

## Safety and rollback

- Automatic backups before any critical change
- systemd-boot entries are preserved
- Initramfs fallback images are always available
- No destructive or experimental tweaks are applied

---

## Versioning

This project follows **Semantic Versioning**.

See [`CHANGELOG.md`](CHANGELOG.md) for detailed release notes.

---

## Target audience

- Advanced CachyOS / Arch Linux users
- Developers and power users
- Desktop and workstation environments
- Virtualization and KVM/QEMU hosts

---

Maintained by **Fernando Albino**  
Tested on CachyOS (Arch Linux) desktop and workstation environments.
