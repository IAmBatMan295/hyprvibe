#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -r "$COMMON_LIB" ]]; then
    echo "Error: Missing common helper library: $COMMON_LIB" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$COMMON_LIB"

USER_HOME="${USER_HOME:-$(resolve_user_home)}"
MKINITCPIO_CONF="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}"
GRUB_DEFAULT_FILE="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
BOOT_DIR="${BOOT_DIR:-/boot}"
ETC_KERNEL_CMDLINE="${ETC_KERNEL_CMDLINE:-/etc/kernel/cmdline}"
LIMINE_DEFAULT_FILE="${LIMINE_DEFAULT_FILE:-/etc/default/limine}"

mkdir -p "${USER_HOME}/Pictures/Screenshots" "${USER_HOME}/Pictures/Recordings"

MPV_DIR="${USER_HOME}/.config/mpv"
SCRIPTS_DIR="${MPV_DIR}/scripts"
SCRIPT_OPTS_DIR="${MPV_DIR}/script-opts"
TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ensure_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}

download_file() {
    local url="$1"
    local destination="$2"
    local tmp_file="${TMP_DIR}/$(basename "$destination").tmp"

    mkdir -p "$(dirname "$destination")" || return 1

    curl -fL --retry 5 --retry-delay 2 --retry-connrefused --connect-timeout 20 \
        "$url" -o "$tmp_file" || return 1

    mv -f "$tmp_file" "$destination"
}

enable_service_if_present() {
    local mode="$1"
    local service="$2"

    if [[ "$mode" == "system" ]]; then
        if ! systemctl list-unit-files "$service" >/dev/null 2>&1; then
            log_warn "Skipping missing system service: $service"
            return 0
        fi

        sudo systemctl enable "$service" || log_warn "Failed to enable $service (chroot?)"
        return 0
    fi

    if ! systemctl --user list-unit-files "$service" >/dev/null 2>&1; then
        log_warn "Skipping missing user service: $service"
        return 0
    fi

    systemctl --user enable "$service" || log_warn "Failed to enable user service $service (chroot?)"
}

prepare_mpd_environment() {
    local mpd_config_dir="${USER_HOME}/.config/mpd"
    local mpd_config_file="${mpd_config_dir}/mpd.conf"
    local mpd_playlists_dir="${mpd_config_dir}/playlists"
    local mpd_music_dir="${USER_HOME}/Music/music"

    log_info "Preparing MPD directories"
    mkdir -p "$mpd_config_dir" "$mpd_playlists_dir" "$mpd_music_dir"

    if [[ ! -f "$mpd_config_file" ]]; then
        log_warn "MPD config not found at ${mpd_config_file}; ensure dotfiles stow ran before this step."
    fi
}

enable_services() {
    local -a global_services=(
        "NetworkManager.service"
        "sddm.service"
        "preload.service"
        "bluetooth.service"
    )

    local -a user_services=(
        "mpd.service"
        "mpDris2.service"
        "wireplumber.service"
    )

    log_phase "Service Enablement"
    log_info "Enabling global services"
    local service
    for service in "${global_services[@]}"; do
        enable_service_if_present "system" "$service"
    done

    log_info "Disabling Wi-Fi power save"
    sudo mkdir -p /etc/NetworkManager/conf.d
    echo -e "[connection]\nwifi.powersave = 2" | sudo tee /etc/NetworkManager/conf.d/99-disable-wifi-powersave.conf > /dev/null
    sudo systemctl restart NetworkManager || log_warn "Could not restart NetworkManager (expected in chroot)"

    log_info "Configuring UFW rules"
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw allow 53317/tcp
        sudo ufw allow 53317/udp
    else
        log_warn "ufw not found, skipping firewall rules"
    fi

    log_info "Enabling user services"
    prepare_mpd_environment
    for service in "${user_services[@]}"; do
        enable_service_if_present "user" "$service"
    done

    log_success "Service enablement completed"
}

install_uosc_stack() {
    ensure_command curl
    ensure_command unzip

    mkdir -p "$MPV_DIR" "$SCRIPTS_DIR" "$SCRIPT_OPTS_DIR"

    log_phase "uosc + thumbfast"
    log_info "Installing latest uosc"
    download_file "https://github.com/tomasklaen/uosc/releases/latest/download/uosc.zip" "$TMP_DIR/uosc.zip"
    unzip -oq "$TMP_DIR/uosc.zip" -d "$MPV_DIR"

    log_info "Installing latest uosc.conf"
    download_file "https://github.com/tomasklaen/uosc/releases/latest/download/uosc.conf" "$SCRIPT_OPTS_DIR/uosc.conf"

    log_info "Installing thumbfast"
    download_file "https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua" "$SCRIPTS_DIR/thumbfast.lua"
    download_file "https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.conf" "$SCRIPT_OPTS_DIR/thumbfast.conf"

    if [[ ! -f "$SCRIPTS_DIR/uosc/main.lua" ]]; then
        log_error "uosc main.lua was not found after extraction."
        return 1
    fi

    if [[ -n "${OPEN_SUBTITLES_KEY:-}" && "${OPEN_SUBTITLES_KEY}" != "YOUR_API_KEY_HERE" ]]; then
        log_info "Applying OpenSubtitles key"
        sed -i -E "s|open_subtitles_api_key = .*|open_subtitles_api_key = '${OPEN_SUBTITLES_KEY}',|" "$SCRIPTS_DIR/uosc/main.lua"
    fi

    log_success "uosc + thumbfast install complete"
}

detect_gpu_drivers() {
    local gpu_info=""
    if command -v lspci >/dev/null 2>&1; then
        gpu_info="$(lspci -nnk 2>/dev/null | grep -i -EA3 'VGA|3D|Display' || true)"
    fi

    local -A seen=()
    local -a drivers=()
    local mod
    for mod in amdgpu i915 xe; do
        if [[ -n "$gpu_info" ]]; then
            if printf '%s\n' "$gpu_info" | grep -iqE "Kernel driver in use:\s*${mod}\b"; then
                seen["$mod"]=1
                drivers+=("$mod")
            fi
        elif [[ -d "/sys/module/${mod}" ]]; then
            seen["$mod"]=1
            drivers+=("$mod")
        fi
    done

    if (( ${#drivers[@]} > 0 )); then
        printf '%s\n' "${drivers[@]}"
        return 0
    fi
    return 1
}

_elevate_cmd() {
    local target="$1"
    shift
    if [[ -w "$target" || -w "$(dirname "$target")" || "$EUID" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

configure_mkinitcpio_plymouth_and_kms() {
    [[ -f "$MKINITCPIO_CONF" ]] || return 0

    local -a gpu_mods=()
    mapfile -t gpu_mods < <(detect_gpu_drivers || true)

    local mods_csv="${gpu_mods[*]:-}"
    local tmp_mk
    tmp_mk="$(mktemp "${TMP_DIR}/mkinitcpio.conf.XXXXXX")"

    if [[ ! -f "${MKINITCPIO_CONF}.hyprvibe_bak" ]]; then
        _elevate_cmd "$MKINITCPIO_CONF" cp -p "$MKINITCPIO_CONF" "${MKINITCPIO_CONF}.hyprvibe_bak" 2>/dev/null || true
    fi

    python3 - "$MKINITCPIO_CONF" "$tmp_mk" "$mods_csv" << 'EOF'
import re
import sys

src_path, dst_path, mods_str = sys.argv[1:4]
mods_to_add = [m for m in mods_str.split() if m]

with open(src_path, "r", encoding="utf-8") as f:
    text = f.read()

def update_array_line(content: str, key: str, updater) -> str:
    pattern = re.compile(rf'^({re.escape(key)}=\()([^)]*)(\).*)$', re.MULTILINE)
    def _repl(m):
        tokens = m.group(2).split()
        new_tokens = updater(tokens)
        return f"{m.group(1)}{' '.join(new_tokens)}{m.group(3)}"
    return pattern.sub(_repl, content, count=1)

if mods_to_add:
    def add_mods(tokens):
        out = list(tokens)
        for mod in mods_to_add:
            if mod not in out:
                out.append(mod)
        return out
    text = update_array_line(text, "MODULES", add_mods)

def add_plymouth_hook(tokens):
    if "plymouth" in tokens:
        return tokens
    out = list(tokens)
    for anchor in ("udev", "systemd"):
        if anchor in out:
            idx = out.index(anchor) + 1
            out.insert(idx, "plymouth")
            return out
    out.append("plymouth")
    return out

text = update_array_line(text, "HOOKS", add_plymouth_hook)

with open(dst_path, "w", encoding="utf-8") as f:
    f.write(text)
EOF

    _elevate_cmd "$MKINITCPIO_CONF" install -m 644 "$tmp_mk" "$MKINITCPIO_CONF"
}

_inject_quiet_splash_file() {
    local target="$1"
    local kind="$2"
    [[ -f "$target" ]] || return 0

    local tmp_out
    tmp_out="$(mktemp "${TMP_DIR}/bootcfg.XXXXXX")"

    if [[ ! -f "${target}.hyprvibe_bak" ]]; then
        _elevate_cmd "$target" cp -p "$target" "${target}.hyprvibe_bak" 2>/dev/null || true
    fi

    python3 - "$target" "$tmp_out" "$kind" << 'EOF'
import re
import sys

src, dst, kind = sys.argv[1:4]
with open(src, "r", encoding="utf-8") as f:
    text = f.read()

def ensure_tokens(line_val: str) -> str:
    tokens = line_val.split()
    for t in ("quiet", "splash"):
        if t not in tokens:
            tokens.append(t)
    return " ".join(tokens)

if kind == "grub":
    pat = re.compile(r'^(GRUB_CMDLINE_LINUX_DEFAULT=")(.*)(")$', re.MULTILINE)
    if pat.search(text):
        text = pat.sub(lambda m: f'{m.group(1)}{ensure_tokens(m.group(2))}{m.group(3)}', text, count=1)
elif kind == "sdboot_entry":
    pat = re.compile(r'^(\s*options\s+)(.+)$', re.MULTILINE)
    text = pat.sub(lambda m: f'{m.group(1)}{ensure_tokens(m.group(2))}', text)
elif kind == "cmdline":
    text = ensure_tokens(text.strip()) + "\n"
elif kind == "limine_conf":
    pat = re.compile(r'^(\s*(?:KERNEL_CMDLINE(?:\[[^\]]+\])?|CMDLINE):\s*)(.+)$', re.MULTILINE)
    text = pat.sub(lambda m: f'{m.group(1)}{ensure_tokens(m.group(2))}', text)
elif kind == "limine_default":
    pat = re.compile(r'^(KERNEL_CMDLINE(?:\[default\])?=")(.*)(")$', re.MULTILINE)
    if pat.search(text):
        text = pat.sub(lambda m: f'{m.group(1)}{ensure_tokens(m.group(2))}{m.group(3)}', text, count=1)

with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
EOF

    _elevate_cmd "$target" install -m 644 "$tmp_out" "$target"
}

configure_bootloader_kernel_params() {
    local updated=0

    # 1. GRUB
    if [[ -f "$GRUB_DEFAULT_FILE" ]]; then
        log_info "Ensuring quiet splash in ${GRUB_DEFAULT_FILE}"
        _inject_quiet_splash_file "$GRUB_DEFAULT_FILE" "grub"
        updated=1
        if [[ -d "${BOOT_DIR}/grub" ]] && command -v grub-mkconfig >/dev/null 2>&1; then
            _elevate_cmd "${BOOT_DIR}/grub/grub.cfg" grub-mkconfig -o "${BOOT_DIR}/grub/grub.cfg" >/dev/null 2>&1 || true
        fi
    fi

    # 2. systemd-boot
    shopt -s nullglob
    local sd_entries=("${BOOT_DIR}"/loader/entries/*.conf "${BOOT_DIR}"/efi/loader/entries/*.conf)
    shopt -u nullglob
    local entry
    for entry in "${sd_entries[@]}"; do
        log_info "Ensuring quiet splash in systemd-boot entry ${entry}"
        _inject_quiet_splash_file "$entry" "sdboot_entry"
        updated=1
    done
    if [[ -f "$ETC_KERNEL_CMDLINE" ]]; then
        _inject_quiet_splash_file "$ETC_KERNEL_CMDLINE" "cmdline"
        updated=1
    fi

    # 3. Limine
    local limine_cfg
    for limine_cfg in "${BOOT_DIR}/limine/limine.conf" "${BOOT_DIR}/limine.conf"; do
        if [[ -f "$limine_cfg" ]]; then
            log_info "Ensuring quiet splash in Limine config ${limine_cfg}"
            _inject_quiet_splash_file "$limine_cfg" "limine_conf"
            updated=1
        fi
    done
    if [[ -f "$LIMINE_DEFAULT_FILE" ]]; then
        _inject_quiet_splash_file "$LIMINE_DEFAULT_FILE" "limine_default"
        updated=1
    fi

    if (( updated == 0 )); then
        log_warn "No supported bootloader configuration detected under ${BOOT_DIR}; skipping quiet splash injection."
    fi
}

setup_plymouth_glitch() {
    log_phase "Plymouth & Early KMS Setup"

    local plymouth_local_dir="${SCRIPT_DIR}/../plymouth-theme/glitch"

    if [[ -d "$plymouth_local_dir" ]]; then
        log_info "Installing Plymouth 'glitch' theme from repository"
        sudo cp -a "$plymouth_local_dir" "/usr/share/plymouth/themes/"
    else
        log_warn "Plymouth theme 'glitch' not found in $plymouth_local_dir. Assuming already installed or skipping default copy."
    fi

    configure_mkinitcpio_plymouth_and_kms
    configure_bootloader_kernel_params

    log_info "Applying theme and rebuilding initramfs (-R flag)..."
    if command -v plymouth-set-default-theme >/dev/null 2>&1; then
        sudo plymouth-set-default-theme -R glitch || sudo mkinitcpio -P
        log_success "Plymouth early KMS glitch theme applied."
    else
        log_warn "Plymouth CLI missing! Falling back to raw mkinitcpio -P."
        sudo mkinitcpio -P
    fi
}


configure_flatpak_themes() {
    log_phase "Flatpak Themes"

    if ! command -v flatpak >/dev/null 2>&1; then
        log_warn "Flatpak missing. Skip."
        return 0
    fi

    log_info "Override flatpak to dark theme and HyprVibe state dir"
    flatpak override --user --filesystem="${USER_HOME}/.themes"
    flatpak override --user --filesystem="${USER_HOME}/.icons"
    flatpak override --user --filesystem="${USER_HOME}/.local/share/themes"
    flatpak override --user --filesystem="${USER_HOME}/.local/share/icons"
    flatpak override --user --filesystem="${USER_HOME}/.local/state/hyprvibe:ro"
    flatpak override --user --filesystem="${USER_HOME}/.config/gtk-3.0:ro"
    flatpak override --user --filesystem="${USER_HOME}/.config/gtk-4.0:ro"
    flatpak override --user --env=GTK_THEME=adw-gtk3-dark

    log_success "Flatpak dark theme done"
}

ensure_tmux_tpm() {
    log_phase "Tmux Plugin Manager (TPM)"

    local tpm_dir="${USER_HOME}/.tmux/plugins/tpm"
    if [[ -d "$tpm_dir" ]]; then
        log_success "TPM already present at ${tpm_dir}"
        return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        log_warn "git missing; cannot clone TPM."
        return 0
    fi
    mkdir -p "$(dirname "$tpm_dir")"
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
    log_success "TPM installed to ${tpm_dir}"
}

configure_gsettings() {
    log_phase "GSettings Configuration"

    if ! command -v gsettings >/dev/null 2>&1; then
        log_warn "gsettings missing. Skip."
        return 0
    fi

    log_info "Set prefer-dark and foot terminal"
    
    # Dark mode
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    
    # Terminal for various DE schemas (silently fail if schema does not exist)
    gsettings set org.gnome.desktop.default-applications.terminal exec 'foot' 2>/dev/null || true
    gsettings set org.cinnamon.desktop.default-applications.terminal exec 'foot' 2>/dev/null || true
    gsettings set org.mate.applications-terminal exec 'foot' 2>/dev/null || true
    
    log_success "GSettings done"
}

install_madsnake() {
    log_phase "Install madsnake screensaver"

    local madsnake_dir="${USER_HOME}/madsnake"
    if [[ ! -d "$madsnake_dir" ]]; then
        log_info "Cloning madsnake repo to $madsnake_dir"
        if ! git clone https://github.com/IAmBatMan295/madsnake.git "$madsnake_dir"; then
            log_error "Failed to clone madsnake repository"
            return 1
        fi
    else
        log_info "madsnake repo already exists at $madsnake_dir, pulling latest"
        if ! git -C "$madsnake_dir" pull; then
            log_error "Failed to update madsnake repository"
            return 1
        fi
    fi

    log_info "Running madsnake install.sh"
    if ! (cd "$madsnake_dir" && bash install.sh); then
        log_error "madsnake install.sh failed"
        return 1
    fi

    log_success "madsnake install complete"
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Modular miscellaneous system setup tasks. If no options are specified,
all tasks are run (--all).

Options:
  --all          Run all miscellaneous setup tasks (default)
  --uosc         Install MPV uosc and thumbfast stack
  --plymouth     Install Plymouth glitch theme and rebuild initramfs
  --flatpak      Configure Flatpak theme overrides
  --gsettings    Configure dark color-scheme and terminal in gsettings
  --madsnake     Install or update madsnake screensaver
  --services     Enable system and user services, Wi-Fi powersave, firewall
  -h, --help     Show this help message
EOF
}

main() {
    setup_colors

    local run_all=false
    local run_uosc=false
    local run_plymouth=false
    local run_flatpak=false
    local run_gsettings=false
    local run_madsnake=false
    local run_services=false

    if (( $# == 0 )); then
        run_all=true
    fi

    while (( $# > 0 )); do
        case "$1" in
            --all)
                run_all=true
                shift
                ;;
            --uosc)
                run_uosc=true
                shift
                ;;
            --plymouth)
                run_plymouth=true
                shift
                ;;
            --flatpak)
                run_flatpak=true
                shift
                ;;
            --gsettings)
                run_gsettings=true
                shift
                ;;
            --madsnake)
                run_madsnake=true
                shift
                ;;
            --services)
                run_services=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [[ "$run_all" == "true" ]]; then
        run_uosc=true
        run_plymouth=true
        run_flatpak=true
        run_gsettings=true
        run_madsnake=true
        run_services=true
    fi

    if [[ "$run_plymouth" == "true" || "$run_services" == "true" ]]; then
        log_info "Validating sudo credentials for miscellaneous tasks..."
        if ! sudo -v; then
            log_error "Sudo authorization failed."
            exit 1
        fi
    fi

    if [[ "$run_uosc" == "true" ]]; then
        install_uosc_stack
    fi
    if [[ "$run_plymouth" == "true" ]]; then
        setup_plymouth_glitch
    fi
    if [[ "$run_flatpak" == "true" ]]; then
        configure_flatpak_themes
    fi
    if [[ "$run_gsettings" == "true" ]]; then
        configure_gsettings
    fi
    if [[ "$run_all" == "true" ]]; then
        ensure_tmux_tpm
    fi
    if [[ "$run_madsnake" == "true" ]]; then
        install_madsnake
    fi
    if [[ "$run_services" == "true" ]]; then
        enable_services
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
