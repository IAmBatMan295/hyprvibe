hl.on("hyprland.start", function()
    local home = os.getenv("HOME") or ""
    hl.exec_cmd(home .. "/.config/hypr/scripts/wallpaper-changer.sh &")
    -- hl.exec_cmd("quickshell &")
    hl.exec_cmd("QML_IMPORT_PATH=" .. home .. "/.config/quickshell/Launcher${QML_IMPORT_PATH:+:$QML_IMPORT_PATH} quickshell &")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1 &")
    hl.exec_cmd("hypridle &")
    hl.exec_cmd("dunst &")
    hl.exec_cmd("hyprsunset &")
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/battery.sh &")
    hl.exec_cmd("localsend --hidden &")
    
    -- Clipboard Manager
    hl.exec_cmd("wl-paste --type text --watch cliphist store &")
    hl.exec_cmd("wl-paste --type image --watch cliphist store &")
end)
