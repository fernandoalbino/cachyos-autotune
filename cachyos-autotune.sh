#!/usr/bin/env bash
# ==============================================================================
# CachyOS AutoTune
# Automated, safe and reproducible system tuning for CachyOS (Arch Linux)
#
# Author:
#   Fernando Albino
#
# Description (EN):
#   CachyOS AutoTune is a modular automation script designed to apply
#   production‑ready system optimizations on CachyOS installations.
#   All adjustments included here were tested in real‑world desktop and
#   workstation environments and focus on performance, stability and
#   maintainability.
#
# Descrição (PT-BR):
#   O CachyOS AutoTune é um script de automação modular projetado para aplicar
#   otimizações de sistema confiáveis em instalações CachyOS.
#   Todos os ajustes aqui incluídos foram testados em ambientes reais de uso,
#   com foco em desempenho, estabilidade e facilidade de manutenção.
#
# Design principles:
#   - Idempotent execution (safe to run multiple times)
#   - Automatic environment detection (user, GPU, bootloader, filesystem)
#   - No hardcoded UUIDs, interfaces or credentials
#   - Automatic backups before any critical change
#   - Modular and readable structure for long‑term maintenance
#
# Usage:
#   sudo ./cachyos-autotune.sh
#   sudo ./cachyos-autotune.sh --dry-run
#
# ==============================================================================

set -Eeuo pipefail

# ----------------------------- Configuração -----------------------------------
# Você pode editar estes defaults para seu gosto.
# Para portabilidade (PC/notebook), prefira manter defaults conservadores.

PARALLEL_DOWNLOADS_DEFAULT="10"

# Btrfs: há duas recomendações nas suas notas (commit=60 e commit=120).
# Default conservador (desktop “equilibrado”): 60
# Perfil mais agressivo (NVMe/workstation): 120
BTRFS_COMMIT_DEFAULT="60"          # altere para 120 se quiser o perfil mais agressivo
BTRFS_COMPRESS_DEFAULT="zstd:3"    # zstd:3 foi o perfil “final” nas notas avançadas

# Sysctl (desktop com zram + swapfile): valores validados
VM_SWAPPINESS_DEFAULT="10"
VFS_CACHE_PRESSURE_DEFAULT="50"

# Pacotes base por módulo (instalados com pacman -S --needed)
PKGS_BASE=(reflector pacman-contrib)
PKGS_PRINTING=(cups epson-inkjet-printer-escpr2 openbsd-netcat)
PKGS_SNAP=(snapper)
PKGS_FLATPAK=(flatpak discover flatpak-kcm)
PKGS_OPENRGB=(openrgb)

# Módulos (ligados por padrão; podem ser desligados via flags/variáveis abaixo)
DO_MAINTENANCE=1
DO_PACMAN_TUNING=1
DO_MAKEPKG_TUNING=1
DO_YAY_TUNING=1
DO_MIRRORS=1

DO_BOOTLOADER_TUNING=1
DO_INITRAMFS_TUNING=1

DO_BTRFS_TUNING=1
DO_SYSCTL_TUNING=1
DO_JOURNALD_TUNING=1
DO_THP_TUNING=1

DO_SNAPPER_HOME=1

DO_NM_BRIDGE_KVM=1

DO_NVIDIA_CLEANUP=1

DO_OPENRGB=1
DO_FLATPAK_SNAP=1

# Itens propositalmente “off” por serem altamente específicos:
DO_PRINTER_EPSON_L6270=0          # precisa definir IP e nome; ver função
DO_BTRFS_SWAPFILE=0               # swapfile em btrfs exige muito cuidado; ver função

# -----------------------------------------------------------------------------


# ------------------------------ Argumentos ------------------------------------
DRY_RUN=0
MINIMAL=0
NO_REBOOT=0

for arg in "${@:-}"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --minimal) MINIMAL=1 ;;
    --no-reboot) NO_REBOOT=1 ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

if [[ $MINIMAL -eq 1 ]]; then
  DO_BOOTLOADER_TUNING=0
  DO_INITRAMFS_TUNING=0
  DO_BTRFS_TUNING=0
  DO_SYSCTL_TUNING=0
  DO_JOURNALD_TUNING=0
  DO_THP_TUNING=0
  DO_SNAPPER_HOME=0
  DO_NM_BRIDGE_KVM=0
  DO_NVIDIA_CLEANUP=0
  DO_OPENRGB=0
  DO_FLATPAK_SNAP=0
fi

# ------------------------------ Utilitários -----------------------------------
log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
warn() { printf '[%s] WARN: %s\n' "$(date +'%F %T')" "$*" >&2; }
die() { printf '[%s] ERROR: %s\n' "$(date +'%F %T')" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

run() {
  # Executa comando respeitando DRY_RUN e preservando logs legíveis.
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: $*"
    return 0
  fi
  log "RUN: $*"
  eval "$@"
}

backup_file() {
  local f="$1"
  [[ -e "$f" ]] || return 0
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local b="${f}.bak.${ts}"
  run "cp -a -- '$f' '$b'"
  log "Backup criado: $b"
}

ensure_root() {
  [[ $EUID -eq 0 ]] || die "Execute com sudo/root: sudo bash $0 [--dry-run]"
}

detect_user() {
  # Preferimos o usuário que invocou sudo; fallback: logname; fallback: UID 1000
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    echo "$SUDO_USER"
    return 0
  fi
  if need_cmd logname; then
    local u
    u="$(logname 2>/dev/null || true)"
    if [[ -n "$u" && "$u" != "root" ]]; then
      echo "$u"
      return 0
    fi
  fi
  # fallback razoável
  awk -F: '$3==1000{print $1; exit}' /etc/passwd
}

user_home() {
  local u="$1"
  getent passwd "$u" | awk -F: '{print $6}'
}

as_user() {
  # Executa um comando como o usuário alvo (sem “sudo -u” espalhado no script).
  local u="$1"; shift
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN (as $u): $*"
    return 0
  fi
  log "RUN (as $u): $*"
  sudo -u "$u" bash -lc "$*"
}

# ------------------------------ Detecção --------------------------------------
detect_bootloader_systemd_boot() {
  [[ -d /boot/loader/entries ]] && [[ -f /boot/loader/loader.conf ]]
}

detect_btrfs_root() {
  local fs
  fs="$(findmnt -n -o FSTYPE / || true)"
  [[ "$fs" == "btrfs" ]]
}

detect_kde_plasma() {
  # heurística leve
  [[ -d /usr/share/plasma ]] || [[ -d /etc/xdg/plasma-workspace ]]
}

detect_wayland() {
  # não dá para confiar no runtime (pode ser executado via TTY). Usamos pacotes/config.
  # Se KDE está presente, consideramos que Wayland é um alvo válido, mas não obrigatório.
  return 0
}

detect_nvidia_gpu() {
  if need_cmd lspci; then
    lspci | grep -Ei 'VGA|3D' | grep -qi nvidia && return 0
  fi
  # fallback: presença do módulo/pacotes
  lsmod | grep -q '^nvidia' && return 0
  pacman -Qq 2>/dev/null | grep -Eq '^nvidia' && return 0
  return 1
}

detect_default_nic() {
  # NIC associada à rota default IPv4
  if need_cmd ip; then
    ip -4 route show default 2>/dev/null | awk '{print $5; exit}'
  fi
}

# ------------------------------ Pacman/Yay ------------------------------------
pacman_install_needed() {
  local pkgs=("$@")
  [[ "${#pkgs[@]}" -gt 0 ]] || return 0
  run "pacman -S --needed --noconfirm ${pkgs[*]}"
}

tune_pacman_conf() {
  local f="/etc/pacman.conf"
  [[ -f "$f" ]] || { warn "pacman.conf não encontrado em $f (pulando)"; return 0; }
  backup_file "$f"

  # ParallelDownloads
  if grep -Eq '^\s*#?\s*ParallelDownloads\s*=' "$f"; then
    run "sed -i -E 's|^\s*#?\s*ParallelDownloads\s*=.*|ParallelDownloads = ${PARALLEL_DOWNLOADS_DEFAULT}|g' '$f'"
  else
    run "printf '\nParallelDownloads = %s\n' '${PARALLEL_DOWNLOADS_DEFAULT}' >> '$f'"
  fi

  # Color
  grep -Eq '^\s*Color\s*$' "$f" || run "printf '\nColor\n' >> '$f'"

  # ILoveCandy (opcional, mas você usa)
  grep -Eq '^\s*ILoveCandy\s*$' "$f" || run "printf 'ILoveCandy\n' >> '$f'"

  # VerbosePkgLists
  grep -Eq '^\s*VerbosePkgLists\s*$' "$f" || run "printf 'VerbosePkgLists\n' >> '$f'"

  log "pacman.conf ajustado."
}

tune_makepkg_user() {
  local u="$1"
  local h="$2"
  local f="$h/.makepkg.conf"

  if [[ ! -f "$f" ]]; then
    warn "~/.makepkg.conf não existe para $u. Vou criar um arquivo mínimo."
    as_user "$u" "cat > '$f' << 'EOF'
# ~/.makepkg.conf — overrides locais (gerado pelo cachyos-autotune)
# Ajustes validados:
# - paralelismo em builds (ajuste conforme CPU)
# - compressão rápida de pacotes
MAKEFLAGS=\"-j$(nproc)\"
COMPRESSZST=(zstd -c -T0 --fast -)
EOF"
  else
    backup_file "$f"
  fi

  # MAKEFLAGS = -jN (N = threads)
  local n; n="$(nproc)"
  # substitui ou adiciona
  if grep -Eq '^\s*MAKEFLAGS=' "$f"; then
    run "sed -i -E 's|^\s*MAKEFLAGS=.*|MAKEFLAGS=\"-j${n}\"|g' '$f'"
  else
    run "printf '\nMAKEFLAGS=\"-j%s\"\n' '${n}' >> '$f'"
  fi

  # COMPRESSZST
  if grep -Eq '^\s*COMPRESSZST=' "$f"; then
    run "sed -i -E 's|^\s*COMPRESSZST=.*|COMPRESSZST=(zstd -c -T0 --fast -)|g' '$f'"
  else
    run "printf '\nCOMPRESSZST=(zstd -c -T0 --fast -)\n' >> '$f'"
  fi

  log "makepkg tuning aplicado para $u."
}

tune_yay_config_user() {
  local u="$1"
  local h="$2"
  local d="$h/.config/yay"
  local f="$d/config.json"

  as_user "$u" "mkdir -p '$d'"
  if [[ -f "$f" ]]; then
    backup_file "$f"
  fi

  # Configuração funcional mínima conforme suas notas
  as_user "$u" "cat > '$f' << 'EOF'
{
  \"buildDir\": \"/tmp/yay\",
  \"cleanAfter\": true
}
EOF"
  log "Config do yay aplicada para $u (não executa yay como sudo)."
}

rate_mirrors_cachyos() {
  if need_cmd cachyos-rate-mirrors; then
    run "cachyos-rate-mirrors"
  else
    warn "cachyos-rate-mirrors não encontrado. (pulando) — você pode instalar o pacote/usar reflector."
  fi
}

# ------------------------------ Bootloader ------------------------------------
edit_systemd_boot_entries() {
  # Ajusta kernel cmdline nas entradas do systemd-boot
  detect_bootloader_systemd_boot || { warn "systemd-boot não detectado em /boot/loader (pulando)"; return 0; }

  local entries=(/boot/loader/entries/*.conf)
  [[ -e "${entries[0]}" ]] || { warn "Nenhuma entry .conf em /boot/loader/entries (pulando)"; return 0; }

  local has_nvidia=0
  if detect_nvidia_gpu; then has_nvidia=1; fi

  local add_opts=( "zswap.enabled=0" "amd_pstate=active" "amd_pstate.shared_mem=1" "mitigations=auto" "nowatchdog" "quiet" "splash" )
  if [[ $has_nvidia -eq 1 ]]; then
    add_opts+=( "nvidia-drm.modeset=1" "nvidia_drm.fbdev=1" )
  fi

  for f in "${entries[@]}"; do
    [[ -f "$f" ]] || continue
    backup_file "$f"

    # pega linha options atual
    local line
    line="$(grep -E '^options\s+' "$f" || true)"
    [[ -n "$line" ]] || { warn "Sem linha 'options' em $f (pulando)"; continue; }

    local opts="${line#options }"

    # Não alteramos root= e rootflags existentes (apenas garantimos flags adicionais)
    for o in "${add_opts[@]}"; do
      if ! grep -qE "(^| )$(printf '%s' "$o" | sed 's/[.[\*^$(){}?+|/]/\\&/g')($| )" <<< "$opts"; then
        opts="${opts} ${o}"
      fi
    done

    # normaliza múltiplos espaços
    opts="$(echo "$opts" | tr -s ' ')"

    # aplica
    if [[ $DRY_RUN -eq 1 ]]; then
      log "DRY-RUN: atualizaria options em $f"
    else
      # substitui somente a linha options
      perl -0777 -i -pe "s/^options\\s+.*$/options ${opts}/m" "$f"
    fi
    log "systemd-boot entry ajustada: $f"
  done

  if need_cmd bootctl; then
    run "bootctl update"
  else
    warn "bootctl não encontrado (pulando update do systemd-boot)"
  fi
}

# ------------------------------ Initramfs -------------------------------------
tune_mkinitcpio() {
  local f="/etc/mkinitcpio.conf"
  [[ -f "$f" ]] || { warn "mkinitcpio.conf não encontrado (pulando)"; return 0; }

  backup_file "$f"

  local has_nvidia=0
  if detect_nvidia_gpu; then has_nvidia=1; fi

  # Definimos:
  # - MODULES com NVIDIA quando aplicável
  # - HOOKS otimizados para systemd-initramfs + KDE/Wayland
  # - compressão zstd -3
  local modules_line
  if [[ $has_nvidia -eq 1 ]]; then
    modules_line='MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)'
  else
    modules_line='MODULES=()'
  fi

  local hooks_line='HOOKS=( base systemd autodetect microcode kms modconf block sd-vconsole plymouth filesystems)'
  local compression_line='COMPRESSION="zstd"'
  local compression_opts='COMPRESSION_OPTIONS=("-3")'

  # Substitui ou adiciona as chaves
  if grep -Eq '^\s*MODULES=' "$f"; then
    run "sed -i -E 's|^\s*MODULES=.*|${modules_line}|g' '$f'"
  else
    run "printf '\n%s\n' '${modules_line}' >> '$f'"
  fi

  if grep -Eq '^\s*HOOKS=' "$f"; then
    run "sed -i -E 's|^\s*HOOKS=.*|${hooks_line}|g' '$f'"
  else
    run "printf '\n%s\n' '${hooks_line}' >> '$f'"
  fi

  if grep -Eq '^\s*COMPRESSION=' "$f"; then
    run "sed -i -E 's|^\s*COMPRESSION=.*|${compression_line}|g' '$f'"
  else
    run "printf '\n%s\n' '${compression_line}' >> '$f'"
  fi

  if grep -Eq '^\s*COMPRESSION_OPTIONS=' "$f"; then
    run "sed -i -E 's|^\s*COMPRESSION_OPTIONS=.*|${compression_opts}|g' '$f'"
  else
    run "printf '\n%s\n' '${compression_opts}' >> '$f'"
  fi

  if need_cmd mkinitcpio; then
    run "mkinitcpio -P"
  else
    warn "mkinitcpio não encontrado (pulando geração de initramfs)"
  fi
}

# ------------------------------ Btrfs / fstab ---------------------------------
tune_fstab_btrfs() {
  detect_btrfs_root || { warn "Root não é Btrfs (pulando Btrfs tuning)"; return 0; }

  local f="/etc/fstab"
  [[ -f "$f" ]] || { warn "/etc/fstab não encontrado (pulando)"; return 0; }
  backup_file "$f"

  local commit="${BTRFS_COMMIT_DEFAULT}"
  local compress="${BTRFS_COMPRESS_DEFAULT}"

  # Ajuste focado em entradas btrfs do sistema (sem “inventar” targets).
  # - Não mexemos em UUID ou mountpoints.
  # - Apenas garantimos opções consistentes quando a linha já é btrfs.
  # - Discos secundários: se forem btrfs e NÃO forem /, /boot, /home => adiciona nofail+timeout
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: ajustaria opções btrfs em /etc/fstab (commit=${commit}, compress=${compress})"
    return 0
  fi

  perl -i -pe '
    next if /^\s*#/ || /^\s*$/;
    my @f = split(/\s+/);
    next unless @f >= 4;
    my ($spec,$mnt,$fst,$opts) = @f[0,1,2,3];
    next unless $fst eq "btrfs";

    # normaliza opts em lista
    my %o = map { $_ => 1 } split(/,/, $opts);

    # opções base validadas
    $o{"noatime"} = 1;
    $o{"ssd"} = 1;
    $o{"discard=async"} = 1;

    # compress e commit (substitui versões anteriores)
    foreach my $k (keys %o) {
      delete $o{$k} if $k =~ /^compress=/;
      delete $o{$k} if $k =~ /^commit=/;
    }
    $o{"compress='""'${BTRFS_COMPRESS_DEFAULT}'""'"} = 1;
    $o{"commit='""'${BTRFS_COMMIT_DEFAULT}'""'"} = 1;

    # discos que não são críticos: evitar timeout de 90s no boot
    if ($mnt ne "/" && $mnt ne "/boot" && $mnt ne "/home") {
      $o{"nofail"} = 1;
      $o{"x-systemd.device-timeout=5s"} = 1;
    } else {
      # root/home/boot: garantir que não colocou nofail por engano
      delete $o{"nofail"};
      delete $o{"x-systemd.device-timeout=5s"};
    }

    my $newopts = join(",", sort keys %o);
    $f[3] = $newopts;
    $_ = join("\t", @f) . "\n";
  ' "$f"

  log "fstab Btrfs ajustado."
}

# ------------------------------ Sysctl / Journald / THP ------------------------
tune_sysctl() {
  local f="/etc/sysctl.d/99-desktop-memory.conf"
  backup_file "$f"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: criaria/ajustaria $f (swappiness=${VM_SWAPPINESS_DEFAULT}, vfs_cache_pressure=${VFS_CACHE_PRESSURE_DEFAULT})"
    return 0
  fi
  cat > "$f" << EOF
# Ajustes desktop (validados): zram + swapfile, foco em baixa latência
vm.swappiness=${VM_SWAPPINESS_DEFAULT}
vm.vfs_cache_pressure=${VFS_CACHE_PRESSURE_DEFAULT}
EOF
  run "sysctl --system"
}

tune_journald() {
  local f="/etc/systemd/journald.conf"
  [[ -f "$f" ]] || { warn "journald.conf não encontrado (pulando)"; return 0; }
  backup_file "$f"

  # Estado recomendado nas suas notas (limitar uso e manter logs úteis)
  # Ajuste conservador: 256M
  local maxuse="256M"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: ajustaria $f (SystemMaxUse=${maxuse})"
    return 0
  fi

  # descomenta/substitui as chaves
  perl -0777 -i -pe "
    s/^[#;]?\s*SystemMaxUse\s*=.*\$/SystemMaxUse=${maxuse}/m
      or \$_ .= \"\nSystemMaxUse=${maxuse}\";
  " "$f"

  run "systemctl restart systemd-journald.service"
}

tune_thp_tmpfiles() {
  local f="/etc/tmpfiles.d/thp.conf"
  backup_file "$f"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: criaria $f para definir THP=madvice"
    return 0
  fi
  cat > "$f" <<'EOF'
# THP tuning (desktop): reduzir stalls/latência de GUI
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
w /sys/kernel/mm/transparent_hugepage/defrag  - - - - madvise
EOF
  run "systemd-tmpfiles --create '$f'"
}

# ------------------------------ Snapper /home ---------------------------------
setup_snapper_home() {
  # Implementação pragmática e segura:
  # - Não assume create-config disponível
  # - Cria /etc/snapper/configs/home com parâmetros validados
  # - Habilita timers comuns
  if ! need_cmd snapper; then
    warn "snapper não instalado (instalando)."
    pacman_install_needed "${PKGS_SNAP[@]}"
  fi

  local cfg="/etc/snapper/configs/home"
  backup_file "$cfg"

  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: criaria/ajustaria $cfg e habilitaria timers"
    return 0
  fi

  cat > "$cfg" <<'EOF'
# snapper config: /home (gerado pelo cachyos-autotune)
SUBVOLUME="/home"
FSTYPE="btrfs"
QGROUP="1/0"

# TIMELINE / CLEANUP (valores alinhados às suas notas)
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="8"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="3"
TIMELINE_LIMIT_YEARLY="0"

NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="50"
NUMBER_LIMIT_IMPORTANT="10"

EMPTY_PRE_POST_CLEANUP="yes"
EMPTY_PRE_POST_MIN_AGE="1800"
EOF

  # habilitar timers (existem na maioria dos setups snapper)
  systemctl enable --now snapper-timeline.timer 2>/dev/null || true
  systemctl enable --now snapper-cleanup.timer 2>/dev/null || true

  log "Snapper /home configurado."
}

# ------------------------------ NetworkManager bridge --------------------------
setup_nm_bridge_kvm() {
  need_cmd nmcli || { warn "nmcli não encontrado (pulando bridge)"; return 0; }

  local nic
  nic="$(detect_default_nic || true)"
  [[ -n "$nic" ]] || { warn "Não consegui detectar NIC default (pulando bridge)"; return 0; }

  # Cria br0 e adiciona nic como slave, de forma idempotente.
  # Obs: se você já tem br0, o script apenas valida/ajusta.
  if nmcli -t -f NAME con show | grep -qx "br0"; then
    log "Conexão br0 já existe."
  else
    run "nmcli con add type bridge ifname br0 con-name br0 ipv4.method auto ipv6.method auto"
  fi

  local slave_name="br0-${nic}"
  if nmcli -t -f NAME con show | grep -qx "$slave_name"; then
    log "Slave $slave_name já existe."
  else
    run "nmcli con add type ethernet ifname '$nic' con-name '$slave_name' master br0"
  fi

  run "nmcli con up br0"
  run "nmcli con up '$slave_name'"

  log "Bridge br0 (KVM/QEMU) configurada com NIC: $nic"
}

# ------------------------------ NVIDIA cleanup ---------------------------------
nvidia_cleanup_stabilize() {
  detect_nvidia_gpu || { log "GPU NVIDIA não detectada (pulando NVIDIA)"; return 0; }

  # O fluxo segue suas notas: remover pacotes potencialmente conflitantes,
  # garantir nvidia-dkms e regenerar initramfs.
  log "GPU NVIDIA detectada: aplicando limpeza/estabilização de drivers."

  # Remove variantes 'open' caso existam (não falha se não existirem)
  run "pacman -Rns --noconfirm nvidia-open-dkms linux-cachyos-nvidia-open 2>/dev/null || true"
  run "pacman -Rns --noconfirm linux-cachyos-nvidia 2>/dev/null || true"

  # Instala nvidia-dkms e headers do kernel atual
  run "pacman -S --needed --noconfirm nvidia-dkms linux-cachyos-headers || pacman -S --needed --noconfirm nvidia-dkms linux-headers"

  # Garante utilitários e regeneração
  if need_cmd mkinitcpio; then
    run "mkinitcpio -P"
  fi
}

# ------------------------------ OpenRGB ----------------------------------------
setup_openrgb() {
  local u="$1" h="$2"
  pacman_install_needed "${PKGS_OPENRGB[@]}"

  # serviço systemd (root)
  run "systemctl enable --now openrgb.service 2>/dev/null || systemctl enable --now openrgb"

  # i2c-dev
  run "modprobe i2c-dev || true"
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p /etc/modules-load.d
    echo "i2c-dev" > /etc/modules-load.d/i2c-dev.conf
  else
    log "DRY-RUN: escreveria /etc/modules-load.d/i2c-dev.conf"
  fi

  # wrapper X11 (xcb) para GUI sob Wayland
  local wrapper="/usr/local/bin/openrgb-xcb"
  backup_file "$wrapper"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "DRY-RUN: criaria $wrapper"
  else
    cat > "$wrapper" <<'EOF'
#!/usr/bin/env bash
QT_QPA_PLATFORM=xcb /usr/bin/openrgb --gui
EOF
    chmod +x "$wrapper"
  fi

  # autostart do usuário
  as_user "$u" "mkdir -p '$h/.config/autostart'"
  as_user "$u" "cat > '$h/.config/autostart/openrgb.desktop' << 'EOF'
[Desktop Entry]
Type=Application
Exec=/usr/local/bin/openrgb-xcb
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=OpenRGB
Comment=Start OpenRGB GUI in X11 (xcb) mode
EOF"

  log "OpenRGB configurado (daemon + wrapper xcb + autostart)."
}

# ------------------------------ Flatpak + Snap ---------------------------------
setup_flatpak_and_snap() {
  pacman_install_needed "${PKGS_FLATPAK[@]}"

  if need_cmd flatpak; then
    run "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
  fi

  # snapd: em Arch geralmente está nos repos. Se falhar, tentamos via yay.
  if pacman -Si snapd >/dev/null 2>&1; then
    run "pacman -S --needed --noconfirm snapd"
  else
    warn "snapd não está nos repos detectados. Tentando via yay (se instalado)."
    if need_cmd yay; then
      as_user "$TARGET_USER" "yay -S --needed --noconfirm snapd"
    else
      warn "yay não encontrado; não consigo instalar snapd automaticamente (pulando snap)."
      return 0
    fi
  fi

  run "systemctl enable --now snapd.service"
  run "systemctl enable --now snapd.socket"

  # symlink /snap
  if [[ -L /snap || -d /snap ]]; then
    log "/snap já existe (ok)."
  else
    run "ln -s /var/lib/snapd/snap /snap"
  fi

  log "Flatpak e Snap configurados."
}

# ------------------------------ Printer (opcional) -----------------------------
setup_printer_epson_l6270() {
  # DESLIGADO por padrão.
  # Requer:
  #   PRINTER_IP=192.168.x.y
  #   PRINTER_NAME=EpsonL6270
  # Exemplo:
  #   sudo PRINTER_IP=192.168.30.211 PRINTER_NAME=EpsonL6270 bash cachyos-autotune.sh
  local ip="${PRINTER_IP:-}"
  local name="${PRINTER_NAME:-EpsonL6270}"
  [[ -n "$ip" ]] || { warn "PRINTER_IP não definido (pulando impressora)"; return 0; }

  pacman_install_needed "${PKGS_PRINTING[@]}"
  run "systemctl enable --now cups.service"
  run "nc -vz '$ip' 9100 || true"
  run "lpadmin -p '$name' -E -v 'socket://$ip:9100' -m epson-inkjet-printer-escpr2"
  run "lpoptions -d '$name'"
  log "Impressora $name configurada em $ip:9100."
}

# ------------------------------ Swapfile Btrfs (opcional) ----------------------
setup_btrfs_swapfile() {
  # DESLIGADO por padrão devido a riscos/variações.
  # Implementação consciente (template). Use apenas se você souber o que está fazendo.
  detect_btrfs_root || { warn "Root não é Btrfs (pulando swapfile)"; return 0; }

  local swap_dir="/swap"
  local swap_file="${swap_dir}/swapfile"
  local size_gb="${SWAP_SIZE_GB:-8}"

  if swapon --show | grep -q "$swap_file"; then
    log "Swapfile já ativa: $swap_file"
    return 0
  fi

  pacman_install_needed btrfs-progs

  run "mkdir -p '$swap_dir'"
  run "chattr +C '$swap_dir' || true"
  run "btrfs property set '$swap_dir' compression none || true"
  run "fallocate -l ${size_gb}G '$swap_file'"
  run "chmod 600 '$swap_file'"
  run "mkswap '$swap_file'"

  # validação recomendada (filefrag)
  if need_cmd filefrag; then
    run "filefrag -v '$swap_file' | head -n 50"
  else
    warn "filefrag não encontrado para validação de extents (instale e valide manualmente)."
  fi

  # fstab
  backup_file /etc/fstab
  if [[ $DRY_RUN -eq 0 ]]; then
    grep -qF "$swap_file" /etc/fstab || echo "$swap_file none swap defaults 0 0" >> /etc/fstab
  else
    log "DRY-RUN: adicionaria swapfile no /etc/fstab"
  fi

  run "swapon '$swap_file'"
  log "Swapfile Btrfs criada/ativada: $swap_file (${size_gb}G)"
}

# ------------------------------ Auditoria --------------------------------------
audit_report() {
  log "===== AUDIT (relatório rápido) ====="
  if need_cmd systemd-analyze; then
    run "systemd-analyze || true"
  fi
  run "cat /proc/cmdline || true"
  if [[ -r /sys/devices/system/cpu/amd_pstate/status ]]; then
    run "cat /sys/devices/system/cpu/amd_pstate/status || true"
  fi
  if need_cmd powerprofilesctl; then
    run "powerprofilesctl get || true"
  fi
  if [[ -d /proc/pressure ]]; then
    run "ls /proc/pressure || true"
  fi
  run "swapon --show || true"
  log "===== FIM AUDIT ====="
}

# ------------------------------ Main -------------------------------------------
main() {
  ensure_root

  TARGET_USER="$(detect_user)"
  [[ -n "$TARGET_USER" ]] || die "Não consegui detectar usuário alvo."
  TARGET_HOME="$(user_home "$TARGET_USER")"
  [[ -d "$TARGET_HOME" ]] || die "Home do usuário não encontrada: $TARGET_HOME"

  log "Usuário alvo: $TARGET_USER ($TARGET_HOME)"
  log "Dry-run: $DRY_RUN"

  # Base tools
  if [[ $DO_MAINTENANCE -eq 1 ]]; then
    pacman_install_needed "${PKGS_BASE[@]}"
  fi

  if [[ $DO_MIRRORS -eq 1 ]]; then
    rate_mirrors_cachyos
  fi

  if [[ $DO_PACMAN_TUNING -eq 1 ]]; then
    tune_pacman_conf
  fi

  if [[ $DO_MAKEPKG_TUNING -eq 1 ]]; then
    tune_makepkg_user "$TARGET_USER" "$TARGET_HOME"
  fi

  if [[ $DO_YAY_TUNING -eq 1 ]]; then
    if need_cmd yay; then
      tune_yay_config_user "$TARGET_USER" "$TARGET_HOME"
    else
      warn "yay não encontrado (pulando config yay). Se você usa paru, podemos adicionar módulo também."
    fi
  fi

  if [[ $DO_NVIDIA_CLEANUP -eq 1 ]]; then
    nvidia_cleanup_stabilize
  fi

  if [[ $DO_INITRAMFS_TUNING -eq 1 ]]; then
    tune_mkinitcpio
  fi

  if [[ $DO_BOOTLOADER_TUNING -eq 1 ]]; then
    edit_systemd_boot_entries
  fi

  if [[ $DO_BTRFS_TUNING -eq 1 ]]; then
    tune_fstab_btrfs
  fi

  if [[ $DO_SYSCTL_TUNING -eq 1 ]]; then
    tune_sysctl
  fi

  if [[ $DO_JOURNALD_TUNING -eq 1 ]]; then
    tune_journald
  fi

  if [[ $DO_THP_TUNING -eq 1 ]]; then
    tune_thp_tmpfiles
  fi

  if [[ $DO_SNAPPER_HOME -eq 1 ]]; then
    setup_snapper_home
  fi

  if [[ $DO_NM_BRIDGE_KVM -eq 1 ]]; then
    setup_nm_bridge_kvm
  fi

  if [[ $DO_OPENRGB -eq 1 ]]; then
    setup_openrgb "$TARGET_USER" "$TARGET_HOME"
  fi

  if [[ $DO_FLATPAK_SNAP -eq 1 ]]; then
    setup_flatpak_and_snap
  fi

  if [[ $DO_PRINTER_EPSON_L6270 -eq 1 ]]; then
    setup_printer_epson_l6270
  fi

  if [[ $DO_BTRFS_SWAPFILE -eq 1 ]]; then
    setup_btrfs_swapfile
  fi

  audit_report

  if [[ $NO_REBOOT -eq 0 ]]; then
    warn "Alguns ajustes (boot/initramfs/kernel cmdline) podem requerer reboot para efeito completo."
    warn "Recomendação: reinicie quando for conveniente."
  fi

  log "Concluído."
}

main "$@"
