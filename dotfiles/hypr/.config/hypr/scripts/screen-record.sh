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

# Recording profiles (optimized for Vega 8 + HDD)
# Video: h264_vaapi hardware encoding, 1080p
# Audio: 256kbps AAC, Lossless FLAC, or No Audio
profiles=(
    "30fps • 256kbps"
    "30fps • Lossless"
    "30fps • No Audio"
    "60fps • 256kbps"
    "60fps • Lossless"
    "60fps • No Audio"
)

# Show Quickshell C++ menu
selected=$(printf '%s\n' "${profiles[@]}" | hyprvibe-dmenu -dmenu --preset compact -i -p "Screen Record" -l 6 --width 280 || true)

# Exit if nothing selected (Escape pressed)
[ -z "$selected" ] && exit 0

# Detect focused monitor output and height dynamically
FOCUSED_OUTPUT=""
MON_HEIGHT=""
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    MON_JSON=$(hyprctl monitors -j 2>/dev/null || true)
    IFS=$'\t' read -r FOCUSED_OUTPUT MON_HEIGHT < <(
        printf '%s' "$MON_JSON" | jq -r '
            (([.[] | select(.focused == true)] | .[0]) // .[0] // empty)
            | [(.name // ""), (.height // "")]
            | @tsv
        ' 2>/dev/null || true
    )
fi
RES_TAG="${MON_HEIGHT:+${MON_HEIGHT}p}"
RES_TAG="${RES_TAG:-display}"

# Parse selection
case "$selected" in
    "30fps • 256kbps")
        FPS=30
        AUDIO_CODEC="aac"
        AUDIO_BITRATE="256k"
        NO_AUDIO=false
        EXT="mp4"
        MODE_TAG="256kbps"
        ;;
    "30fps • Lossless")
        FPS=30
        AUDIO_CODEC="flac"
        AUDIO_BITRATE=""
        NO_AUDIO=false
        EXT="mkv"
        MODE_TAG="lossless"
        ;;
    "30fps • No Audio")
        FPS=30
        NO_AUDIO=true
        EXT="mp4"
        MODE_TAG="no-audio"
        ;;
    "60fps • 256kbps")
        FPS=60
        AUDIO_CODEC="aac"
        AUDIO_BITRATE="256k"
        NO_AUDIO=false
        EXT="mp4"
        MODE_TAG="256kbps"
        ;;
    "60fps • Lossless")
        FPS=60
        AUDIO_CODEC="flac"
        AUDIO_BITRATE=""
        NO_AUDIO=false
        EXT="mkv"
        MODE_TAG="lossless"
        ;;
    "60fps • No Audio")
        FPS=60
        NO_AUDIO=true
        EXT="mp4"
        MODE_TAG="no-audio"
        ;;
    *)
        exit 1
        ;;
esac

LABEL="${FPS}fps-${RES_TAG}-${MODE_TAG}"

# Generate filename with timestamp
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

if [ "$FPS" -eq 30 ]; then
    BITRATE="8M"
    GOP="60"
else
    BITRATE="15M"
    GOP="120"
fi

# Build audio parameters and command
AUDIO_PARAMS=()
if [ "$NO_AUDIO" != true ]; then
    DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null || true)
    if [ -n "$DEFAULT_SINK" ]; then
        AUDIO_SOURCE="${DEFAULT_SINK}.monitor"
        AUDIO_PARAMS=("--audio=$AUDIO_SOURCE" "-R" "48000" "-C" "$AUDIO_CODEC")
    else
        AUDIO_PARAMS=("--audio" "-R" "48000" "-C" "$AUDIO_CODEC")
    fi
    if [ -n "$AUDIO_BITRATE" ]; then
        AUDIO_PARAMS+=("-P" "b=$AUDIO_BITRATE")
    fi
fi

# Detect encoder and configure params
read -r VIDEO_CODEC PIX_FMT DETECTED_RENDER_DEV < <(detect_encoder || true)

if [[ "$VIDEO_CODEC" == "libx264" ]]; then
    notify-send "Screen Record" "Hardware encoder unavailable. Using software encoding (libx264)" -t 3000
fi

CODEC_PARAMS=("-p" "pix_fmt=$PIX_FMT" "-p" "b=$BITRATE" "-p" "g=$GOP")
if [[ "$VIDEO_CODEC" == "h264_vaapi" && -n "${DETECTED_RENDER_DEV:-}" && -e "${DETECTED_RENDER_DEV}" ]]; then
    CODEC_PARAMS+=("-d" "$DETECTED_RENDER_DEV")
fi

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
