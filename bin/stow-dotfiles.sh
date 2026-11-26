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

DOTFILES_DIR="${ROOT_DIR}/dotfiles"
USER_HOME="${USER_HOME:-$(resolve_user_home)}"

PACKAGES=(
    btop
    dunst
    foot
    gtk-2.0
    gtk-3.0
    gtk-4.0
    hypr
    llama-server
    madsnake
    mpd
    mpv
    nvim
    ohmyposh
    quickshell
    rmpc
    sd-server
    shell-config
    tmux
    xfce4
)

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        return 1
    fi
}

require_directory() {
    local dir_path="$1"
    if [[ ! -d "$dir_path" ]]; then
        log_error "Required directory missing: $dir_path"
        return 1
    fi
}

is_safe_target_path() {
    local target_path="$1"
    local resolved_home
    local resolved_target

    resolved_home="$(realpath -ms "$USER_HOME")"
    resolved_target="$(realpath -ms "$target_path")"

    if [[ "$resolved_target" == "$resolved_home" || "$resolved_target" == "/" ]]; then
        return 1
    fi

    case "$resolved_target" in
        "$resolved_home/.config/"*|"$resolved_home"/.*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

backup_and_prepare_target() {
    local target_path="$1"

    if ! is_safe_target_path "$target_path"; then
        log_error "Unsafe target path for cleanup: $target_path"
        return 1
    fi

    # If it is a symlink pointing directly into DOTFILES_DIR, unlinking is safe and expected
    if [[ -L "$target_path" ]]; then
        local link_dest
        link_dest="$(readlink -f "$target_path" 2>/dev/null || true)"
        if [[ "$link_dest" == "${DOTFILES_DIR}"/* ]]; then
            rm -f "$target_path"
            return 0
        fi
    fi

    # If it exists as a real file, directory, or non-repo symlink, back it up
    if [[ -e "$target_path" || -L "$target_path" ]]; then
        local backup_path="${target_path}.hyprvibe_bak_$(date +%Y%m%d_%H%M%S)"
        log_warn "Existing path detected at ${target_path}. Backing up to ${backup_path}"
        if ! mv "$target_path" "$backup_path"; then
            log_error "Failed to backup ${target_path} to ${backup_path}"
            return 1
        fi
    fi

    return 0
}

preclean_package_targets() {
    local pkg="$1"
    local pkg_dir="${DOTFILES_DIR}/${pkg}"

    if [[ -d "${pkg_dir}/.config" ]]; then
        local cfg_entry
        while IFS= read -r -d '' cfg_entry; do
            backup_and_prepare_target "${USER_HOME}/.config/$(basename "$cfg_entry")" || return 1
        done < <(find "${pkg_dir}/.config" -mindepth 1 -maxdepth 1 -print0)
    fi

    if [[ -d "${pkg_dir}/.local/share" ]]; then
        local share_entry
        while IFS= read -r -d '' share_entry; do
            backup_and_prepare_target "${USER_HOME}/.local/share/$(basename "$share_entry")" || return 1
        done < <(find "${pkg_dir}/.local/share" -mindepth 1 -maxdepth 1 -print0)
    fi

    if [[ -d "${pkg_dir}/.local/bin" ]]; then
        local bin_entry
        while IFS= read -r -d '' bin_entry; do
            backup_and_prepare_target "${USER_HOME}/.local/bin/$(basename "$bin_entry")" || return 1
        done < <(find "${pkg_dir}/.local/bin" -mindepth 1 -maxdepth 1 -print0)
    fi

    local top_entry
    while IFS= read -r -d '' top_entry; do
        local bname="$(basename "$top_entry")"
        if [[ "$bname" == ".config" || "$bname" == ".local" ]]; then
            continue
        fi
        backup_and_prepare_target "${USER_HOME}/${bname}" || return 1
    done < <(find "$pkg_dir" -mindepth 1 -maxdepth 1 -name ".*" -print0)

    return 0
}

main() {
    setup_colors

    require_command stow
    require_directory "$DOTFILES_DIR"

    local pkg
    for pkg in "${PACKAGES[@]}"; do
        require_directory "${DOTFILES_DIR}/${pkg}"
    done

    log_phase "Stow Pre-clean"
    log_info "Preparing target paths with zero-loss backup"
    for pkg in "${PACKAGES[@]}"; do
        preclean_package_targets "$pkg" || return 1
    done

    log_phase "Stow Apply"
    if [[ "${HYPRVIBE_SKIP_LAUNCHER_BUILD:-0}" != "1" && -x "${SCRIPT_DIR}/build-launcher.sh" ]] && command -v cmake >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
        local _l_so="${DOTFILES_DIR}/quickshell/.config/quickshell/Launcher/HyprVibeLauncher/libhyprvibelauncher.so"
        local _l_bin="${USER_HOME}/.local/bin/hyprvibe-dmenu"
        local _l_src="${DOTFILES_DIR}/quickshell/.config/quickshell/Launcher/engine"
        if [[ ! -f "$_l_so" || ! -x "$_l_bin" || "${_l_src}/LauncherModel.cpp" -nt "$_l_so" || "${_l_src}/SystemCore.cpp" -nt "$_l_so" || "${_l_src}/SystemCore.hpp" -nt "$_l_so" || "${_l_src}/PulseEngine.cpp" -nt "$_l_so" || "${_l_src}/PulseEngine.hpp" -nt "$_l_so" || "${_l_src}/DBusEngine.cpp" -nt "$_l_so" || "${_l_src}/DBusEngine.hpp" -nt "$_l_so" || "${_l_src}/CMakeLists.txt" -nt "$_l_so" || "${_l_src}/hyprvibe-dmenu.cpp" -nt "$_l_bin" ]]; then
            USER_HOME="$USER_HOME" "${SCRIPT_DIR}/build-launcher.sh" || log_warn "Launcher C++ build skipped or failed"
        fi
    fi

    log_info "Stowing dotfiles packages into ${USER_HOME} (--no-folding)"
    cd "$DOTFILES_DIR"
    rm -f "${DOTFILES_DIR}/dunst/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf" 2>/dev/null || true
    stow --no-folding -t "$USER_HOME" "${PACKAGES[@]}"

    log_info "Configuring dynamic template and runtime symlinks in ${USER_HOME}"
    mkdir -p "${USER_HOME}/.local/state/hyprvibe/current" "${USER_HOME}/.config/dunst/dunstrc.d"
    ln -sfn "${USER_HOME}/.local/state/hyprvibe/current/dunst.conf" "${USER_HOME}/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf"

    if [[ -f "${ROOT_DIR}/templates/xfce4/thunar.xml.template" ]]; then
        local target_thunar="${USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml"
        mkdir -p "$(dirname "$target_thunar")"
        if [[ -f "$target_thunar" && ! -L "$target_thunar" ]]; then
            backup_and_prepare_target "$target_thunar" || return 1
        fi
        sed "s|_USER_HOME_|${USER_HOME}|g" "${ROOT_DIR}/templates/xfce4/thunar.xml.template" > "$target_thunar"
    fi

    log_success "Dotfiles stow step completed successfully."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi