#!/usr/bin/env bash

set -euE -o pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -r "$COMMON_LIB" ]]; then
    echo "Error: Missing common helper library: $COMMON_LIB" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$COMMON_LIB"

PACKAGES_DIR="${ROOT_DIR}/packages"
PACMAN_LIST=""
YAY_LIST=""
PACKAGE_PROFILE=""
MIN_ATTEMPTS=3
PACMAN_SYSUPGRADE_DONE=0

YAY_INSTALL_FLAGS=(
    --needed
    --sudoloop
    --useask
    --answerclean None
    --answerdiff None
    --answeredit None
    --answerupgrade None
    --noremovemake
)

run_with_tty_stdin() {
    if { : </dev/tty; } 2>/dev/null; then
        "$@" </dev/tty
    else
        "$@"
    fi
}

detect_package_profile() {
    PACKAGE_PROFILE="cachy"
}

set_package_files() {
    PACMAN_LIST="${PACKAGES_DIR}/pacman.txt"
    YAY_LIST="${PACKAGES_DIR}/yay.txt"
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

require_file() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        log_error "Missing file: $file_path"
        exit 1
    fi
}

load_packages() {
    local file_path="$1"
    local -n out_array="$2"
    out_array=()

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line
        line="${raw_line%%#*}"
        line="$(trim "$line")"
        if [[ -n "$line" ]]; then
            out_array+=("$line")
        fi
    done < "$file_path"
}

CPUINFO_FILE="${CPUINFO_FILE:-/proc/cpuinfo}"
SYSFS_POWER_SUPPLY_DIR="${SYSFS_POWER_SUPPLY_DIR:-/sys/class/power_supply}"
SYSFS_BACKLIGHT_DIR="${SYSFS_BACKLIGHT_DIR:-/sys/class/backlight}"
BOOT_DIR="${BOOT_DIR:-/boot}"

detect_cpu_vendor() {
    local vendor
    vendor="$(grep -m1 "vendor_id" "$CPUINFO_FILE" 2>/dev/null | cut -d: -f2 | tr -d '[:space:]' || true)"

    if [[ "$vendor" == "GenuineIntel" ]]; then
        printf '%s\n' "intel"
        return 0
    elif [[ "$vendor" == "AuthenticAMD" ]]; then
        printf '%s\n' "amd"
        return 0
    fi

    printf '%s\n' "unknown"
    return 1
}

detect_gpu_vendors_list() {
    local lspci_out="" vendors=()
    if command -v lspci >/dev/null 2>&1; then
        lspci_out="$(lspci -nn 2>/dev/null | grep -iE 'VGA|3D|Display' || true)"
    fi

    if [[ -n "$lspci_out" ]]; then
        [[ "$lspci_out" == *"[1002:"* ]] && vendors+=("amd")
        [[ "$lspci_out" == *"[8086:"* ]] && vendors+=("intel")
        [[ "$lspci_out" == *"[10de:"* ]] && vendors+=("nvidia")
    else
        [[ -d /sys/module/amdgpu ]] && vendors+=("amd")
        [[ -d /sys/module/i915 || -d /sys/module/xe ]] && vendors+=("intel")
        [[ -d /sys/module/nvidia || -d /sys/module/nouveau ]] && vendors+=("nvidia")
    fi

    printf '%s\n' "${vendors[@]}"
}

is_laptop_chassis() {
    local entry
    if [[ -d "$SYSFS_POWER_SUPPLY_DIR" ]]; then
        shopt -s nullglob
        for entry in "${SYSFS_POWER_SUPPLY_DIR}"/BAT* "${SYSFS_POWER_SUPPLY_DIR}"/CMB*; do
            if [[ -d "$entry" ]]; then
                shopt -u nullglob
                return 0
            fi
        done
        shopt -u nullglob
    fi
    if [[ -d "$SYSFS_BACKLIGHT_DIR" ]] && [[ -n "$(ls -A "$SYSFS_BACKLIGHT_DIR" 2>/dev/null || true)" ]]; then
        return 0
    fi
    return 1
}

detect_bootloader_kind() {
    if [[ -d "${BOOT_DIR}/grub" ]]; then
        echo "grub"
    elif [[ -d "${BOOT_DIR}/loader/entries" || -d "${BOOT_DIR}/efi/loader/entries" ]]; then
        echo "systemd-boot"
    elif [[ -d "${BOOT_DIR}/limine" || -f "${BOOT_DIR}/limine.conf" || -f "${BOOT_DIR}/limine/limine.conf" ]]; then
        echo "limine"
    else
        echo "unknown"
    fi
}

filter_packages_for_hardware() {
    local cpu_vendor
    cpu_vendor="$(detect_cpu_vendor || true)"

    local -a gpu_vendors=()
    mapfile -t gpu_vendors < <(detect_gpu_vendors_list)
    local has_amd=0 has_intel=0 has_nvidia=0 gv
    for gv in "${gpu_vendors[@]}"; do
        case "$gv" in
            amd) has_amd=1 ;;
            intel) has_intel=1 ;;
            nvidia) has_nvidia=1 ;;
        esac
    done

    local is_laptop=0
    is_laptop_chassis && is_laptop=1

    local bootloader
    bootloader="$(detect_bootloader_kind)"

    log_phase "Hardware Package Filtering"
    log_info "CPU=${cpu_vendor} | GPUs=${gpu_vendors[*]:-unknown} | Chassis=$([[ $is_laptop -eq 1 ]] && echo laptop || echo desktop) | Boot=${bootloader}"

    local -A drop_pkg=()
    # Avoid conflicting notification/polkit/plymouth agents
    drop_pkg["mako"]=1
    drop_pkg["polkit-kde-agent"]=1
    drop_pkg["cachyos-plymouth-theme"]=1

    # Drop unneeded grub packages on systemd-boot or limine hosts
    if [[ "$bootloader" == "systemd-boot" || "$bootloader" == "limine" ]]; then
        drop_pkg["grub"]=1
        drop_pkg["grub-hook"]=1
        drop_pkg["cachyos-grub-theme"]=1
    fi

    # Drop laptop-only utilities on desktops
    if (( is_laptop == 0 )); then
        drop_pkg["brightnessctl"]=1
        drop_pkg["iio-sensor-proxy"]=1
    fi

    # GPU driver adaptation when GPUs were positively identified
    if (( ${#gpu_vendors[@]} > 0 )); then
        if (( has_amd == 0 )); then
            drop_pkg["vulkan-radeon"]=1
            drop_pkg["lib32-vulkan-radeon"]=1
            drop_pkg["xf86-video-amdgpu"]=1
            drop_pkg["xf86-video-ati"]=1
        fi
        if (( has_intel == 0 )); then
            drop_pkg["vulkan-intel"]=1
            drop_pkg["intel-media-driver"]=1
            drop_pkg["intel-gmmlib"]=1
            drop_pkg["libva-intel-driver"]=1
        fi
        if (( has_nvidia == 0 )); then
            drop_pkg["xf86-video-nouveau"]=1
            drop_pkg["vulkan-nouveau"]=1
            drop_pkg["nvidia-utils"]=1
            drop_pkg["lib32-nvidia-utils"]=1
        else
            drop_pkg["xf86-video-nouveau"]=1
            drop_pkg["vulkan-nouveau"]=1
        fi
    fi

    # CPU microcode & Ryzen-only kernel modules
    if [[ "$cpu_vendor" == "intel" ]]; then
        drop_pkg["amd-ucode"]=1
        local -a filtered_yay=()
        local ypkg
        for ypkg in "${YAY_PKGS[@]}"; do
            [[ "$ypkg" == "ryzen_smu-dkms-git" ]] && continue
            filtered_yay+=("$ypkg")
        done
        YAY_PKGS=("${filtered_yay[@]}")
    elif [[ "$cpu_vendor" == "amd" ]]; then
        drop_pkg["intel-ucode"]=1
    fi

    local -a core_required=(inotify-tools iw zenity python-dbus python-gobject edid-decode)
    local -a filtered_pacman=()
    local -A seen_pac=()
    local pkg

    for pkg in "${PACMAN_PKGS[@]}"; do
        if [[ "$cpu_vendor" == "intel" && "$pkg" == "amd-ucode" ]]; then
            pkg="intel-ucode"
        elif [[ "$cpu_vendor" == "amd" && "$pkg" == "intel-ucode" ]]; then
            pkg="amd-ucode"
        fi
        [[ -n "${drop_pkg[$pkg]:-}" ]] && continue
        [[ -n "${seen_pac[$pkg]:-}" ]] && continue
        seen_pac["$pkg"]=1
        filtered_pacman+=("$pkg")
    done

    for pkg in "${core_required[@]}"; do
        if [[ -z "${seen_pac[$pkg]:-}" ]]; then
            seen_pac["$pkg"]=1
            filtered_pacman+=("$pkg")
        fi
    done

    if (( has_nvidia == 1 )); then
        for pkg in nvidia-utils egl-wayland; do
            if [[ -z "${seen_pac[$pkg]:-}" ]]; then
                seen_pac["$pkg"]=1
                filtered_pacman+=("$pkg")
            fi
        done
    fi

    PACMAN_PKGS=("${filtered_pacman[@]}")
}

declare -A INSTALLED_PKG_MAP=()
INSTALLED_CACHE_VALID=0

refresh_installed_pkg_cache() {
    INSTALLED_PKG_MAP=()

    local installed_pkg=""
    while IFS= read -r installed_pkg; do
        if [[ -n "$installed_pkg" ]]; then
            INSTALLED_PKG_MAP["$installed_pkg"]=1
        fi
    done < <(pacman -Qq)

    INSTALLED_CACHE_VALID=1
}

invalidate_installed_pkg_cache() {
    INSTALLED_CACHE_VALID=0
}

ensure_installed_pkg_cache() {
    if (( INSTALLED_CACHE_VALID == 0 )); then
        refresh_installed_pkg_cache
    fi
}

missing_packages() {
    local -n all_pkgs="$1"
    local -n missing_out="$2"
    missing_out=()

    ensure_installed_pkg_cache

    local pkg
    for pkg in "${all_pkgs[@]}"; do
        if [[ -z "${INSTALLED_PKG_MAP[$pkg]+x}" ]]; then
            missing_out+=("$pkg")
        fi
    done
}

missing_packages_with_providers() {
    local -n all_pkgs="$1"
    local -n missing_out="$2"
    missing_out=()

    ensure_installed_pkg_cache

    local candidates=()
    local pkg
    for pkg in "${all_pkgs[@]}"; do
        if [[ -z "${INSTALLED_PKG_MAP[$pkg]+x}" ]]; then
            candidates+=("$pkg")
        fi
    done

    if (( ${#candidates[@]} == 0 )); then
        return 0
    fi

    local unresolved=()
    mapfile -t unresolved < <(pacman -T "${candidates[@]}" 2>/dev/null || true)

    for pkg in "${unresolved[@]}"; do
        if [[ -n "$pkg" ]]; then
            missing_out+=("$pkg")
        fi
    done
}

should_run_mirror_ranking() {
    local answer

    while true; do
        if ! read_from_tty "Run mirror ranking now? [Y/n]: " answer; then
            log_warn "Interactive input unavailable; proceeding with mirror ranking."
            return 0
        fi

        case "${answer,,}" in
            y|yes|"")
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                log_warn "Please answer yes or no."
                ;;
        esac
    done
}

should_run_post_pacman_recheck() {
    local answer

    while true; do
        if ! read_from_tty "Run post-pacman missing-package recheck pass? [Y/n]: " answer; then
            log_warn "Interactive input unavailable; running post-pacman recheck."
            return 0
        fi

        case "${answer,,}" in
            y|yes|"")
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                log_warn "Please answer yes or no."
                ;;
        esac
    done
}

should_run_slow_fallback() {
    local manager_name="$1"
    local answer

    while true; do
        if ! read_from_tty "Bulk ${manager_name} install failed. Run slower package-by-package fallback? [y/N]: " answer; then
            log_warn "Interactive input unavailable; skipping package-by-package fallback."
            return 1
        fi

        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            n|no|"")
                return 1
                ;;
            *)
                log_warn "Please answer yes or no."
                ;;
        esac
    done
}

bootstrap_yay_once() {
    if command -v yay >/dev/null 2>&1; then
        return 0
    fi

    log_info "yay not found. Installing from AUR git repository"
    run_with_tty_stdin sudo pacman -S --needed base-devel git || return 1

    local tmp_dir
    tmp_dir="$(mktemp -d)" || return 1

    if ! git clone https://aur.archlinux.org/yay.git "$tmp_dir/yay"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    pushd "$tmp_dir/yay" >/dev/null || {
        rm -rf "$tmp_dir"
        return 1
    }

    if ! run_with_tty_stdin makepkg -si; then
        popd >/dev/null
        rm -rf "$tmp_dir"
        return 1
    fi

    popd >/dev/null
    rm -rf "$tmp_dir"

    command -v yay >/dev/null 2>&1
}

bootstrap_yay_verify() {
    command -v yay >/dev/null 2>&1
}

setup_reflector_once() {
    if ! command -v cachyos-rate-mirrors >/dev/null 2>&1; then
        log_info "cachyos-rate-mirrors not found. Installing it first"
        run_with_tty_stdin sudo pacman -S --needed cachyos-rate-mirrors || return 1
    fi

    log_info "Running cachyos-rate-mirrors for CachyOS mirrorlists"
    sudo cachyos-rate-mirrors
    log_success "cachyos-rate-mirrors completed"
    return 0
}

verify_reflector_setup() {
    command -v cachyos-rate-mirrors >/dev/null 2>&1
}

PACMAN_PKGS=()
YAY_PKGS=()

sync_and_upgrade_system_once() {
    if (( PACMAN_SYSUPGRADE_DONE == 1 )); then
        return 0
    fi

    log_phase "System Sync"
    log_info "Syncing package databases and upgrading system packages first"
    log_info "This prevents dependency breakage during large package installs"
    run_with_tty_stdin sudo pacman -Syu || return 1
    invalidate_installed_pkg_cache

    PACMAN_SYSUPGRADE_DONE=1
    return 0
}

install_pacman_with_fallback() {
    local -a targets=("$@")
    local -a failed=()
    local pkg

    if (( ${#targets[@]} == 0 )); then
        return 0
    fi

    if run_with_tty_stdin sudo pacman -S --needed --ask=4 "${targets[@]}"; then
        invalidate_installed_pkg_cache
        return 0
    fi

    invalidate_installed_pkg_cache

    if ! should_run_slow_fallback "pacman"; then
        log_warn "Skipping package-by-package pacman fallback"
        return 1
    fi

    log_warn "Bulk pacman transaction failed; retrying package-by-package"

    for pkg in "${targets[@]}"; do
        if pacman -Q "$pkg" >/dev/null 2>&1; then
            continue
        fi

        log_info "Installing pacman package: ${pkg}"
        if ! run_with_tty_stdin sudo pacman -S --needed --ask=4 "$pkg"; then
            failed+=("$pkg")
        fi
    done

    if (( ${#failed[@]} > 0 )); then
        invalidate_installed_pkg_cache
        log_error "Pacman packages still failing: ${failed[*]}"
        return 1
    fi

    invalidate_installed_pkg_cache

    return 0
}

install_yay_with_fallback() {
    local -a targets=("$@")
    local -a failed=()
    local pkg
    local unresolved

    if (( ${#targets[@]} == 0 )); then
        return 0
    fi

    if run_with_tty_stdin yay -S "${YAY_INSTALL_FLAGS[@]}" "${targets[@]}"; then
        invalidate_installed_pkg_cache
        return 0
    fi

    invalidate_installed_pkg_cache

    if ! should_run_slow_fallback "yay"; then
        log_warn "Skipping package-by-package yay fallback"
        return 1
    fi

    log_warn "Bulk yay transaction failed; retrying package-by-package"

    for pkg in "${targets[@]}"; do
        unresolved="$(pacman -T "$pkg" 2>/dev/null || true)"
        if [[ -z "$unresolved" ]]; then
            continue
        fi

        log_info "Installing yay package: ${pkg}"
        if ! run_with_tty_stdin yay -S "${YAY_INSTALL_FLAGS[@]}" "$pkg"; then
            failed+=("$pkg")
        fi
    done

    if (( ${#failed[@]} > 0 )); then
        invalidate_installed_pkg_cache
        log_error "Yay packages still failing: ${failed[*]}"
        return 1
    fi

    invalidate_installed_pkg_cache

    return 0
}

install_pacman_once() {
    if (( ${#PACMAN_PKGS[@]} == 0 )); then
        return 0
    fi

    local missing=()
    missing_packages PACMAN_PKGS missing

    if (( ${#missing[@]} == 0 )); then
        log_success "All pacman packages are already installed; skipping pacman install"
        return 0
    fi

    sync_and_upgrade_system_once || return 1

    log_info "Installing ${#missing[@]} missing pacman package(s)"
    install_pacman_with_fallback "${missing[@]}"
}

verify_pacman_install() {
    local missing=()
    missing_packages PACMAN_PKGS missing

    if (( ${#missing[@]} > 0 )); then
        log_error "Missing pacman packages: ${missing[*]}"
        return 1
    fi

    return 0
}

install_yay_packages_once() {
    if (( ${#YAY_PKGS[@]} == 0 )); then
        return 0
    fi

    local missing=()
    missing_packages_with_providers YAY_PKGS missing

    if (( ${#missing[@]} == 0 )); then
        log_success "All yay packages are already installed; skipping yay install"
        return 0
    fi

    log_info "Installing ${#missing[@]} missing yay package(s)"
    install_yay_with_fallback "${missing[@]}"
}

verify_yay_install() {
    local missing=()
    missing_packages_with_providers YAY_PKGS missing

    if (( ${#missing[@]} > 0 )); then
        log_error "Missing yay packages: ${missing[*]}"
        return 1
    fi

    return 0
}

main() {
    setup_colors

    if [[ "${EUID}" -eq 0 ]]; then
        log_error "Please run this script as a normal user with sudo privileges, not as root."
        exit 1
    fi

    detect_package_profile || exit 1
    set_package_files || exit 1
    log_phase "Package Profile"
    log_info "Using package profile: ${PACKAGE_PROFILE}"

    require_file "$PACMAN_LIST"
    require_file "$YAY_LIST"
    load_packages "$PACMAN_LIST" PACMAN_PKGS
    load_packages "$YAY_LIST" YAY_PKGS
    filter_packages_for_hardware

    if should_run_mirror_ranking; then
        run_with_retries "Setup reflector mirrors" setup_reflector_once verify_reflector_setup || exit 1
    else
        log_warn "Skipping mirror ranking by user choice"
    fi

    run_with_retries "Install pacman packages" install_pacman_once verify_pacman_install || exit 1

    if should_run_post_pacman_recheck; then
        run_with_retries "Post-pacman missing package pass" install_pacman_once verify_pacman_install || exit 1
    else
        log_warn "Skipping post-pacman missing-package recheck by user choice"
    fi

    run_with_retries "Install yay helper" bootstrap_yay_once bootstrap_yay_verify || exit 1
    run_with_retries "Install yay packages" install_yay_packages_once verify_yay_install || exit 1

    log_phase "Package Installer Summary"
    log_success "All package installation steps completed successfully."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi