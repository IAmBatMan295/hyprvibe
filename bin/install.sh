#!/usr/bin/env bash

set -eEuo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_SOURCE}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

if [[ -r "$COMMON_LIB" ]]; then
    # shellcheck disable=SC1090
    source "$COMMON_LIB"
else
    resolve_user_home() {
        if [[ -n "${USER_HOME:-}" ]]; then
            printf '%s\n' "${USER_HOME}"
            return 0
        fi

        local resolved_home
        resolved_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"

        if [[ -n "$resolved_home" ]]; then
            printf '%s\n' "$resolved_home"
        else
            printf '%s\n' "${HOME}"
        fi
    }

    log_step() {
        local current="$1"
        local total="$2"
        local label="$3"
        printf '\n%b[%s/%s]%b %b%s%b\n' "${COLOR_CYAN:-}" "$current" "$total" "${COLOR_RESET:-}" "${COLOR_BOLD:-}" "$label" "${COLOR_RESET:-}"
    }

    print_tui_box() {
        local title="$1"
        shift
        local width=66
        local border
        printf -v border '%*s' "$width" ''
        border="${border// /─}"

        printf '\n%b┌%s┐%b\n' "${COLOR_BLUE:-}" "$border" "${COLOR_RESET:-}"
        printf '%b│%b %-*.*s %b│%b\n' "${COLOR_BLUE:-}" "${COLOR_BOLD:-}${COLOR_CYAN:-}" $((width - 2)) $((width - 2)) "$title" "${COLOR_BLUE:-}" "${COLOR_RESET:-}"
        if (( $# > 0 )); then
            printf '%b├%s┤%b\n' "${COLOR_BLUE:-}" "$border" "${COLOR_RESET:-}"
            local line
            for line in "$@"; do
                printf '%b│%b %-*.*s %b│%b\n' "${COLOR_BLUE:-}" "${COLOR_RESET:-}" $((width - 2)) $((width - 2)) "$line" "${COLOR_BLUE:-}" "${COLOR_RESET:-}"
            done
        fi
        printf '%b└%s┘%b\n' "${COLOR_BLUE:-}" "$border" "${COLOR_RESET:-}"
    }

    COLOR_RESET=""
    COLOR_BOLD=""
    COLOR_BLUE=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_CYAN=""

    setup_colors() {
        if [[ -z "${NO_COLOR:-}" ]]; then
            COLOR_RESET=$'\033[0m'
            COLOR_BOLD=$'\033[1m'
            COLOR_BLUE=$'\033[34m'
            COLOR_GREEN=$'\033[32m'
            COLOR_YELLOW=$'\033[33m'
            COLOR_RED=$'\033[31m'
            COLOR_CYAN=$'\033[36m'
        fi
    }

    ensure_terminal_environment() {
        if ! infocmp "${TERM:-}" >/dev/null 2>&1; then
            export TERM="xterm-256color"
        fi
    }

    log_phase() {
        printf "\n%s%s==> %s%s\n" "$COLOR_BOLD" "$COLOR_BLUE" "$1" "$COLOR_RESET"
    }

    log_info() {
        printf "%s[INFO]%s %s\n" "$COLOR_CYAN" "$COLOR_RESET" "$1"
    }

    log_success() {
        printf "%s[OK]%s %s\n" "$COLOR_GREEN" "$COLOR_RESET" "$1"
    }

    log_warn() {
        printf "%s[WARN]%s %s\n" "$COLOR_YELLOW" "$COLOR_RESET" "$1"
    }

    log_error() {
        printf "%s[ERROR]%s %s\n" "$COLOR_RED" "$COLOR_RESET" "$1" >&2
    }

    read_from_tty() {
        local prompt="$1"
        local out_var="$2"
        local input=""

        if [[ -r /dev/tty ]]; then
            if ! read -r -p "$prompt" input </dev/tty; then
                return 1
            fi
        else
            if ! read -r -p "$prompt" input; then
                return 1
            fi
        fi

        printf -v "$out_var" '%s' "$input"
        return 0
    }
fi

HYPRVIBE_REPO_URL="${HYPRVIBE_REPO_URL:-https://github.com/IAmBatMan295/HyprVibe.git}"
USER_HOME="$(resolve_user_home)"
HYPRVIBE_TARGET_DIR="${USER_HOME}/hyprvibe"
MODULES_DIR="$SCRIPT_DIR"
INSTALL_LOG_FILE="${USER_HOME}/hyprvibe-log.txt"
SUDO_KEEPALIVE_PID=""
CLONE_TMP_DIR=""

on_error() {
    local line_no="$1"
    local exit_code="$2"
    log_error "install.sh failed at line ${line_no} with exit code ${exit_code}."
}

trap 'on_error "$LINENO" "$?"' ERR

setup_run_logging() {
    if [[ "${HYPRVIBE_LOGGING_ACTIVE:-0}" == "1" ]]; then
        return 0
    fi

    if ! : >"$INSTALL_LOG_FILE"; then
        log_error "Failed to create log file at ${INSTALL_LOG_FILE}."
        exit 1
    fi

    export HYPRVIBE_LOGGING_ACTIVE=1
    export HYPRVIBE_INSTALL_LOG_FILE="$INSTALL_LOG_FILE"

    if command -v stdbuf >/dev/null 2>&1; then
        exec > >(stdbuf -o0 -e0 tee "$INSTALL_LOG_FILE") 2>&1
    else
        exec > >(tee "$INSTALL_LOG_FILE") 2>&1
    fi

    log_info "Logging installer output to ${INSTALL_LOG_FILE}"
}

require_interactive_tty() {
    if [[ -r /dev/tty ]]; then
        return 0
    fi

    log_error "Interactive terminal input is required for this installer."
    log_warn "Run the script from a normal terminal session."
    return 1
}

cleanup_clone_temp() {
    if [[ -n "$CLONE_TMP_DIR" && -d "$CLONE_TMP_DIR" ]]; then
        rm -rf "$CLONE_TMP_DIR"
    fi
}

ensure_cachyos() {
    local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ ! -f "$os_release_file" ]]; then
        log_error "${os_release_file} not found. hyprvibe requires CachyOS."
        exit 1
    fi

    local os_id=""
    local os_id_like=""
    local os_pretty_name=""

    os_id="$(grep -E '^ID=' "$os_release_file" | cut -d= -f2 | tr -d '"' || true)"
    os_id_like="$(grep -E '^ID_LIKE=' "$os_release_file" | cut -d= -f2 | tr -d '"' || true)"
    os_pretty_name="$(grep -E '^PRETTY_NAME=' "$os_release_file" | cut -d= -f2 | tr -d '"' || true)"

    if [[ "$os_id" != "cachyos" && "$os_id_like" != *"cachyos"* ]]; then
        log_error "Unsupported distribution: ${os_pretty_name:-Linux}."
        log_error "hyprvibe is strictly built and configured for CachyOS."
        exit 1
    fi
}

detect_invoked_repo_root() {
    local src="$SCRIPT_SOURCE"
    if [[ -z "$src" || "$src" == "bash" || "$src" == "-bash" || "$src" == "sh" || "$src" == "/dev/fd/"* || ! -e "$src" ]]; then
        return 1
    fi

    local src_dir
    src_dir="$(cd -- "$(dirname -- "$src")" 2>/dev/null && pwd -P)" || return 1

    if command -v git >/dev/null 2>&1; then
        local git_top=""
        if git_top="$(git -C "$src_dir" rev-parse --show-toplevel 2>/dev/null)"; then
            realpath -m "$git_top"
            return 0
        fi
    fi

    local candidate
    candidate="$(realpath -m "${src_dir}/..")"
    if [[ -d "${candidate}/dotfiles" && -d "${candidate}/themes" && -f "${candidate}/bin/install.sh" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    return 1
}

enforce_repo_location() {
    local resolved_target
    resolved_target="$(realpath -m "$HYPRVIBE_TARGET_DIR")"

    local invoked_root=""
    if invoked_root="$(detect_invoked_repo_root)"; then
        if [[ "$invoked_root" != "$resolved_target" ]]; then
            log_error "hyprvibe must be installed from ${resolved_target} (currently running from ${invoked_root})."
            log_info "Move your repository to ${resolved_target} and re-run:"
            printf '  mv "%s" "%s" && bash "%s/bin/install.sh"\n' "$invoked_root" "$resolved_target" "$resolved_target" >&2
            return 1
        fi
    fi

    return 0
}

validate_target_dir() {
    local resolved_home
    local resolved_target

    resolved_home="$(realpath -m "$USER_HOME")"
    resolved_target="$(realpath -m "$HYPRVIBE_TARGET_DIR")"

    if [[ -z "$resolved_home" || "$resolved_home" == "/" ]]; then
        log_error "Could not determine a safe user home directory."
        exit 1
    fi

    if [[ "$resolved_target" != "${resolved_home}/hyprvibe" ]]; then
        log_error "Installer target is fixed to ${resolved_home}/hyprvibe"
        exit 1
    fi
}

refresh_hyprvibe_clone() {
    validate_target_dir

    if ! command -v git >/dev/null 2>&1; then
        log_error "git is required for bootstrap."
        exit 1
    fi

    if [[ -d "$HYPRVIBE_TARGET_DIR" ]]; then
        if git -C "$HYPRVIBE_TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            log_phase "Repository Check"
            log_info "Existing hyprvibe repository detected at ${HYPRVIBE_TARGET_DIR}."
            log_info "Pulling latest updates..."
            if git -C "$HYPRVIBE_TARGET_DIR" pull --rebase; then
                log_success "Repository updated successfully."
            else
                log_warn "Could not pull updates (offline or local modifications). Continuing with existing local copy."
            fi
            MODULES_DIR="${HYPRVIBE_TARGET_DIR}/bin"
            if [[ -r "${HYPRVIBE_TARGET_DIR}/bin/lib/common.sh" ]]; then
                # shellcheck disable=SC1090
                source "${HYPRVIBE_TARGET_DIR}/bin/lib/common.sh"
            fi
            return 0
        else
            log_warn "Target directory ${HYPRVIBE_TARGET_DIR} exists but is not a git repository."
            local backup_dir
            backup_dir="${HYPRVIBE_TARGET_DIR}.hyprvibe_bak_$(date +%s)"
            log_info "Backing up existing directory to ${backup_dir}"
            mv "$HYPRVIBE_TARGET_DIR" "$backup_dir"
        fi
    fi

    CLONE_TMP_DIR="$(mktemp -d)" || {
        log_error "Failed to create temporary directory for clone."
        exit 1
    }

    trap 'cleanup_clone_temp; exit 1' INT TERM

    local cloned_repo_dir="${CLONE_TMP_DIR}/hyprvibe"

    log_phase "Bootstrap Repository"
    log_info "Cloning fresh hyprvibe copy from ${HYPRVIBE_REPO_URL}"
    if ! git clone "$HYPRVIBE_REPO_URL" "$cloned_repo_dir"; then
        cleanup_clone_temp
        log_error "Failed to clone ${HYPRVIBE_REPO_URL}"
        exit 1
    fi

    if [[ ! -f "${cloned_repo_dir}/bin/install.sh" ]]; then
        cleanup_clone_temp
        log_error "Cloned repository does not contain bin/install.sh"
        exit 1
    fi

    mkdir -p "$(dirname -- "$HYPRVIBE_TARGET_DIR")"
    mv "$cloned_repo_dir" "$HYPRVIBE_TARGET_DIR"
    cleanup_clone_temp
    trap - INT TERM

    MODULES_DIR="${HYPRVIBE_TARGET_DIR}/bin"

    if [[ ! -f "${MODULES_DIR}/install.sh" ]]; then
        log_error "Missing installer in cloned repo at ${MODULES_DIR}/install.sh"
        exit 1
    fi

    if [[ -r "${HYPRVIBE_TARGET_DIR}/bin/lib/common.sh" ]]; then
        # shellcheck disable=SC1090
        source "${HYPRVIBE_TARGET_DIR}/bin/lib/common.sh"
    fi

    log_success "Using modules from ${MODULES_DIR}"
}

start_sudo_keepalive() {
    log_phase "Sudo Session"
    log_info "Requesting sudo once for this full install run"
    if ! sudo -v; then
        log_error "Failed to validate sudo credentials."
        return 1
    fi

    (
        local sleep_pid=""
        trap '[[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true; exit 0' INT TERM
        while true; do
            sleep 50 &
            sleep_pid=$!
            wait "$sleep_pid" 2>/dev/null || true
            sleep_pid=""

            if ! kill -0 "$$" 2>/dev/null; then
                exit 0
            fi

            if ! sudo -n true </dev/null >/dev/null 2>&1; then
                log_error "Sudo session expired during install. Stopping installer."
                kill -TERM "$$" >/dev/null 2>&1 || true
                exit 1
            fi
        done
    ) </dev/null >/dev/null 2>&1 &

    SUDO_KEEPALIVE_PID="$!"
}

stop_sudo_keepalive() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    sudo -k >/dev/null 2>&1 || true
}

run_module() {
    local module_script="$1"
    local module_path="${MODULES_DIR}/${module_script}"

    if [[ ! -f "$module_path" ]]; then
        log_error "Required module not found: $module_path"
        return 1
    fi

    log_phase "Running module: ${module_script}"

    if ! bash "$module_path"; then
        log_error "Module failed: ${module_script}"
        return 1
    fi

    log_success "Module completed: ${module_script}"
}

manage_optional_plugins() {
    local plugins_dir="${HYPRVIBE_TARGET_DIR}/plugins"
    if [[ ! -d "$plugins_dir" ]]; then
        return 0
    fi

    if [[ "${HYPRVIBE_AUTO_YES:-false}" == "true" ]]; then
        log_info "Skipping optional plugins prompt under --yes."
        return 0
    fi

    log_phase "Optional Hardware Plugins"
    echo "Available plugins:"
    echo "  1) Lenovo Battery Conservation Mode (60% charge cap for laptops)"
    echo ""

    local answer=""
    if ! read_from_tty "Would you like to install optional hardware plugins? [y/N]: " answer; then
        log_info "Skipping optional plugins by default."
        return 0
    fi

    case "${answer,,}" in
        y|yes)
            local choice=""
            read_from_tty "Select plugins to install (comma-separated, e.g. 1) or 'all': " choice || return 0
            if [[ "$choice" == "1" || "${choice,,}" == "all" ]]; then
                if [[ -f "${plugins_dir}/battery-conservation/install.sh" ]]; then
                    bash "${plugins_dir}/battery-conservation/install.sh" || log_warn "Plugin battery-conservation reported a warning."
                fi
            fi
            ;;
        *)
            log_info "Skipping plugins installation."
            ;;
    esac
}

HYPRVIBE_AUTO_YES="false"
STEP_COMPLETED=()
STEP_WARNINGS=()
STEP_SKIPPED=()

print_installer_banner() {
    print_tui_box "hyprvibe OS Installer - CachyOS + Hyprland" \
        "Target Repo : ${HYPRVIBE_TARGET_DIR}" \
        "Install Log : ${INSTALL_LOG_FILE}"
}

detect_summary_field_chassis() {
    local bat
    shopt -s nullglob
    local supplies=(/sys/class/power_supply/BAT* /sys/class/power_supply/CMB*)
    shopt -u nullglob
    for bat in "${supplies[@]}"; do
        [[ -d "$bat" ]] && { printf 'Laptop (battery detected)'; return 0; }
    done
    printf 'Desktop / AC-only'
}

detect_summary_field_bootloader() {
    if [[ -f /etc/default/limine || -f /boot/limine.conf || -f /boot/limine/limine.conf ]] || command -v limine-update >/dev/null 2>&1; then
        printf 'Limine'
    elif [[ -d /boot/loader/entries ]] || command -v bootctl >/dev/null 2>&1; then
        printf 'systemd-boot'
    elif [[ -f /etc/default/grub ]]; then
        printf 'GRUB'
    else
        printf 'Unknown'
    fi
}

print_preflight_summary() {
    local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    local os_name="CachyOS"
    if [[ -r "$os_release_file" ]]; then
        os_name="$(grep -E '^PRETTY_NAME=' "$os_release_file" | cut -d= -f2 | tr -d '"' || echo "CachyOS")"
    fi

    local cpu_vendor="unknown"
    if command -v lscpu >/dev/null 2>&1; then
        cpu_vendor="$(lscpu 2>/dev/null | awk -F: '/Vendor ID/{gsub(/^[ \t]+/,"",$2); print $2; exit}' || echo "unknown")"
    fi

    local gpu_line="auto-detected"
    if command -v lspci >/dev/null 2>&1; then
        gpu_line="$(lspci 2>/dev/null | awk -F': ' '/VGA|3D|Display/{print $2}' | paste -sd ', ' - || echo "auto-detected")"
        [[ -z "$gpu_line" ]] && gpu_line="auto-detected"
    fi

    local chassis_str
    chassis_str="$(detect_summary_field_chassis)"
    local bootloader_str
    bootloader_str="$(detect_summary_field_bootloader)"
    local run_mode="Interactive"
    [[ "$HYPRVIBE_AUTO_YES" == "true" ]] && run_mode="Non-interactive (--yes)"

    print_tui_box "Pre-Flight System Summary" \
        "OS         : ${os_name}" \
        "CPU Vendor : ${cpu_vendor}" \
        "GPU(s)     : ${gpu_line}" \
        "Chassis    : ${chassis_str}" \
        "Bootloader : ${bootloader_str}" \
        "User Home  : ${USER_HOME}" \
        "Mode       : ${run_mode}"
}

confirm_installation_preflight() {
    if [[ "$HYPRVIBE_AUTO_YES" == "true" ]]; then
        log_info "Auto-confirm enabled (--yes). Starting installation..."
        return 0
    fi

    local answer=""
    if ! read_from_tty "Proceed with hyprvibe installation? [Y/n]: " answer; then
        log_error "Interactive input unavailable for confirmation."
        return 1
    fi

    case "${answer,,}" in
        ""|y|yes)
            return 0
            ;;
        *)
            log_info "Installation cancelled by user before changes were applied."
            return 1
            ;;
    esac
}

print_install_summary() {
    local elapsed="${1:-0}"
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    local duration
    printf -v duration '%02dm %02ds' "$mins" "$secs"

    local lines=(
        "Duration  : ${duration}"
        "Completed : ${#STEP_COMPLETED[@]} step(s)"
        "Warnings  : ${#STEP_WARNINGS[@]}"
        "Skipped   : ${#STEP_SKIPPED[@]}"
        "Log File  : ${INSTALL_LOG_FILE}"
        "Verify    : ${HYPRVIBE_TARGET_DIR}/bin/hyprvibe-doctor"
    )

    local item
    for item in ${STEP_WARNINGS[@]+"${STEP_WARNINGS[@]}"}; do
        lines+=("  [WARN] ${item}")
    done
    for item in ${STEP_SKIPPED[@]+"${STEP_SKIPPED[@]}"}; do
        lines+=("  [SKIP] ${item}")
    done

    print_tui_box "hyprvibe Installation Summary" "${lines[@]}"
}

prompt_reboot_if_requested() {
    if [[ "$HYPRVIBE_AUTO_YES" == "true" ]]; then
        log_info "Skipping automatic reboot under --yes. Reboot manually before logging into hyprvibe."
        return 0
    fi

    local answer=""
    if ! read_from_tty "Reboot now to enter SDDM / Hyprland cleanly? [y/N]: " answer; then
        return 0
    fi

    case "${answer,,}" in
        y|yes)
            log_info "Rebooting system..."
            sudo systemctl reboot
            ;;
        *)
            log_info "Remember to reboot before starting your first hyprvibe session."
            ;;
    esac
}

print_usage() {
    cat <<'EOF'
Usage: install.sh [OPTIONS]

Options:
  -y, --yes    Skip pre-flight confirmation and reboot prompts
  -h, --help   Show this help message and exit
EOF
}

main() {
    local pos_args=()
    while (( $# > 0 )); do
        case "$1" in
            -y|--yes)
                HYPRVIBE_AUTO_YES="true"
                ;;
            -h|--help)
                print_usage
                return 0
                ;;
            *)
                pos_args+=("$1")
                ;;
        esac
        shift
    done
    export HYPRVIBE_AUTO_YES

    setup_colors
    ensure_terminal_environment

    if [[ "${EUID}" -eq 0 ]]; then
        log_error "Please run this script as a normal user with sudo privileges, not as root."
        exit 1
    fi

    enforce_repo_location || exit 1
    ensure_cachyos
    setup_run_logging
    print_installer_banner

    refresh_hyprvibe_clone ${pos_args[@]+"${pos_args[@]}"}
    print_preflight_summary

    require_interactive_tty || exit 1
    confirm_installation_preflight || exit 0

    trap stop_sudo_keepalive EXIT
    start_sudo_keepalive || exit 1

    SECONDS=0
    local total_steps=7

    log_step 1 "$total_steps" "GitHub SSH Setup"
    run_module "github-auth.sh" || exit 1
    STEP_COMPLETED+=("github-auth.sh")

    log_step 2 "$total_steps" "System & AUR Package Installation"
    run_module "install-packages.sh" || exit 1
    STEP_COMPLETED+=("install-packages.sh")

    log_step 3 "$total_steps" "Themes, Icons & Hardened SDDM Setup"
    run_module "theme-assets-installer.sh" || exit 1
    STEP_COMPLETED+=("theme-assets-installer.sh")

    log_step 4 "$total_steps" "Hardware Display & Scaling Detection"
    log_phase "Hardware Display & Scaling Detection"
    if [[ -f "${HYPRVIBE_TARGET_DIR}/bin/lib/hardware-detect.sh" ]]; then
        # shellcheck disable=SC1091
        source "${HYPRVIBE_TARGET_DIR}/bin/lib/hardware-detect.sh"
        ensure_monitors_config "${HYPRVIBE_TARGET_DIR}"
        log_success "Monitor and display scaling configuration verified."
        STEP_COMPLETED+=("hardware-detect.sh")
    else
        log_warn "hardware-detect.sh missing; skipped monitor auto-detection."
        STEP_SKIPPED+=("hardware-detect.sh")
    fi

    log_step 5 "$total_steps" "Stow Dotfiles"
    run_module "stow-dotfiles.sh" || exit 1
    STEP_COMPLETED+=("stow-dotfiles.sh")

    log_step 6 "$total_steps" "Default Theme & System Hardening"
    log_phase "Theme Engine Initialization"
    if [[ -x "${HYPRVIBE_TARGET_DIR}/bin/hyprvibe-theme" ]]; then
        if "${HYPRVIBE_TARGET_DIR}/bin/hyprvibe-theme" set monochrome; then
            STEP_COMPLETED+=("hyprvibe-theme set monochrome")
        else
            log_warn "Failed to set default monochrome theme."
            STEP_WARNINGS+=("hyprvibe-theme set monochrome")
        fi
    else
        STEP_SKIPPED+=("hyprvibe-theme set monochrome")
    fi

    run_module "miscellaneous.sh" || exit 1
    STEP_COMPLETED+=("miscellaneous.sh")

    log_step 7 "$total_steps" "Optional Hardware Plugins"
    manage_optional_plugins
    STEP_COMPLETED+=("optional-plugins")

    print_install_summary "$SECONDS"
    prompt_reboot_if_requested
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi