#!/bin/bash

# State-based screen recorder using wf-recorder
# Toggle script: First run opens menu to start, second run stops recording

RECORDINGS_DIR="$HOME/Pictures/Recordings"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp/hyprvibe-$UID}"
mkdir -p "$STATE_DIR" "$RECORDINGS_DIR"
PIDFILE="$STATE_DIR/wf-recorder.pid"
LOGFILE="$STATE_DIR/wf-recorder.log"

# Check if recording is active (running state)
if [ -f "$PIDFILE" ]; then
    REC_PID=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$REC_PID" ] && kill -0 "$REC_PID" 2>/dev/null; then
        # RUNNING STATE -> CLOSED STATE: Stop recording and wait for clean container flush
        kill -SIGINT "$REC_PID" 2>/dev/null || true
        for _ in {1..50}; do
            kill -0 "$REC_PID" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$REC_PID" 2>/dev/null; then
            kill -SIGTERM "$REC_PID" 2>/dev/null || true
            for _ in {1..20}; do
                kill -0 "$REC_PID" 2>/dev/null || break
                sleep 0.05
            done
        fi
        rm -f "$PIDFILE"
        notify-send "Recording Stopped" "Saved to $RECORDINGS_DIR" -t 3000
        exit 0
    fi
    rm -f "$PIDFILE"
fi

# CLOSED STATE -> RUNNING STATE: Show menu and start recording
if ! command -v wf-recorder >/dev/null 2>&1; then
    notify-send -u critical "Screen Recorder" "wf-recorder is not installed" 2>/dev/null || true
    exit 1
fi

# Recording profiles: 60fps, lossless FLAC audio (low-CPU compression)
profiles=(
    "1080p • Lossless"
    "Native • Lossless"
)

# Show Quickshell C++ menu
selected=$(printf '%s\n' "${profiles[@]}" | hyprvibe-dmenu -dmenu --preset record || true)

# Exit if nothing selected (Escape pressed)
[ -z "$selected" ] && exit 0

case "$selected" in
    "1080p • Lossless")
        SCALE_MODE="1080p"
        ;;
    "Native • Lossless")
        SCALE_MODE="native"
        ;;
    *)
        exit 1
        ;;
esac

# Detect focused monitor output and physical resolution dynamically
FOCUSED_OUTPUT=""
MON_WIDTH=""
MON_HEIGHT=""
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    MON_JSON=$(hyprctl monitors -j 2>/dev/null || true)
    IFS=$'\t' read -r FOCUSED_OUTPUT MON_WIDTH MON_HEIGHT < <(
        printf '%s' "$MON_JSON" | jq -r '
            (([.[] | select(.focused == true)] | .[0]) // .[0] // empty)
            | [(.name // ""), (.width // ""), (.height // "")]
            | @tsv
        ' 2>/dev/null || true
    )
fi

FPS=60
GOP=120
EXT="mkv"
TARGET_W=""
TARGET_H=""
NEEDS_SCALE=false

if [ "$SCALE_MODE" = "1080p" ]; then
    if [[ "$MON_WIDTH" =~ ^[0-9]+$ && "$MON_HEIGHT" =~ ^[0-9]+$ && "$MON_WIDTH" -gt 0 && "$MON_HEIGHT" -gt 0 ]]; then
        if [ "$MON_WIDTH" -ge "$MON_HEIGHT" ] && [ "$MON_HEIGHT" -gt 1080 ]; then
            TARGET_H=1080
            TARGET_W=$(awk -v w="$MON_WIDTH" -v h="$MON_HEIGHT" 'BEGIN { print int((w * 1080 / h) / 2 + 0.5) * 2 }')
            NEEDS_SCALE=true
        elif [ "$MON_HEIGHT" -gt "$MON_WIDTH" ] && [ "$MON_WIDTH" -gt 1080 ]; then
            TARGET_W=1080
            TARGET_H=$(awk -v w="$MON_WIDTH" -v h="$MON_HEIGHT" 'BEGIN { print int((h * 1080 / w) / 2 + 0.5) * 2 }')
            NEEDS_SCALE=true
        else
            TARGET_W="$MON_WIDTH"
            TARGET_H="$MON_HEIGHT"
        fi
        RES_TAG="${TARGET_W}x${TARGET_H}"
    else
        TARGET_W="-2"
        TARGET_H="1080"
        NEEDS_SCALE=true
        RES_TAG="1080p"
    fi
else
    if [[ "$MON_WIDTH" =~ ^[0-9]+$ && "$MON_HEIGHT" =~ ^[0-9]+$ && "$MON_WIDTH" -gt 0 && "$MON_HEIGHT" -gt 0 ]]; then
        RES_TAG="${MON_WIDTH}x${MON_HEIGHT}"
    elif [[ -n "$MON_HEIGHT" ]]; then
        RES_TAG="${MON_HEIGHT}p"
    else
        RES_TAG="native"
    fi
fi

LABEL="${FPS}fps-${RES_TAG}-lossless"
FILENAME="recording-$(date +%Y-%m-%d_%H-%M-%S).$EXT"
OUTPUT="$RECORDINGS_DIR/$FILENAME"

detect_encoder() {
    local dri_dir="${DRI_DIR:-/dev/dri}"
    local -a candidates=()
    local node

    if [[ -n "${RENDER_DEV:-}" && -e "${RENDER_DEV}" ]]; then
        candidates=("${RENDER_DEV}")
    elif [[ -d "$dri_dir" ]]; then
        while IFS= read -r -d '' node; do
            candidates+=("$node")
        done < <(find "$dri_dir" -maxdepth 1 -name "renderD*" -print0 2>/dev/null | sort -z)
    fi

    # Probe actual H.264 VAAPI encoding via ffmpeg (catches decode-only GPUs & hybrid cards)
    if command -v ffmpeg >/dev/null 2>&1; then
        for node in "${candidates[@]}"; do
            if ffmpeg -init_hw_device "vaapi=va:${node}" -f lavfi -i nullsrc=s=256x256:d=0.01 -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null - >/dev/null 2>&1; then
                echo "h264_vaapi nv12 ${node}"
                return 0
            fi
        done

        # Check NVENC (Nvidia)
        if command -v nvidia-smi >/dev/null 2>&1 && ffmpeg -encoders 2>/dev/null | grep -q "h264_nvenc"; then
            echo "h264_nvenc yuv420p"
            return 0
        fi
    fi

    # Software fallback
    echo "libx264 yuv420p"
    return 1
}

# Lossless FLAC audio at low CPU compression level for minimal gaming overhead
DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null || true)
if [ -n "$DEFAULT_SINK" ]; then
    AUDIO_PARAMS=("--audio=${DEFAULT_SINK}.monitor" "-R" "48000" "-C" "flac" "-P" "compression_level=1")
else
    AUDIO_PARAMS=("--audio" "-R" "48000" "-C" "flac" "-P" "compression_level=1")
fi

# Detect encoder and configure optimal DMA-BUF hardware or safe CPU fallback params
read -r VIDEO_CODEC PIX_FMT DETECTED_RENDER_DEV < <(detect_encoder || true)

SCALE_EXPR=""
if [ "$NEEDS_SCALE" = true ] && [ -n "$TARGET_W" ] && [ -n "$TARGET_H" ]; then
    SCALE_EXPR="w=${TARGET_W}:h=${TARGET_H}"
fi

CODEC_PARAMS=("-b" "0" "-p" "g=$GOP")
case "$VIDEO_CODEC" in
    h264_vaapi)
        VAAPI_FILTER="scale_vaapi=${SCALE_EXPR:+${SCALE_EXPR}:}format=nv12:out_range=full"
        CODEC_PARAMS+=("-F" "$VAAPI_FILTER" "-p" "rc_mode=CQP" "-p" "qp=20" "-p" "async_depth=4")
        if [[ -n "${DETECTED_RENDER_DEV:-}" && -e "${DETECTED_RENDER_DEV}" ]]; then
            CODEC_PARAMS+=("-d" "$DETECTED_RENDER_DEV")
        fi
        ;;
    h264_nvenc)
        [ -n "$SCALE_EXPR" ] && CODEC_PARAMS+=("-F" "scale=${SCALE_EXPR}:flags=bilinear")
        CODEC_PARAMS+=("-x" "yuv420p" "-p" "preset=p4" "-p" "rc=vbr" "-p" "cq=20")
        ;;
    libx264)
        notify-send "Screen Record" "Hardware encoder unavailable. Using software encoding (libx264)" -t 3000
        CODEC_PARAMS+=("--no-dmabuf" "-x" "yuv420p" "-p" "preset=veryfast" "-p" "crf=20")
        [ -n "$SCALE_EXPR" ] && CODEC_PARAMS+=("-F" "scale=${SCALE_EXPR}:flags=bilinear")
        ;;
esac

OUTPUT_PARAMS=()
if [[ -n "$FOCUSED_OUTPUT" ]]; then
    OUTPUT_PARAMS=("-o" "$FOCUSED_OUTPUT")
fi

# Start recording in background
nohup wf-recorder \
    --codec="$VIDEO_CODEC" \
    -r "$FPS" \
    "${OUTPUT_PARAMS[@]}" \
    "${AUDIO_PARAMS[@]}" \
    "${CODEC_PARAMS[@]}" \
    -f "$OUTPUT" > "$LOGFILE" 2>&1 &

# Save PID for state management
echo $! > "$PIDFILE"

# Notify user
notify-send "Recording Started" "$LABEL" -t 2000

exit 0
