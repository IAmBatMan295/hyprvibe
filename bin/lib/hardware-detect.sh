#!/usr/bin/env bash
# Hardware monitor and display scaling detection for HyprVibe
# Generates hardware-adaptive monitor configurations at install time.

DRM_SYSFS_DIR="${DRM_SYSFS_DIR:-/sys/class/drm}"
SDDM_HYPRLAND_SYS="${SDDM_HYPRLAND_SYS:-/usr/share/sddm/hyprland.lua}"

detect_all_monitors_info() {
    # 1. Try hyprctl if active (returns all connected monitors)
    if command -v hyprctl >/dev/null 2>&1 && pgrep -x Hyprland >/dev/null 2>&1; then
        local mon_json
        mon_json="$(hyprctl monitors -j 2>/dev/null || true)"
        if [[ -n "$mon_json" && "$mon_json" != "[]" ]]; then
            local parsed
            parsed="$(printf '%s' "$mon_json" | jq -r '
                .[] | . as $m
                | select(($m.name // "") != "")
                | ($m.availableModes // []
                    | map(
                        select(startswith("\($m.width)x\($m.height)@"))
                        | ltrimstr("\($m.width)x\($m.height)@")
                        | rtrimstr("Hz")
                        | split(".")[0]
                        | tonumber?
                    )
                    | max // (($m.refreshRate // 60) | floor)
                ) as $max
                | (if (($m.hardwareDetails.bt2020 // false)
                       or ($m.hardwareDetails.hdr // false)
                       or (($m.currentFormat // "") | test("2101010|16161616|F16")))
                   then 10 else 8 end) as $bpc
                | "\($m.name) \($m.width // 1920) \($m.height // 1080) \($max) \($m.scale // 1.0) \($bpc)"
            ' 2>/dev/null || true)"
            if [[ -n "$parsed" ]]; then
                printf '%s\n' "$parsed"
                return 0
            fi
        fi
    fi

    # 2. Sysfs DRM enumeration across all connected displays
    local found_any=0 p
    shopt -s nullglob
    local status_files=("${DRM_SYSFS_DIR}"/card*-*/status)
    shopt -u nullglob

    for p in "${status_files[@]}"; do
        [[ -f "$p" ]] || continue
        grep -qx "connected" "$p" 2>/dev/null || continue

        local dir base mon_name
        dir="$(dirname "$p")"
        base="$(basename "$dir")"
        mon_name="${base#*-}"
        [[ -n "$mon_name" ]] || continue

        local width=1920 height=1080 refresh=60 scale="1.0" bitdepth=8

        if [[ -f "${dir}/modes" ]]; then
            local top_mode
            top_mode="$(head -n 1 "${dir}/modes" 2>/dev/null || true)"
            if [[ "$top_mode" =~ ^([0-9]+)x([0-9]+) ]]; then
                width="${BASH_REMATCH[1]}"
                height="${BASH_REMATCH[2]}"
            fi
        fi

        if [[ -f "${dir}/edid" && -s "${dir}/edid" ]]; then
            if command -v edid-decode >/dev/null 2>&1; then
                local edid_out edid_max_hz bpc
                edid_out="$(edid-decode "${dir}/edid" 2>/dev/null || true)"
                edid_max_hz="$(printf '%s\n' "$edid_out" | grep -iE 'Max(imum)? Refresh Rate:' | grep -oE '[0-9]+' | sort -nr | head -n 1 || true)"
                if [[ -n "$edid_max_hz" && "$edid_max_hz" -gt 0 ]]; then
                    refresh="$edid_max_hz"
                fi
                bpc="$(printf '%s\n' "$edid_out" | grep -iE 'Bits per primary color channel:' | grep -oE '[0-9]+' | head -n 1 || true)"
                if [[ "$bpc" == "10" || "$bpc" == "12" ]]; then
                    bitdepth=10
                fi
            else
                # Pure binary EDID check: require EDID rev >= 4 and digital input bit 7 before reading bits 6-4 bpc
                local rev_hex b20_hex
                rev_hex="$(od -An -j19 -N1 -tu1 "${dir}/edid" 2>/dev/null | tr -d '[:space:]' || true)"
                b20_hex="$(od -An -j20 -N1 -tx1 "${dir}/edid" 2>/dev/null | tr -d '[:space:]' || true)"
                if [[ "$rev_hex" =~ ^[0-9]+$ ]] && (( rev_hex >= 4 )) && [[ -n "$b20_hex" ]]; then
                    local b20_dec=$(( 16#$b20_hex ))
                    if (( (b20_dec & 128) != 0 )); then
                        local bpc_code=$(( (b20_dec >> 4) & 7 ))
                        if (( bpc_code >= 3 )); then
                            bitdepth=10
                        fi
                    fi
                fi
            fi

            local edid_dims w_cm h_cm dpi=0
            edid_dims="$(od -An -N2 -j21 -tu1 "${dir}/edid" 2>/dev/null || true)"
            read -r w_cm h_cm <<< "$edid_dims"
            if [[ "${w_cm:-0}" =~ ^[0-9]+$ && "${h_cm:-0}" =~ ^[0-9]+$ ]] && (( w_cm > 0 && h_cm > 0 )); then
                dpi=$(awk -v w="$width" -v cm="$w_cm" 'BEGIN { printf "%d", w / (cm / 2.54) }')
            fi

            if (( dpi >= 210 )); then
                scale="1.8"
            elif (( dpi >= 170 )); then
                scale="1.5"
            elif (( dpi >= 135 )); then
                scale="1.25"
            elif (( dpi == 0 )) && [[ "$mon_name" =~ ^eDP ]] && (( height >= 1600 )); then
                scale="1.8"
            elif (( dpi == 0 )) && [[ "$mon_name" =~ ^eDP ]] && (( height >= 1400 )); then
                scale="1.5"
            else
                scale="1.0"
            fi
        fi

        printf "%s %s %s %s %s %s\n" "$mon_name" "$width" "$height" "$refresh" "$scale" "$bitdepth"
        found_any=1
    done

    if (( found_any == 0 )); then
        printf "eDP-1 1920 1080 60 1.0 8\n"
    fi
}

detect_monitor_info() {
    detect_all_monitors_info | head -n 1
}

format_hl_monitor_rule() {
    local mon_name="$1" width="$2" height="$3" refresh="$4" scale="$5" bitdepth="$6"
    if [[ "$bitdepth" == "10" ]]; then
        printf 'hl.monitor({ output = "%s", mode = "%sx%s@%s", position = "auto", scale = %s, bitdepth = 10 })' \
            "$mon_name" "$width" "$height" "$refresh" "$scale"
    else
        printf 'hl.monitor({ output = "%s", mode = "%sx%s@%s", position = "auto", scale = %s })' \
            "$mon_name" "$width" "$height" "$refresh" "$scale"
    fi
}

get_active_monitor_scale() {
    local repo_root="${1:-$HOME/HyprVibe}"
    local user_monitors="${repo_root}/dotfiles/hypr/.config/hypr/config/monitors.lua"
    if [[ ! -f "$user_monitors" && -f "${HOME}/.config/hypr/config/monitors.lua" ]]; then
        user_monitors="${HOME}/.config/hypr/config/monitors.lua"
    fi

    # Return explicit non-fallback per-output scale if already customized
    if [[ -f "$user_monitors" ]]; then
        local found_scale
        found_scale="$(grep -E 'output\s*=\s*"[^"]+"' "$user_monitors" | grep -oE 'scale\s*=\s*[0-9]+(\.[0-9]+)?' | head -n 1 | awk -F= '{print $2}' | tr -d ' ' || true)"
        if [[ -n "$found_scale" ]]; then
            printf "%s\n" "$found_scale"
            return 0
        fi
    fi

    local mon_info _ scale _
    mon_info="$(detect_monitor_info)"
    read -r _ _ _ _ scale _ <<< "$mon_info"
    printf "%s\n" "${scale:-1.0}"
}

ensure_monitors_config() {
    local repo_root="${1:-$HOME/HyprVibe}"
    local target_file="${repo_root}/dotfiles/hypr/.config/hypr/config/monitors.lua"
    local template_file="${repo_root}/templates/hypr/monitors.lua.template"

    mkdir -p "$(dirname "$target_file")"

    local rules_block="" mon_name width height refresh scale bitdepth
    while IFS=' ' read -r mon_name width height refresh scale bitdepth; do
        [[ -n "$mon_name" ]] || continue
        local rule
        rule="$(format_hl_monitor_rule "$mon_name" "$width" "$height" "$refresh" "$scale" "$bitdepth")"
        if [[ -z "$rules_block" ]]; then
            rules_block="$rule"
        else
            rules_block+=$'\n'"$rule"
        fi
    done < <(detect_all_monitors_info)

    # Keep generic fallback at scale=1.0 so unknown external displays do not inherit HiDPI scaling
    local fallback_scale="1.0"
    if [[ -f "$template_file" ]]; then
        local tpl_content
        tpl_content="$(<"$template_file")"
        tpl_content="${tpl_content//"{{SCALE}}"/$fallback_scale}"
        tpl_content="${tpl_content//"{{PRIMARY_RULE}}"/$rules_block}"
        printf '%s\n' "$tpl_content" > "$target_file"
    else
        cat > "$target_file" <<EOF
-- Auto-generated monitor configuration for Hyprland.
-- Generated dynamically at install time based on connected hardware.

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = ${fallback_scale} })
${rules_block}
EOF
    fi

    sync_sddm_compositor_config "$repo_root"
    return 0
}

sync_sddm_compositor_config() {
    local repo_root="${1:-$HOME/HyprVibe}"
    local target_file="${2:-$SDDM_HYPRLAND_SYS}"

    local rules_block="" mon_name width height refresh scale bitdepth
    local primary_scale=""
    while IFS=' ' read -r mon_name width height refresh scale bitdepth; do
        [[ -n "$mon_name" ]] || continue
        [[ -z "$primary_scale" ]] && primary_scale="$scale"

        local sddm_refresh=60
        if [[ -n "$refresh" && "$refresh" =~ ^[0-9]+$ ]]; then
            if (( refresh >= 120 )); then
                sddm_refresh=120
            else
                sddm_refresh="$refresh"
            fi
        fi

        local rule
        rule="$(format_hl_monitor_rule "$mon_name" "$width" "$height" "$sddm_refresh" "$scale" "$bitdepth")"
        if [[ -z "$rules_block" ]]; then
            rules_block="$rule"
        else
            rules_block+=$'\n'"$rule"
        fi
    done < <(detect_all_monitors_info)

    local fallback_scale="1.0"
    local active_scale
    active_scale="$(get_active_monitor_scale "$repo_root")"
    if [[ -n "$active_scale" && -n "$primary_scale" && -z "${rules_block##*$'\n'*}" ]]; then
        # Single-monitor setup: preserve user-customized monitors.lua scale if present
        :
    fi

    local template_file="${repo_root}/templates/sddm/hyprland.lua.template"
    local tmp_rendered
    tmp_rendered="$(mktemp "${TMPDIR:-/tmp}/hyprvibe-sddm-hypr.XXXXXX")"

    if [[ -f "$template_file" ]]; then
        local tpl_content
        tpl_content="$(<"$template_file")"
        tpl_content="${tpl_content//"{{SCALE}}"/$fallback_scale}"
        tpl_content="${tpl_content//"{{PRIMARY_RULE}}"/$rules_block}"
        printf '%s\n' "$tpl_content" > "$tmp_rendered"
    else
        cat > "$tmp_rendered" <<EOF
-- Minimal Hyprland configuration for HyprVibe SDDM Wayland greeter.
hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
    vrr = 1,
  },
  animations = {
    enabled = true,
  },
})

hl.on("hyprland.start", function()
  hl.exec_cmd("hyprsunset -t 3700 &")
end)

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = ${fallback_scale} })
${rules_block}
EOF
    fi

    local out_dir
    out_dir="$(dirname "$target_file")"
    if [[ -w "$out_dir" || -w "$target_file" ]]; then
        install -m 644 "$tmp_rendered" "$target_file" 2>/dev/null || true
    elif [[ -d "$out_dir" ]] && sudo -n true 2>/dev/null; then
        sudo -n install -m 644 "$tmp_rendered" "$target_file" >/dev/null 2>&1 || true
    fi
    rm -f "$tmp_rendered"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ensure_monitors_config "${1:-$HOME/HyprVibe}"
fi

