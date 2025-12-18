# Changelog

All notable changes to this project will be documented in this file.

This project follows the principles of **Keep a Changelog**  
and adheres to **Semantic Versioning** (https://semver.org).

---

## [1.0.0] – 2025-12-18

### Added
- Initial public release of **CachyOS AutoTune**
- Fully automated, modular tuning script for CachyOS (Arch Linux)
- Automatic environment detection:
  - Logged-in user
  - CPU vendor and capabilities
  - NVIDIA GPU presence
  - systemd-boot bootloader
  - Btrfs filesystem
- Safe execution model with:
  - Idempotent behavior
  - Automatic backups before modifying system files
  - Dry-run mode (`--dry-run`)
  - Minimal mode (`--minimal`)

### System Maintenance
- Pacman configuration tuning:
  - Parallel downloads
  - Improved output readability
- Safe cache cleanup routines
- CachyOS mirror ranking support
- Post-update audit reporting

### Build & AUR Optimization
- CPU-aware `makepkg` configuration
- Fast and efficient `zstd` compression
- Safe `yay` configuration without sudo usage

### Boot & Kernel
- Automated systemd-boot entry tuning
- AMD P-State configuration when supported
- zswap disabled when zram is in use
- Conservative kernel mitigation flags
- NVIDIA DRM/KMS enabled only when NVIDIA hardware is detected

### Initramfs
- Optimized `mkinitcpio` hooks for systemd-initramfs
- NVIDIA modules included in initramfs when applicable
- Optimized zstd compression settings
- Fallback initramfs always preserved

### Filesystem & Memory
- Btrfs mount option normalization
- Commit interval tuning with conservative defaults
- Desktop-oriented memory tuning:
  - Swappiness
  - VFS cache pressure
- Transparent Huge Pages set to `madvise`
- PSI support kept for auditing and diagnostics

### Snapshot Management
- Snapper configuration for `/home`
- Automatic snapshot cleanup
- Timer-based snapshot lifecycle management

### Networking & Virtualization
- NetworkManager bridge (`br0`) for KVM/QEMU
- Automatic physical NIC detection
- Wake-on-LAN compatible configuration

### Hardware Utilities
- NVIDIA driver cleanup and stabilization
- OpenRGB daemon setup
- Wayland-compatible OpenRGB GUI via X11 (`xcb`)
- Automatic user session startup

### Application Support
- Flatpak installation and Flathub integration
- Snapd installation, socket activation and `/snap` symlink

### Intentionally Excluded
- Fixed monitor layouts (KDE Wayland)
- Hardcoded printer configurations
- Visual or subjective desktop tweaks
- Credentials, secrets or VPN configurations

---

## [Unreleased]

### Planned
- Laptop-specific profile (power and thermal awareness)
- Optional Paru support
- Non-interactive CI validation (shellcheck)
- Versioned configuration profiles
- Optional rollback per module
