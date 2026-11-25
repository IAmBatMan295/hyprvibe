#!/usr/bin/env bash

set -eEuo pipefail

MIN_ATTEMPTS=3
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ ! -r "$COMMON_LIB" ]]; then
    echo "Error: Missing common helper library: $COMMON_LIB" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$COMMON_LIB"

USER_HOME="$(resolve_user_home)"
ICONS_DIR="${USER_HOME}/.local/share/icons"
YAMIS_DIR_USER="${YAMIS_DIR_USER:-${ICONS_DIR}/YAMIS}"
YAMIS_DIR_SYSTEM="${YAMIS_DIR_SYSTEM:-/usr/share/icons/YAMIS}"
SDDM_SYS_THEME_DIR="${SDDM_SYS_THEME_DIR:-/usr/share/sddm/themes/hyprvibe}"
SDDM_SYS_HYPRLAND_LUA="${SDDM_SYS_HYPRLAND_LUA:-/usr/share/sddm/hyprland.lua}"
ETC_SDDM_CONF_DIR="${ETC_SDDM_CONF_DIR:-/etc/sddm.conf.d}"
SDDM_LEGACY_CLOCKWORK_DIR="${SDDM_LEGACY_CLOCKWORK_DIR:-/usr/share/sddm/themes/clockwork}"

yamis_installed() {
    [[ -f "${YAMIS_DIR_USER}/index.theme" || -f "${YAMIS_DIR_SYSTEM}/index.theme" ]]
}

current_yamis_location() {
    if [[ -f "${YAMIS_DIR_USER}/index.theme" ]]; then
        printf '%s\n' "${YAMIS_DIR_USER}"
        return 0
    fi

    if [[ -f "${YAMIS_DIR_SYSTEM}/index.theme" ]]; then
        printf '%s\n' "${YAMIS_DIR_SYSTEM}"
        return 0
    fi

    return 1
}

detect_theme_dir() {
    local repo_dir="$1"

    if [[ -f "${repo_dir}/index.theme" ]]; then
        printf '%s\n' "$repo_dir"
        return 0
    fi

    local candidate
    candidate="$(find "$repo_dir" -maxdepth 6 -type f -name index.theme | head -n 1 || true)"
    if [[ -n "$candidate" ]]; then
        dirname "$candidate"
        return 0
    fi

    return 1
}

try_extract_archive_theme_dir() {
    local source_dir="$1"
    local unpack_dir="$2"

    local archive_file
    archive_file="$(find "$source_dir" -maxdepth 3 -type f \( -name '*.tar.gz' -o -name '*.tgz' -o -name '*.tar.xz' -o -name '*.tar.zst' \) | head -n 1 || true)"
    if [[ -z "$archive_file" ]]; then
        return 1
    fi

    mkdir -p "$unpack_dir" || return 1
    if ! tar -xf "$archive_file" -C "$unpack_dir"; then
        return 1
    fi

    detect_theme_dir "$unpack_dir"
}

install_yamis_once() {
    if yamis_installed; then
        local existing_path
        existing_path="$(current_yamis_location || true)"
        if [[ -n "$existing_path" ]]; then
            log_success "YAMIS already installed at ${existing_path}. Skipping clone/install."
        else
            log_success "YAMIS already installed. Skipping clone/install."
        fi
        return 0
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)" || return 1

    local -a repo_urls=()
    if [[ -n "${YAMIS_REPO_URL:-}" ]]; then
        repo_urls+=("${YAMIS_REPO_URL}")
    fi

    repo_urls+=(
        "https://github.com/googIyEYES/YAMIS.git"
        "https://bitbucket.org/dirn-typo/yet-another-monochrome-icon-set.git"
    )

    local url
    local cloned_dir=""
    for url in "${repo_urls[@]}"; do
        log_info "Trying YAMIS source: ${url}"
        if git clone --depth 1 "$url" "${tmp_dir}/src" >/dev/null 2>&1; then
            cloned_dir="${tmp_dir}/src"
            break
        fi
    done

    if [[ -z "$cloned_dir" ]]; then
        log_error "Unable to clone YAMIS from configured sources."
        rm -rf "$tmp_dir"
        return 1
    fi

    local theme_dir
    if ! theme_dir="$(detect_theme_dir "$cloned_dir")"; then
        local extracted_dir="${tmp_dir}/extracted"
        if ! theme_dir="$(try_extract_archive_theme_dir "$cloned_dir" "$extracted_dir")"; then
            log_error "Could not find YAMIS theme files in cloned repository."
            rm -rf "$tmp_dir"
            return 1
        fi
    fi

    log_info "Using YAMIS theme files from: ${theme_dir}"

    mkdir -p "$ICONS_DIR" || {
        rm -rf "$tmp_dir"
        return 1
    }

    rm -rf "$YAMIS_DIR_USER"
    mkdir -p "$YAMIS_DIR_USER" || {
        rm -rf "$tmp_dir"
        return 1
    }

    cp -a "${theme_dir}/." "$YAMIS_DIR_USER" || {
        rm -rf "$tmp_dir"
        return 1
    }

    if [[ ! -f "${YAMIS_DIR_USER}/index.theme" ]]; then
        log_error "YAMIS install verification failed: missing ${YAMIS_DIR_USER}/index.theme"
        rm -rf "$tmp_dir"
        return 1
    fi

    log_success "YAMIS installed to ${YAMIS_DIR_USER}"

    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "$YAMIS_DIR_USER" >/dev/null 2>&1 || true
    fi

    rm -rf "$tmp_dir"
    return 0
}

verify_yamis_install() {
    yamis_installed
}

install_hyprvibe_sddm_once() {
    local source_theme_dir="${ROOT_DIR}/dotfiles/sddm/themes/hyprvibe"
    local sddm_dir="${ROOT_DIR}/dotfiles/sddm"

    if [[ ! -d "$source_theme_dir" ]]; then
        log_error "hyprvibe SDDM theme source missing at ${source_theme_dir}"
        return 1
    fi

    # Ensure repo gitignored assets cache has seed wallpaper
    mkdir -p "${source_theme_dir}/assets" 2>/dev/null || true
    if [[ ! -f "${source_theme_dir}/assets/default-bg.jpg" ]]; then
        shopt -s nullglob
        local repo_seed_bgs=("${ROOT_DIR}/themes/catppuccin/backgrounds"/*.{jpg,jpeg,png,webp})
        shopt -u nullglob
        if (( ${#repo_seed_bgs[@]} > 0 )); then
            cp -f "${repo_seed_bgs[0]}" "${source_theme_dir}/assets/default-bg.jpg" 2>/dev/null || true
        fi
    fi

    # Ensure theme.conf exists with seed defaults if missing
    if [[ ! -f "${source_theme_dir}/theme.conf" ]]; then
        cat > "${source_theme_dir}/theme.conf" <<'EOF'
[General]
background=assets/default-bg.jpg
blurRadius=50
accentColor=#a1a0fa
surfaceColor=#1e1e2e
textColor=#cdd6f4
mutedColor=#9795c4
errorColor=#f38ba8
borderColor=#45475a
fontFamily=JetBrainsMono Nerd Font
fontSize=13
EOF
    fi

    log_info "Installing hyprvibe SDDM theme to ${SDDM_SYS_THEME_DIR}..."
    sudo mkdir -p "$SDDM_SYS_THEME_DIR"
    sudo cp -a "${source_theme_dir}/." "${SDDM_SYS_THEME_DIR}/"

    # Ensure assets directory and seed default wallpaper exist
    sudo mkdir -p "${SDDM_SYS_THEME_DIR}/assets"
    if ! compgen -G "${SDDM_SYS_THEME_DIR}/assets/default-bg.*" >/dev/null 2>&1; then
        local seed_bg=""
        shopt -s nullglob
        local seed_bgs=("${ROOT_DIR}/themes/catppuccin/backgrounds"/*.{jpg,jpeg,png,webp})
        shopt -u nullglob
        if (( ${#seed_bgs[@]} > 0 )); then
            seed_bg="${seed_bgs[0]}"
            sudo cp -f "$seed_bg" "${SDDM_SYS_THEME_DIR}/assets/default-bg.jpg"
        fi
    fi

    # Keep SDDM greeter QML code root-owned (644 files / 755 dirs) so compromised user processes
    # cannot inject password-capturing UI into the root-run greeter; only theme.conf and assets/ stay user-writable
    # for dynamic hyprvibe-theme color and wallpaper sync.
    local target_user="${SUDO_USER:-${USER:-$(id -un)}}"
    local target_group
    target_group="$(id -gn "$target_user" 2>/dev/null || echo "$target_user")"

    sudo chown -R root:root "$SDDM_SYS_THEME_DIR"
    sudo find "$SDDM_SYS_THEME_DIR" -type d -exec chmod 755 {} +
    sudo find "$SDDM_SYS_THEME_DIR" -type f -exec chmod 644 {} +

    sudo mkdir -p "${SDDM_SYS_THEME_DIR}/assets"
    sudo chown -R "${target_user}:${target_group}" "${SDDM_SYS_THEME_DIR}/assets"
    sudo chmod 755 "${SDDM_SYS_THEME_DIR}/assets"
    sudo find "${SDDM_SYS_THEME_DIR}/assets" -type f -exec chmod 644 {} +

    if [[ -f "${SDDM_SYS_THEME_DIR}/theme.conf" ]]; then
        sudo chown "${target_user}:${target_group}" "${SDDM_SYS_THEME_DIR}/theme.conf"
        sudo chmod 644 "${SDDM_SYS_THEME_DIR}/theme.conf"
    fi

    # Generate adaptive hardware scaling for SDDM Wayland greeter compositor directly from template
    if [[ -f "${ROOT_DIR}/bin/lib/hardware-detect.sh" ]]; then
        local tmp_sddm_lua
        tmp_sddm_lua="$(mktemp "${TMPDIR:-/tmp}/hyprvibe-sddm-hypr.XXXXXX")"
        # shellcheck disable=SC1091
        source "${ROOT_DIR}/bin/lib/hardware-detect.sh"
        sync_sddm_compositor_config "${ROOT_DIR}" "$tmp_sddm_lua"
        if [[ -s "$tmp_sddm_lua" ]]; then
            log_info "Installing SDDM Wayland compositor config to ${SDDM_SYS_HYPRLAND_LUA}..."
            sudo mkdir -p "$(dirname -- "$SDDM_SYS_HYPRLAND_LUA")"
            sudo install -m 644 "$tmp_sddm_lua" "$SDDM_SYS_HYPRLAND_LUA"
        fi
        rm -f "$tmp_sddm_lua"
    fi

    # Install SDDM configuration drops
    log_info "Configuring SDDM for Wayland and hyprvibe theme..."
    sudo mkdir -p "$ETC_SDDM_CONF_DIR"

    if [[ -f "${sddm_dir}/10-wayland.conf" ]]; then
        sudo cp -f "${sddm_dir}/10-wayland.conf" "${ETC_SDDM_CONF_DIR}/10-wayland.conf"
        sudo chmod 644 "${ETC_SDDM_CONF_DIR}/10-wayland.conf"
    fi

    if [[ -f "${sddm_dir}/10-theme.conf" ]]; then
        sudo cp -f "${sddm_dir}/10-theme.conf" "${ETC_SDDM_CONF_DIR}/10-theme.conf"
        sudo chmod 644 "${ETC_SDDM_CONF_DIR}/10-theme.conf"
    fi

    # Clean up legacy theme configurations and files
    sudo rm -f "${ETC_SDDM_CONF_DIR}/clockwork.conf" "${ETC_SDDM_CONF_DIR}/theme.conf" 2>/dev/null || true
    sudo rm -rf "$SDDM_LEGACY_CLOCKWORK_DIR" 2>/dev/null || true

    log_success "hyprvibe SDDM theme installed and activated."
    return 0
}

verify_hyprvibe_sddm() {
    [[ -d "$SDDM_SYS_THEME_DIR" && -f "${ETC_SDDM_CONF_DIR}/10-theme.conf" ]] && compgen -G "${SDDM_SYS_THEME_DIR}/assets/default-bg.*" >/dev/null 2>&1
}

main() {
    setup_colors

    run_with_retries "Install YAMIS icon theme" install_yamis_once verify_yamis_install || exit 1
    run_with_retries "Install hyprvibe SDDM theme" install_hyprvibe_sddm_once verify_hyprvibe_sddm || exit 1
    log_phase "Theme Assets Summary"
    log_success "Theme assets installation completed successfully."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi