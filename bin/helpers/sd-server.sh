#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Title: Local Image Generator
# Description: Helper script to generate images and run stable-diffusion.cpp server
# ==============================================================================

HELPER_TITLE="Local Image Generator"
HELPER_ICON="󰋩"
HELPER_ORDER=23

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT_DIR="$(cd -- "$(dirname -- "${REAL_SCRIPT}")/../.." && pwd)"
# shellcheck source=../lib/helper-ui.sh
source "${ROOT_DIR}/bin/lib/helper-ui.sh"

helper_maybe_spawn_window "$0" 0.45 0.48 640 400 "--inner --headless --status --detect-type --dry-run-cmd --list-models --model --start --stop --restart --generate" "$@"

# ------------------------------------------------------------------------------
# State & Configuration Paths (Read-only Stow defaults; mutable edits in XDG_STATE_HOME)
# ------------------------------------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprvibe/sd-server"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sd-server"
DEFAULT_CONFIG_FILE="${CONFIG_DIR}/sd-server.conf"
CONFIG_FILE="${STATE_DIR}/config.conf"
PID_FILE="${STATE_DIR}/sd-server.pid"
LOG_FILE="${STATE_DIR}/server.log"
CURRENT_INFO_FILE="${STATE_DIR}/sd-server.current"

mkdir -p "$STATE_DIR"

MODELS_DIR="${HOME}/models/flux"
OUTPUT_DIR="${HOME}/Pictures/Generated"
DIFFUSION_MODEL="${HOME}/models/flux/flux1-dev-Q3_K_S.gguf"
VAE="${HOME}/models/flux/ae.safetensors"
CLIP_L="${HOME}/models/flux/clip_l.safetensors"
T5XXL="${HOME}/models/flux/t5xxl_q3_k_s.gguf"
STEPS=26
GUIDANCE=3.5
CFG_SCALE=1.0
WIDTH=1024
HEIGHT=1024
SEED=-1
PORT=8090
HOST="127.0.0.1"
VAE_TILING="on"

# Load tracked defaults first, then user overrides from ~/.local/state
if [[ -f "$DEFAULT_CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$DEFAULT_CONFIG_FILE" 2>/dev/null || true
fi
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" 2>/dev/null || true
fi

MODELS_DIR="${MODELS_DIR/#\~/$HOME}"
OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
DIFFUSION_MODEL="${DIFFUSION_MODEL/#\~/$HOME}"
VAE="${VAE/#\~/$HOME}"
CLIP_L="${CLIP_L/#\~/$HOME}"
T5XXL="${T5XXL/#\~/$HOME}"

mkdir -p "$OUTPUT_DIR"

check_vram_hint() {
    local model_path="$1"
    [[ -f "$model_path" ]] || return 0
    local model_mb
    model_mb=$(( $(stat -c%s "$model_path" 2>/dev/null || echo 0) / 1048576 ))
    (( model_mb > 0 )) || return 0

    local avail_vram_mb=0 drm_vram
    for drm_vram in /sys/class/drm/card*/device/mem_info_vram_total; do
        if [[ -r "$drm_vram" ]]; then
            local bytes
            bytes="$(cat "$drm_vram" 2>/dev/null || echo 0)"
            if [[ "$bytes" =~ ^[0-9]+$ ]]; then
                local mb=$(( bytes / 1048576 ))
                (( mb > avail_vram_mb )) && avail_vram_mb="$mb"
            fi
        fi
    done

    if (( avail_vram_mb > 0 && model_mb > avail_vram_mb )); then
        echo -e "  ${CLR_YELLOW}Note: Model (${model_mb} MiB) exceeds dedicated VRAM (${avail_vram_mb} MiB); enable VAE tiling or use GGUF quants.${CLR_RESET}"
    fi
}

save_config() {
    local rel_models="${MODELS_DIR/#$HOME/\${HOME\}}"
    local rel_out="${OUTPUT_DIR/#$HOME/\${HOME\}}"
    local rel_diff="${DIFFUSION_MODEL/#$HOME/\${HOME\}}"
    local rel_vae="${VAE/#$HOME/\${HOME\}}"
    local rel_clipl="${CLIP_L/#$HOME/\${HOME\}}"
    local rel_t5="${T5XXL/#$HOME/\${HOME\}}"

    cat > "$CONFIG_FILE" <<EOF
# Configuration for Local Image Generator Helper
# Managed via HyprVibe dotfiles (GNU Stow)

MODELS_DIR="${rel_models}"
OUTPUT_DIR="${rel_out}"
DIFFUSION_MODEL="${rel_diff}"
VAE="${rel_vae}"
CLIP_L="${rel_clipl}"
T5XXL="${rel_t5}"
STEPS=${STEPS}
GUIDANCE=${GUIDANCE}
CFG_SCALE=${CFG_SCALE}
WIDTH=${WIDTH}
HEIGHT=${HEIGHT}
SEED=${SEED}
PORT=${PORT}
HOST="${HOST}"
VAE_TILING="${VAE_TILING}"
EOF
}

# ------------------------------------------------------------------------------
# Process Status & Control
# ------------------------------------------------------------------------------
get_server_pid() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi

    local proc_pid
    proc_pid=$(pgrep -x sd-server 2>/dev/null | head -n 1 || true)
    if [[ -n "$proc_pid" ]]; then
        echo "$proc_pid"
        return 0
    fi
    return 1
}

is_running() {
    get_server_pid >/dev/null 2>&1
}

# ------------------------------------------------------------------------------
# Model Architecture Detection & Profiles
# ------------------------------------------------------------------------------
detect_model_type() {
    local target="$1"
    local lower
    lower=$(echo "$target" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower" =~ sdxl|xl|juggernaut|realvis|pony|animagine|albedobase ]]; then
        echo "sdxl"
    elif [[ "$lower" =~ 1\.5|v1-5|sd15|dreamshaper|deliberate|epicrealism ]]; then
        echo "sd15"
    elif [[ "$lower" =~ flux ]]; then
        echo "flux"
    elif [[ "$lower" =~ sd3|sd-3 ]]; then
        echo "sd3"
    else
        echo "sdxl"
    fi
}

apply_model_defaults() {
    local target="$1"
    local m_type
    m_type=$(detect_model_type "$target")
    case "$m_type" in
        sdxl)
            WIDTH=1024
            HEIGHT=1024
            STEPS=25
            CFG_SCALE=7.0
            GUIDANCE=0.0
            ;;
        sd15)
            WIDTH=512
            HEIGHT=512
            STEPS=20
            CFG_SCALE=7.0
            GUIDANCE=0.0
            ;;
        flux)
            WIDTH=1024
            HEIGHT=1024
            STEPS=26
            CFG_SCALE=1.0
            GUIDANCE=3.5
            ;;
    esac
}

find_models() {
    local search_dirs=("$MODELS_DIR" "${HOME}/models" "${HOME}/models/sd")
    local found=()
    for sdir in "${search_dirs[@]}"; do
        if [[ -d "$sdir" ]]; then
            while IFS= read -r -d '' f; do
                local bname
                bname=$(basename "$f")
                if [[ "$bname" =~ ^(Qwen|qwen|t5|clip|ae|vae) ]]; then
                    continue
                fi
                found+=("$f")
            done < <(find "$sdir" -maxdepth 2 -type f \( -name "*.safetensors" -o -name "*.gguf" -o -name "*.ckpt" \) -print0 2>/dev/null)
        fi
    done
    (( ${#found[@]} == 0 )) && return 0
    printf '%s\n' "${found[@]}" | sort -u
}

build_cmd_args() {
    local target_model="${1:-$DIFFUSION_MODEL}"
    local m_type
    m_type=$(detect_model_type "$target_model")

    local m_w="$WIDTH"
    local m_h="$HEIGHT"
    local m_steps="$STEPS"
    local m_cfg="$CFG_SCALE"
    local m_guide="$GUIDANCE"

    local cmd=""
    if [[ "$m_type" == "flux" ]]; then
        cmd="sd-cli --diffusion-model \"$target_model\" --vae \"$VAE\" --clip_l \"$CLIP_L\" --t5xxl \"$T5XXL\" -W $m_w -H $m_h --steps $m_steps --guidance $m_guide --cfg-scale $m_cfg -s $SEED --auto-fit on"
    elif [[ "$m_type" == "sdxl" ]]; then
        if [[ -n "${1:-}" && "$1" != "$DIFFUSION_MODEL" ]]; then
            m_w=1024
            m_h=1024
            m_steps=25
            m_cfg=7.0
        fi
        cmd="sd-cli -m \"$target_model\" -W $m_w -H $m_h --steps $m_steps --cfg-scale $m_cfg -s $SEED"
    elif [[ "$m_type" == "sd15" ]]; then
        if [[ -n "${1:-}" && "$1" != "$DIFFUSION_MODEL" ]]; then
            m_w=512
            m_h=512
            m_steps=20
            m_cfg=7.0
        fi
        cmd="sd-cli -m \"$target_model\" -W $m_w -H $m_h --steps $m_steps --cfg-scale $m_cfg -s $SEED"
    else
        cmd="sd-cli -m \"$target_model\" -W $m_w -H $m_h --steps $m_steps --cfg-scale $m_cfg -s $SEED"
    fi

    if [[ "$VAE_TILING" == "on" ]]; then
        cmd="$cmd --vae-tiling"
    fi
    echo "$cmd"
}

start_server() {
    if ! command -v sd-server >/dev/null 2>&1; then
        echo "  ❌ Error: 'sd-server' binary not found in PATH." >&2
        return 1
    fi

    if is_running; then
        echo "  Server already running (PID: $(get_server_pid)). Stop or restart first."
        return 1
    fi

    local target_model="${1:-$DIFFUSION_MODEL}"
    if [[ ! -f "$target_model" ]]; then
        echo "  Error: Model file does not exist: $target_model"
        return 1
    fi

    local m_type
    m_type=$(detect_model_type "$target_model")

    echo "  Starting sd-server..."
    echo "  Model:    $(basename "$target_model") (Profile: ${m_type^^})"
    echo "  Size:     ${WIDTH}x${HEIGHT} | Steps: ${STEPS} | CFG: ${CFG_SCALE}"
    echo "  Listen:   http://${HOST}:${PORT}"
    check_vram_hint "$target_model"

    local extra_args=()
    if [[ "$VAE_TILING" == "on" ]]; then
        extra_args+=("--vae-tiling")
    fi

    local model_flags=()
    if [[ "$m_type" == "flux" ]]; then
        extra_args+=("--auto-fit" "on")
        model_flags=(
            --diffusion-model "$target_model"
            --vae "$VAE"
            --clip_l "$CLIP_L"
            --t5xxl "$T5XXL"
            --guidance "$GUIDANCE"
        )
    else
        model_flags=(-m "$target_model")
    fi

    setsid -f sd-server \
        --listen-ip "$HOST" \
        --listen-port "$PORT" \
        "${model_flags[@]}" \
        -W "$WIDTH" \
        -H "$HEIGHT" \
        --steps "$STEPS" \
        --cfg-scale "$CFG_SCALE" \
        -s "$SEED" \
        "${extra_args[@]}" >> "$LOG_FILE" 2>&1 < /dev/null

    local pid=""
    for _ in {1..20}; do
        pid=$(pgrep -x sd-server 2>/dev/null | head -n 1 || true)
        [[ -n "$pid" ]] && break
        sleep 0.1
    done

    if [[ -z "$pid" ]]; then
        echo "  ❌ Failed to launch sd-server process."
        tail -n 10 "$LOG_FILE"
        return 1
    fi

    echo "$pid" > "$PID_FILE"
    cat > "$CURRENT_INFO_FILE" <<EOF
MODEL="$target_model"
TYPE="$m_type"
WIDTH=$WIDTH
HEIGHT=$HEIGHT
STEPS=$STEPS
PORT=$PORT
HOST=$HOST
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
EOF

    echo "  ✔ Server successfully started (PID: $pid)"
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -a "${HELPER_TITLE}" "${HELPER_TITLE}" "Image server running at http://${HOST}:${PORT}" || true
    return 0
}

stop_server() {
    local pid
    pid=$(get_server_pid || true)
    if [[ -z "$pid" ]]; then
        echo "  Server is not running."
        rm -f "$PID_FILE" "$CURRENT_INFO_FILE"
        return 0
    fi

    echo "  Stopping sd-server (PID: $pid)..."
    kill "$pid" 2>/dev/null || true

    local count=0
    while kill -0 "$pid" 2>/dev/null && (( count < 10 )); do
        sleep 0.5
        ((count++)) || true
    done

    if kill -0 "$pid" 2>/dev/null; then
        echo "  Forcing shutdown (SIGKILL)..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE" "$CURRENT_INFO_FILE"
    echo "  ✔ Server stopped."
    command -v notify-send >/dev/null 2>&1 && \
        notify-send -a "${HELPER_TITLE}" "${HELPER_TITLE}" "Server stopped" || true
}

generate_image() {
    local prompt="$1"
    if ! command -v sd-cli >/dev/null 2>&1; then
        echo "  ❌ Error: 'sd-cli' binary not found in PATH." >&2
        return 1
    fi
    if [[ ! -f "$DIFFUSION_MODEL" ]]; then
        echo "  ❌ Error: Model file does not exist: $DIFFUSION_MODEL" >&2
        return 1
    fi

    local m_type timestamp out_file
    m_type=$(detect_model_type "$DIFFUSION_MODEL")
    timestamp=$(date '+%Y%m%d_%H%M%S')
    out_file="${OUTPUT_DIR}/${m_type}_${timestamp}.png"

    echo ""
    echo "  Generating image with ${m_type^^}..."
    echo "  Model:   $(basename "$DIFFUSION_MODEL")"
    echo "  Prompt:  \"$prompt\""
    echo "  Output:  $out_file"
    echo "  Size:    ${WIDTH}x${HEIGHT} | Steps: ${STEPS} | CFG: ${CFG_SCALE}"
    check_vram_hint "$DIFFUSION_MODEL"
    echo ""

    local extra_args=()
    if [[ "$VAE_TILING" == "on" ]]; then
        extra_args+=("--vae-tiling")
    fi

    local model_flags=()
    if [[ "$m_type" == "flux" ]]; then
        extra_args+=("--auto-fit" "on")
        model_flags=(
            --diffusion-model "$DIFFUSION_MODEL"
            --vae "$VAE"
            --clip_l "$CLIP_L"
            --t5xxl "$T5XXL"
            --guidance "$GUIDANCE"
        )
    else
        model_flags=(-m "$DIFFUSION_MODEL")
    fi

    sd-cli \
        "${model_flags[@]}" \
        -W "$WIDTH" \
        -H "$HEIGHT" \
        --steps "$STEPS" \
        --cfg-scale "$CFG_SCALE" \
        -s "$SEED" \
        -p "$prompt" \
        -o "$out_file" \
        "${extra_args[@]}"

    if [[ -f "$out_file" ]]; then
        echo ""
        echo "  ✔ Image saved to: $out_file"
        command -v notify-send >/dev/null 2>&1 && \
            notify-send -a "${HELPER_TITLE}" -i "$out_file" "Image Generated" "Saved to $out_file" || true
        command -v xdg-open >/dev/null 2>&1 && xdg-open "$out_file" >/dev/null 2>&1 &
    else
        echo "  ❌ Generation failed."
    fi
}

# ------------------------------------------------------------------------------
# CLI Argument Handling
# ------------------------------------------------------------------------------
ACTION=""
PROMPT_ARG=""
TARGET_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --status)
            ACTION="status"
            shift
            ;;
        --list-models)
            ACTION="list-models"
            shift
            ;;
        --model)
            [[ $# -ge 2 && "$2" != --* ]] || { echo "Error: --model requires a path" >&2; exit 1; }
            DIFFUSION_MODEL="${2/#\~/$HOME}"
            shift 2
            ;;
        --detect-type)
            [[ $# -ge 2 && "$2" != --* ]] || { echo "Error: --detect-type requires a model path" >&2; exit 1; }
            ACTION="detect-type"
            TARGET_ARG="$2"
            shift 2
            ;;
        --dry-run-cmd)
            ACTION="dry-run-cmd"
            TARGET_ARG="${2:-}"
            if [[ -n "$TARGET_ARG" && "$TARGET_ARG" != --* ]]; then
                shift 2
            else
                TARGET_ARG=""
                shift 1
            fi
            ;;
        --start)
            ACTION="start"
            shift
            ;;
        --stop)
            ACTION="stop"
            shift
            ;;
        --restart)
            ACTION="restart"
            shift
            ;;
        --generate)
            [[ $# -ge 2 && "$2" != --* ]] || { echo "Error: --generate requires a prompt string" >&2; exit 1; }
            ACTION="generate"
            PROMPT_ARG="$2"
            shift 2
            ;;
        --headless)
            HELPER_HEADLESS=true
            shift
            ;;
        --inner)
            ACTION="inner"
            shift
            break
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -n "$ACTION" && "$ACTION" != "inner" ]]; then
    case "$ACTION" in
        status)
            if is_running; then
                echo "running"
            else
                echo "stopped"
            fi
            exit 0
            ;;
        list-models)
            find_models
            exit 0
            ;;
        detect-type)
            detect_model_type "$TARGET_ARG"
            exit 0
            ;;
        dry-run-cmd)
            build_cmd_args "$TARGET_ARG"
            exit 0
            ;;
        start)
            start_server
            exit $?
            ;;
        stop)
            stop_server
            exit 0
            ;;
        restart)
            stop_server
            start_server
            exit $?
            ;;
        generate)
            if [[ -z "$PROMPT_ARG" ]]; then
                echo "Error: --generate requires a prompt string" >&2
                exit 1
            fi
            generate_image "$PROMPT_ARG"
            exit $?
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# UI Helpers & Menu Loop
# ------------------------------------------------------------------------------
print_header() {
    clear 2>/dev/null || true
    echo ""
    echo -e "  ${CLR_BOLD}${CLR_CYAN}${HELPER_ICON}  ${HELPER_TITLE}${CLR_RESET}"
    echo -e "  ${CLR_GRAY}──────────────────────────────────────────────────${CLR_RESET}"

    if is_running; then
        local pid
        pid=$(get_server_pid || true)
        echo -e "  Server Status: ${CLR_GREEN}${CLR_BOLD}● RUNNING${CLR_RESET} (PID: ${pid})"
        echo -e "  Endpoint:      ${CLR_CYAN}http://${HOST}:${PORT}${CLR_RESET}"
    else
        echo -e "  Server Status: ${CLR_RED}○ STOPPED${CLR_RESET}"
    fi

    echo -e "  Model:         $(basename "$DIFFUSION_MODEL")"
    echo -e "  Resolution:    ${WIDTH}x${HEIGHT} | Steps: ${STEPS} | Guidance: ${GUIDANCE}"
    echo -e "  Output Folder: ${OUTPUT_DIR}"
    echo -e "  ${CLR_GRAY}──────────────────────────────────────────────────${CLR_RESET}"
    echo ""
}

select_model_menu() {
    mapfile -t models < <(find_models)
    if (( ${#models[@]} == 0 )); then
        echo -e "  ${CLR_YELLOW}No diffusion models (.safetensors/.gguf/.ckpt) found.${CLR_RESET}"
        echo "  Place model files into ~/models/flux/ or ~/models/sd/"
        read -rp "  Press Enter to continue..." || true
        return 1
    fi

    echo "  Available Models:"
    for i in "${!models[@]}"; do
        local num=$((i + 1))
        local mpath="${models[$i]}"
        local mname
        mname=$(basename "$mpath")
        local mtype
        mtype=$(detect_model_type "$mpath")
        if [[ "$mpath" == "$DIFFUSION_MODEL" ]]; then
            echo -e "    ${CLR_GREEN}${num}) ${mname} [${mtype^^}] [active]${CLR_RESET}"
        else
            echo "    ${num}) ${mname} [${mtype^^}]"
        fi
    done
    echo "    b) Back"
    echo ""
    read -rp "  Select model [1-${#models[@]}, b]: " choice || return 1

    if [[ "$choice" =~ ^[bB]$ || -z "$choice" ]]; then
        return 1
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#models[@]} )); then
        local idx=$((choice - 1))
        DIFFUSION_MODEL="${models[$idx]}"
        apply_model_defaults "$DIFFUSION_MODEL"
        save_config
        echo "  ✔ Selected $(basename "$DIFFUSION_MODEL") and applied profile defaults."
        return 0
    fi

    echo "  ❌ Invalid selection."
    sleep 1
    return 1
}

settings_menu() {
    while true; do
        print_header
        echo "  Settings:"
        echo "    1) Resolution:       ${WIDTH}x${HEIGHT}"
        echo "    2) Sampling Steps:   ${STEPS}"
        echo "    3) Guidance Scale:   ${GUIDANCE}"
        echo "    4) VAE Tiling:       ${VAE_TILING} (reduces VRAM)"
        echo "    5) Output Directory: ${OUTPUT_DIR}"
        echo "    b) Back"
        echo ""
        read -rp "  Choice [1-5, b]: " s_opt || break
        case "$s_opt" in
            1)
                echo ""
                echo "    1) 1024x1024 (Standard FLUX / SDXL)"
                echo "    2) 1280x768  (Landscape 16:9 approx)"
                echo "    3) 768x1280  (Portrait)"
                echo "    4) 768x768   (Faster)"
                read -rp "  Select [1-4]: " r_opt || break
                case "$r_opt" in
                    1) WIDTH=1024; HEIGHT=1024 ;;
                    2) WIDTH=1280; HEIGHT=768 ;;
                    3) WIDTH=768; HEIGHT=1280 ;;
                    4) WIDTH=768; HEIGHT=768 ;;
                esac
                save_config
                ;;
            2)
                read -rp "  Enter steps [default: 26]: " n_steps || true
                if [[ "$n_steps" =~ ^[1-9][0-9]*$ ]]; then
                    STEPS="$n_steps"
                elif [[ -n "$n_steps" ]]; then
                    echo "  ❌ Invalid step count (must be a positive integer)."
                    sleep 1
                fi
                save_config
                ;;
            3)
                read -rp "  Enter guidance scale [default: 3.5]: " n_guide || true
                if [[ "$n_guide" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
                    GUIDANCE="$n_guide"
                elif [[ -n "$n_guide" ]]; then
                    echo "  ❌ Invalid guidance value (must be numeric)."
                    sleep 1
                fi
                save_config
                ;;
            4)
                if [[ "$VAE_TILING" == "on" ]]; then
                    VAE_TILING="off"
                else
                    VAE_TILING="on"
                fi
                save_config
                ;;
            5)
                read -rp "  Enter output path: " n_out || true
                n_out="${n_out/#\~/$HOME}"
                if [[ -n "$n_out" ]] && mkdir -p "$n_out" 2>/dev/null; then
                    OUTPUT_DIR="$n_out"
                    save_config
                elif [[ -n "$n_out" ]]; then
                    echo "  ❌ Cannot create output directory: $n_out"
                    sleep 1
                fi
                ;;
            b|B|"")
                break
                ;;
        esac
    done
}

while true; do
    print_header
    echo "  Actions:"
    echo "    1) Generate Image (Enter Prompt)"
    if is_running; then
        echo "    2) Stop API / Web Server"
        echo "    3) Restart Server"
        echo "    4) Open Generated Images Folder"
        echo "    5) Configure Settings (Resolution, Steps, Guidance)"
        echo "    6) View Last Server Logs"
    else
        echo "    2) Start API / Web Server (port ${PORT})"
        echo "    3) Select Model & Apply Profile"
        echo "    4) Open Generated Images Folder"
        echo "    5) Configure Settings (Resolution, Steps, Guidance)"
        echo "    6) View Last Server Logs"
    fi
    echo "    q) Quit"
    echo ""
    read -rp "  Choice: " opt || exit 0
    if is_running; then
        case "$opt" in
            1)
                echo ""
                read -rp "  Enter prompt: " user_prompt || true
                if [[ -n "$user_prompt" ]]; then
                    generate_image "$user_prompt" || true
                fi
                read -rp "  Press Enter to continue..." || true
                ;;
            2)
                echo ""
                stop_server
                read -rp "  Press Enter to continue..." || true
                ;;
            3)
                echo ""
                stop_server
                start_server || true
                read -rp "  Press Enter to continue..." || true
                ;;
            4)
                command -v xdg-open >/dev/null 2>&1 && xdg-open "$OUTPUT_DIR" >/dev/null 2>&1 &
                ;;
            5)
                settings_menu
                ;;
            6)
                clear 2>/dev/null || true
                echo -e "  ${CLR_CYAN}Streaming logs from ${LOG_FILE} (Ctrl+C to return)...${CLR_RESET}\n"
                if [[ -f "$LOG_FILE" ]]; then
                    tail -n 60 -f "$LOG_FILE" || true
                else
                    echo "  No log file found."
                    read -rp "  Press Enter to continue..." || true
                fi
                ;;
            q|Q)
                echo "Exiting."
                exit 0
                ;;
            *)
                ;;
        esac
    else
        case "$opt" in
            1)
                echo ""
                read -rp "  Enter prompt: " user_prompt || true
                if [[ -n "$user_prompt" ]]; then
                    generate_image "$user_prompt" || true
                fi
                read -rp "  Press Enter to continue..." || true
                ;;
            2)
                echo ""
                start_server || true
                read -rp "  Press Enter to continue..." || true
                ;;
            3)
                echo ""
                select_model_menu || true
                ;;
            4)
                command -v xdg-open >/dev/null 2>&1 && xdg-open "$OUTPUT_DIR" >/dev/null 2>&1 &
                ;;
            5)
                settings_menu
                ;;
            6)
                clear 2>/dev/null || true
                echo -e "  ${CLR_CYAN}Last logs from ${LOG_FILE} (Ctrl+C to return)...${CLR_RESET}\n"
                if [[ -f "$LOG_FILE" ]]; then
                    tail -n 60 "$LOG_FILE"
                else
                    echo "  No log file found."
                fi
                echo ""
                read -rp "  Press Enter to continue..." || true
                ;;
            q|Q)
                echo "Exiting."
                exit 0
                ;;
            *)
                ;;
        esac
    fi
done
