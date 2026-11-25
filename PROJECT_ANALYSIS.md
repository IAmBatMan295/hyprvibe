# HyprVibe Project Deep Analysis

> Static audit of configs, scripts, Quickshell shell/widgets, theme-switching engine, and CachyOS installer + hardware detection.
> Generated phase-by-phase without modifying runtime state or executing project scripts.
> Note: Git-ignored/untracked files (personal secrets, runtime state, local overrides) are excluded from GitHub leak/security concerns per project context, though integration with tracked templates/scripts is audited.

---

## Inventory Summary

- **Root**: `/home/kunjan/HyprVibe`
- **Core compartments**:
  1. `dotfiles/` (24 Stow packages targeting `~`: `.config/`, `.local/`, `.gtkrc-2.0`, `.zshrc`, plus non-stow/system packages `chromium`, `sddm`)
  2. `dotfiles/quickshell/` (~12k lines QML/JS bar, control panels, services, + 12 `.local/bin/hyprvibe-*` helpers)
  3. `dotfiles/hypr/.config/hypr/scripts/` + `bin/helpers/` + `dotfiles/btop/.local/bin/btop` + `plugins/`
  4. Theme engine: `bin/hyprvibe-theme`, `bin/lib/theme-engine.sh`, `templates/themed/*`, `themes/*/colors.toml`
  5. Installer & Hardware Detection: `bin/install.sh`, `bin/lib/common.sh`, `bin/lib/hardware-detect.sh`, `bin/install-packages.sh`, `bin/stow-dotfiles.sh`, `bin/theme-assets-installer.sh`, `bin/miscellaneous.sh`, `bin/github-auth.sh`, `packages/*`, `plymouth-theme/*`, `templates/hypr/*`, `templates/xfce4/*`

---

## Phase 1: Core Dotfile Configs (Non-Quickshell)

### 1.1 Hyprland & Wayland Session (`dotfiles/hypr/`, `templates/hypr/`)
- **Files**: [hyprland.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/hyprland.lua), [autostart.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/autostart.lua), [binds.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/binds.lua), [environment.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/environment.lua), [inputs.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/inputs.lua), [rules.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/rules.lua), [theme.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/theme.lua), [hypridle.conf](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/hypridle.conf), [hyprlock.conf](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/hyprlock.conf), [hyprsunset.conf](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/hyprsunset.conf), [monitors.lua.template](file:///home/kunjan/HyprVibe/templates/hypr/monitors.lua.template)
- **Findings**:
  1. **Bug — Broken Lid Switch DPMS dispatch (`binds.lua:73-74`)**: `hl.dsp.exec_cmd("sleep 0.5 && hyprctl dispatch 'hl.dsp.dpms(\"off\")'")` and `"hyprctl dispatch 'hl.dsp.dpms(\"on\")'"` pass Hyprland-Lua syntax inside shell `hyprctl dispatch`, which Hyprland rejects (must be `hyprctl dispatch dpms off` / `on` or direct Lua `hl.dsp.dpms("off")`).
  2. **Bug/Portability — Hardcoded repo path in keybind (`binds.lua:22`)**: `os.getenv("HOME") .. "/HyprVibe/bin/hyprvibe-theme menu"` breaks if repo is cloned to another path (whereas `theme.lua:89-96` dynamically resolves via `readlink -f`).
  3. **Bug/Layout — Hardcoded pixel offset in `hyprlock.conf:38`**: Time label uses `valign = top` and `position = 0, -560`. On 1080p screens (`half = 540px`), `-560` pushes the clock below vertical center into `DAY-DATE-MONTH` (`center + 60`) and `USER` (`center - 80`). Percentage or relative positioning / screen-aware layout is needed for varying monitor heights.
  4. **Behavior/Security — `hypridle.conf` does not lock screen**: `lock_cmd = pidof madsnake || madsnake` and `on-timeout = madsnake` after 60s only launch a terminal snake screensaver (`madsnake`), never invoking `hyprlock` or DPMS off. Anyone pressing a key exits screensaver without authentication.
  5. **Minor — Screenshot naming & pipeline (`binds.lua:27,33`)**: Uses `$(date +%F_%T)` (colons `:` fail on FAT32/exFAT/Windows/some cloud mounts) and `wl-copy && wl-paste > ...` instead of `tee` (if `slurp` is cancelled, `grim` fails safely; using `tee` avoids clipboard round-trip race).
  6. **Minor — `autostart.lua` backgrounding inconsistency**: `hl.exec_cmd("hypridle")` and `wl-paste --watch ...` omit `&` while all other commands include `&`; `localsend --hidden &` runs unconditionally; `theme.lua:107` omits quotes around `bin` in `test -x ` check; `rules.lua:3` sets `code` opacity `0.8 1.0 override` (more transparent when active than inactive — likely inverted).
  7. **Note — `hyprsunset.conf`**: Single `00:00` profile permanently forces `3700K` all day (no daytime `6500K` profile).

### 1.2 Shell, Terminal, Multiplexer & System Monitor (`shell-config/`, `foot/`, `ohmyposh/`, `tmux/`, `btop/`)
- **Files**: [.zshrc](file:///home/kunjan/HyprVibe/dotfiles/shell-config/.zshrc), [foot.ini](file:///home/kunjan/HyprVibe/dotfiles/foot/.config/foot/foot.ini), [zen.toml](file:///home/kunjan/HyprVibe/dotfiles/ohmyposh/.config/ohmyposh/zen.toml), [tmux.conf](file:///home/kunjan/HyprVibe/dotfiles/tmux/.config/tmux/tmux.conf), [block-gray.conf](file:///home/kunjan/HyprVibe/dotfiles/tmux/.config/tmux/themes/block-gray.conf), [btop.conf](file:///home/kunjan/HyprVibe/dotfiles/btop/.config/btop/btop.conf)
- **Findings**:
  1. **Bug — Zsh `list-colors` single-quoted (`zshrc:48`)**: `zstyle ':completion:*' list-colors '${(s.:.)LS_COLORS}'` passes a literal string instead of expanding `LS_COLORS`; requires double quotes `"${(s.:.)LS_COLORS}"`.
  2. **Bug/Duplicate — `.zshrc` issues**:
     - Lines 41–42 duplicate `setopt hist_ignore_all_dups`.
     - Lines 8–9 use unquoted `$ZINIT_HOME` and synchronously `git clone` during interactive shell startup (hangs if offline).
     - Line 25 runs `compinit` without `-C` on every shell start (adds startup latency).
     - Line 55 uses `find . -type f -o -type d` for `FZF_DEFAULT_COMMAND` (slow, includes `.git`/`node_modules`; `fd` is much faster if installed).
     - Line 126 adds `$HOME/.local/bin` to `PATH` only inside interactive `.zshrc`, NOT `.zprofile` / `environment.lua` — non-interactive Wayland/Hyprland/Quickshell processes do not inherit `.zshrc`'s `PATH`.
     - Lines 67–75 (`cpg`, `rustpg`, `pypg`) reference personal `~/Desktop/*pg` directories.
  3. **Mismatch — `tmux.conf` plugin path & comment**:
     - Line 25 executes `run '~/.tmux/plugins/tpm/tpm'`, whereas `dotfiles/.gitignore:1` ignores `tmux/.config/tmux/plugins/`. Must verify where installer places `tpm`.
     - Line 47 comment says `prefix + k`, binding is `bind c kill-window`.
     - `allow-passthrough on` is not set, blocking OSC 11/111 sequences from Neovim (`theme.lua`) from reaching `foot`.

### 1.3 Desktop UI, GTK, Rofi, Dunst, Waybar, Thunar & SDDM
- **Files**: [dunstrc](file:///home/kunjan/HyprVibe/dotfiles/dunst/.config/dunst/dunstrc), [00-hyprvibe-theme.conf](file:///home/kunjan/HyprVibe/dotfiles/dunst/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf), [gtk-3.0/gtk.css](file:///home/kunjan/HyprVibe/dotfiles/gtk-3.0/.config/gtk-3.0/gtk.css), [gtk-4.0/gtk.css](file:///home/kunjan/HyprVibe/dotfiles/gtk-4.0/.config/gtk-4.0/gtk.css), [gtk-4.0/gtk-dark.css](file:///home/kunjan/HyprVibe/dotfiles/gtk-4.0/.config/gtk-4.0/gtk-dark.css), [rofi/*.rasi](file:///home/kunjan/HyprVibe/dotfiles/rofi/.config/rofi/config.rasi), [waybar/config.jsonc](file:///home/kunjan/HyprVibe/dotfiles/waybar/.config/waybar/config.jsonc), [waybar/style.css](file:///home/kunjan/HyprVibe/dotfiles/waybar/.config/waybar/style.css), [uca.xml](file:///home/kunjan/HyprVibe/dotfiles/xfce4/.config/Thunar/uca.xml), [thunar.xml.template](file:///home/kunjan/HyprVibe/templates/xfce4/thunar.xml.template), [sddm/*](file:///home/kunjan/HyprVibe/dotfiles/sddm/themes/hyprvibe/Main.qml)
- **Findings**:
  1. **Bug — GTK/Waybar relative `@import` through Stow symlinks**: `gtk-3.0/gtk.css:24`, `gtk-4.0/gtk.css:24`, `gtk-4.0/gtk-dark.css:2`, and `waybar/style.css:8` use `@import "../../.local/state/hyprvibe/current/..."`. If a CSS parser canonicalizes the symlink before resolving relative `@import`, `../../` resolves inside `~/HyprVibe/dotfiles/<pkg>/` (nonexistent) instead of `~/`! Using `~/.local/state/...` or absolute/stowed links avoids canonicalization pitfalls.
  2. **Stow Risk — `dunstrc.d/00-hyprvibe-theme.conf` is tracked in git**: Need to verify in Phase 4 whether `hyprvibe-theme` writes directly to `~/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf` (mutating the git-tracked file through Stow's symlink!).
  3. **Dead/Broken Legacy Config — `waybar/config.jsonc`**: Replaced by Quickshell in `autostart.lua`, plus contains `"tooltip_format"` typo (`cpu` module line 35, should be `"tooltip-format"`), calls `swaync-client -t -sw` (line 48, `dunst` is used instead of `swaync`), `nmgui`, `pavucontrol`, `pamixer`, `bluetui`, and `$TERMINAL -e btop` (waybar doesn't expand `$TERMINAL` unless wrapped in `sh -c`).
  4. **Bug — `sddm/themes/hyprvibe/Main.qml:158,277`**: `shakeAnim` animates `property: "x"` on `inputContainer`, which has `anchors.horizontalCenter: parent.horizontalCenter` — animating `x` on an anchored QML item violates Qt Quick anchor constraints and fails/snaps. Fix: animate a `Translate` transform or `anchors.horizontalCenterOffset`.
  5. **Bug/Override — `sddm/hyprland.lua:21-22`**: Tracked in git with personal hardware monitor rule (`output = "eDP-1", mode = "2880x1800@120", scale = 1.8`) despite comment saying generated dynamically at install time. Must verify in Phase 5 whether installer mutates this tracked file or writes `/usr/share/sddm/hyprland.lua`.
  6. **Behavior — `sddm/components/SessionSelect.qml:24-38`**: Always prefers `"uwsm"+"hyprland"` or `"hyprland"` before checking `model.lastIndex`, effectively ignoring `RememberLastSession=true` in `10-theme.conf` if user selects another DE/WM. Also inverted `ListView` (`getInvertedIndex`) starts scrolled at top rather than bottom if >4 items.
  7. **Minor — `gtk-4.0/gtk-dark.css`**: Missing fallback `@define-color` variables present in `gtk.css`; `gtk-3.0/gtk.css:27` targets `.nemo-window *` though Thunar is the configured file manager.

### 1.4 Media, AI & Misc (`mpd/`, `mpv/`, `rmpc/`, `madsnake/`, `llama-server/`, `sd-server/`)
- **Files**: [mpd.conf](file:///home/kunjan/HyprVibe/dotfiles/mpd/.config/mpd/mpd.conf), [mpDris2.conf](file:///home/kunjan/HyprVibe/dotfiles/mpd/.config/mpDris2/mpDris2.conf), [mpv.conf](file:///home/kunjan/HyprVibe/dotfiles/mpv/.config/mpv/mpv.conf), [config.ron](file:///home/kunjan/HyprVibe/dotfiles/rmpc/.config/rmpc/config.ron), [madsnake/config](file:///home/kunjan/HyprVibe/dotfiles/madsnake/.config/madsnake/config), [llama-server.conf](file:///home/kunjan/HyprVibe/dotfiles/llama-server/.config/llama-server/llama-server.conf), [sd-server.conf](file:///home/kunjan/HyprVibe/dotfiles/sd-server/.config/sd-server/sd-server.conf)
- **Findings**:
  1. **Critical Bug — Syntax error in `rmpc/config.ron:210`**: Stray trailing `}` on line 210 after top-level `)` closes on line 209 — breaks RON config parsing! Also lines 50-51, 56-57, 102-103, 117-118 have awkward line wraps (`"x": \n ToggleRandom`).
  2. **Personal/Hardware Coupling**: `llama-server.conf` hardcodes `CTX_SIZE=65536`, `GPU_LAYERS=99`, `LAST_MODEL=".../Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"`, and `sd-server.conf` hardcodes `flux1-dev-Q3_K_S.gguf` / `WIDTH=1024` / `HEIGHT=1024` (VRAM-dependent; needs GPU/VRAM awareness or clean defaults).

### 1.5 Neovim (`dotfiles/nvim/`)
- **Files**: [init.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/init.lua), [lazy.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/config/lazy.lua), [keymaps.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/config/keymaps.lua), [options.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/config/options.lua), [theme.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/config/theme.lua), [theme-sync.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/plugins/theme-sync.lua), [lualine.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/plugins/lualine.lua), [render-markdown.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/plugins/render-markdown.lua), [forest-green.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/colors/forest-green.lua), [disable_docs.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/plugins/disable_docs.lua)
- **Findings**:
  1. **Bug — `lualine.setup()` called with no args (`theme.lua:93`)**: Strips custom `opts` (`globalstatus = true`, dynamic `theme = function()`) set in `plugins/lualine.lua` on every live theme switch! Should call `require("lualine").refresh()` or re-pass plugin opts instead.
  2. **Performance/Bug — Unthrottled `apply_theme()` (`theme-sync.lua:23-40,61`)**:
     - `LazyVim.opts.colorscheme` calls `apply_theme()`, AND `hyprvibe-theme-sync` `config` calls `apply_theme()` again (duplicate startup theme load).
     - `FocusGained` unconditionally runs `vim.cmd.colorscheme(...)` + `lualine.setup()` even when theme hasn't changed!
     - `uv.new_fs_event()` watches `~/.local/state/hyprvibe/current` without debounce (fires 13+ times per `hyprvibe-theme set`, one per rendered template) and silently fails forever if the directory doesn't exist at startup.
  3. **Design Smell — Fake self-plugin (`theme-sync.lua:18`)**: `dir = "~/.config/nvim"` registers the user config dir itself as a Lazy plugin (`runtimepath` duplication); placing autocmds/watcher in `lua/config/autocmds.lua` avoids this.
  4. **Terminal Sync Limitation (`theme.lua:43-56`)**: Raw `io.stdout:write("\x1b]11;...")` works in direct `foot`, breaks/drops inside `tmux` without `allow-passthrough on`, and writes to stdout in headless mode.
  5. **Dependency Bloat (`render-markdown.lua:3`)**: Depends on full `nvim-mini/mini.nvim` even though LazyVim uses `mini.icons`.
  6. **Minor (`keymaps.lua:38-43`)**: `_term_root` caches first root across cwd changes; `tokyonight.lua` is installed (`lazy-lock.json`) though HyprVibe doesn't map any theme to `tokyonight` (only used in `lazy.lua` fallback list).

---

## Phase 2: Quickshell Shell, Widgets, Panels & `.local/bin/hyprvibe-*`

### 2.1 Core Shell Host & Commons (`shell.qml`, `shell.json`, `Commons/*`, `services/*`)
- **Files**: [shell.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/shell.qml), [shell.json](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/shell.json), [ThemeColor.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Commons/ThemeColor.qml), [Style.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Commons/Style.qml), [Util.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Commons/Util.qml), [Border.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Commons/Border.qml), [PluginRegistry.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/services/PluginRegistry.qml)
- **Findings**:
  1. **Bug — `ThemeColor.qml:76-120` skips `flatColor()` on non-alpha properties**: `bar.text`, `bar.active`, `popups.text`, `tooltip.text`, `notifications.countdown`, `menu.text`, `menu.selectedText`, `polkit.text`, `polkit.textError`, `polkit.accent`, `lock.text`, `lock.textError` call `root.pick(...)` directly instead of `root.flatColor(root.pick(...), fallback)`. If `shell.toml` sets a role name (e.g., `bar.text = "accent"`), QML throws invalid color assignment.
  2. **Bug — `Style.qml:279` vs `389` base font mismatch**: Initial `fontBaseSize` is `14`, but `applyShellValues()` resets `nextBase = 12` when `[font] base-size` is absent, causing an instant font-size snap on startup once `shell.toml` loads.
  3. **Bug/Stow Risk — `shell.qml:124-146`**: Both `defaultsFile` and `userConfigFile` watch `~/.config/quickshell/shell.json` (duplicate FileView watch). `persistShellConfig` uses `atomicWrites: true`, which replaces a GNU Stow symlink with a standalone file if plugin mutations run.
  4. **Duplicate IPC / Reload Work**: `ThemeColor.qml` watches `colors.toml` + `shell.toml` via `FileView`, while `shell.qml:1460` (`IpcHandler.applyTheme`) also parses base64 payloads (`Qt.atob`, Latin1-only) — theme switches trigger double reloads.

### 2.2 Bar & Bar Widgets (`plugins/bar/*`, `plugins/panels/clock/*`)
- **Files**: [Bar.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/Bar.qml), [BarModel.js](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/BarModel.js), [Workspaces.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Workspaces.qml), [Backlight.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Backlight.qml), [Cpu.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Cpu.qml), [Memory.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Memory.qml), [Media.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Media.qml), [PowerProfile.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/PowerProfile.qml)
- **Findings**:
  1. **Bug — `Workspaces.qml:40` passes Lua syntax to `hyprctl dispatch`**: `hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })'` fails on standard Hyprland IPC (unless a custom dispatcher wraps it; should use `Hyprland.dispatch("workspace " + id)` natively via `Quickshell.Hyprland` without spawning `bash -lc`).
  2. **Bug — `Bar.qml:634,576,882,1270,1284` ignores config & stubs**:
     - `applyBarConfig()` hardcodes `position = "top"` and `setBarPosition()` hardcodes `"top"` (contradicting `shell.json` & `manual-edit.md` `"bottom"` docs).
     - `toggleTransparency()` is an empty no-op even though `shell.qml:1480` exposes IPC `toggleBarTransparency()`.
     - `BarPanel.margins` only defines `Behavior on top`, not `bottom`/`left`/`right`.
     - `BarPanel.color: Util.alpha(root.background, 0.85)` hardcodes `0.85` opacity, overriding `[bar] background-alpha` in `shell.toml`.
     - `FileView` watching `~/.local/state/hyprvibe/toggles` fails silently if directory does not exist at startup.
  3. **Hardware Detection / Multi-Monitor Efficiency**:
     - `Backlight.qml`: Always active in `shell.json`; on desktops without `/sys/class/backlight`, `brightnessctl -m info` fails every 5s while widget stays visible showing hardcoded `40%`.
     - `PowerProfile.qml`: Restarts `gdbus monitor --system --dest net.hadess.PowerProfiles` every 3s forever if `power-profiles-daemon` is missing/masked; stays visible regardless of capability.
     - `Cpu.qml`: Reads `/proc/cpuinfo` `cpu MHz` (missing on some architectures/VMs or reporting base clock; `cpufreq/scaling_cur_freq` is more reliable).
     - `Media.qml`: Spawns `bash -c "rmpc status; rmpc song"` every 1.5s when playing (`5s` idle), even though `Quickshell.Services.Mpris` + `mpDris2` already exist in the session.
     - **Multi-monitor duplication**: `Bar.qml` instantiates every widget per screen, multiplying `IpcHandler` conflicts and spawning N× identical polling processes (`Cpu`, `Memory`, `Media`, `Backlight`, `PowerProfile`, `Audio.volumeSinkProc`, `Network.refresh`).

### 2.3 Control Panels (`plugins/panels/*`) & UI Components (`Ui/*`)
- **Files**: [audio/Panel.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/audio/Panel.qml), [bluetooth/Panel.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/bluetooth/Panel.qml), [bluetooth/Model.js](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/bluetooth/Model.js), [network/Panel.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/network/Panel.qml), [power/Panel.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/power/Panel.qml), [KeyboardPanel.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Ui/KeyboardPanel.qml), [Button.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Ui/Button.qml), [CursorSurface.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Ui/CursorSurface.qml), [PanelSlider.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Ui/PanelSlider.qml)
- **Findings**:
  1. **Critical Bug — `network/Panel.qml:515` invokes nonexistent launcher**: Clicking DNS `Custom` executes `"hyprvibe-launch-floating-terminal-with-presentation"`, which does not exist anywhere in HyprVibe!
  2. **Bug — `audio/Panel.qml:621` references undefined property `root.allMuted`**: Tooltip evaluates `root.allMuted ? "Audio: Muted" : ...` instead of `!root.anyAudible` / `root.outputMuted`, so muted state never appears in tooltip.
  3. **Bug — `network/Panel.qml:621-629` `enterpriseConnect` `Process` lacks `onExited`**: Failed `nmcli` 802.1X connections hang in `"Connecting…"` until 30s `actionTimeout`. Also line 1745 hardcodes `"Wrong password"` for all failure reasons (`isFailed ? "Wrong password" : ...`) instead of `failureReason`.
  4. **Bug — `bluetooth/Panel.qml:126` vs `bluetooth/Model.js:145` visibility mismatch**: `sectionVisible("discovered")` checks `!root.scanning`, while `Model.visibleSections` omits `!root.scanning`. Keyboard cursor `j/k` can enter `"discovered"` while UI hides those rows during scan! Also closing panel (`onOpenedChanged`, line 418) kills `pairProc` without clearing `pendingActions` for `pairPromptAddress`, and `scanBluetoothDevices()` runs both `adapter.discovering = true` and `hyprvibe-bluetooth-device scan` (`bluetoothctl scan on`) concurrently.
  5. **Systemic Risk — Bare `hyprvibe-*` invocations depend on `PATH`**: All panels invoke `hyprvibe-audio-*`, `hyprvibe-battery-status`, `hyprvibe-system-stats`, `hyprvibe-bluetooth-*`, `hyprvibe-network-*`, `hyprvibe-dns` without `~/.local/bin/` prefix, while `~/.local/bin` is only added in `.zshrc` (interactive shells), NOT in `environment.lua`! Must check if systemd `environment.d` or `/etc/profile` sets it in Phase 5.
  6. **Minor `Ui/*` bugs**: `Button.qml` & `CursorSurface.qml` override `[controls]` border specs with hardcoded `Border.flat(...)` (while `Button.qml` still reserves padding using `_focusBorderSpec` etc.); `PanelSlider.qml:113` lacks `track.width > 0` guard against division by zero (`NaN`).

### 2.4 Quickshell Helper Binaries (`dotfiles/quickshell/.local/bin/hyprvibe-*`)
- **Files**: 12 scripts under [dotfiles/quickshell/.local/bin/](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.local/bin/)
- **Findings**:
  1. **Bug — `hyprvibe-network-status:3,138` crashes on `speed` read**: With `set -euo pipefail`, `[[ -r /sys/class/net/$iface/speed ]] && ... $(cat .../speed)` aborts on virtual/USB/bridge NICs where `speed` is readable (`-r`) yet returns `EINVAL` (`Invalid argument`), skipping `print_ping_samples`. Also `ip route get 1.1.1.1` (line 33) fails on LAN-only/airgapped/IPv6-only networks.
  2. **Bug — `hyprvibe-dns:190-194,201-244`**:
     - `Custom` mode reads stdin (`read -r dns_servers`), failing if launched non-interactively via `pkexec`; `normalize_servers` uses `xargs` (unsafe with quotes/backslashes).
     - Overwrites `/etc/systemd/resolved.conf` completely instead of writing a drop-in `/etc/systemd/resolved.conf.d/20-hyprvibe-dns.conf`, AND mutates every individual NM connection profile permanently (`clear_connection_dns` resets profiles that had custom static DNS before).
  3. **Bug — `hyprvibe-battery-status:21,106-110,188-192`**:
     - `grep BAT` misses ACPI batteries named `CMB0` (common on Acer/some laptops; `/battery_` is reliable).
     - IdeaPad `conservation_mode` hardcodes `80`/`60` threshold guess from `percentage > 65` (older IdeaPads cap at 60%, newer at 80% regardless of current %).
     - When `state` is `fully-charged` or `pending-charge` without `charge_holding`, empty `time_remaining` prints broken `"Battery 100% ·  left · ..."`.
  4. **Bug — `hyprvibe-bluetooth-pair:49,58,68,87,144`**:
     - Synchronous `sys.stdin.readline()` inside D-Bus handlers blocks the single-threaded GLib mainloop (`on_timeout` cannot fire while waiting).
     - `dev.Connect()` failure is caught and ignored, still printing `RESULT success`.
  5. **Minor**: `hyprvibe-bluetooth-device:24` checks only default controller (`bluetoothctl show`) unlike `hyprvibe-bluetooth-power`, and swallows `connect`/`forget` failures via `|| true`; `hyprvibe-audio-input-set-default` lacks the `timeout 2` guards present in `hyprvibe-audio-output-set-default`.

---

## Phase 3: Hyprland, Wrapper & Helper Scripts

### 3.1 Hyprland Session Scripts (`dotfiles/hypr/.config/hypr/scripts/`) & `btop` Wrapper
- **Files**: [battery.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/battery.sh), [clipboard-menu.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/clipboard-menu.sh), [helpers-menu.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/helpers-menu.sh), [power-menu.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/power-menu.sh), [power-profiles.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/power-profiles.sh), [screen-record.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/screen-record.sh), [toggle-refresh.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/toggle-refresh.sh), [wallpaper-changer.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/wallpaper-changer.sh), [btop wrapper](file:///home/kunjan/HyprVibe/dotfiles/btop/.local/bin/btop)
- **Findings**:
  1. **Critical Bug — Broken VRR query in `toggle-refresh.sh:30` & `power-profiles.sh:55`**: Both query `hyprctl getoption misc.vrr -j` (dot separator) instead of `misc:vrr` (colon separator, as used in `Style.qml:444`). Hyprland rejects `misc.vrr`, so `STATE` is always empty — **`toggle-refresh.sh` can NEVER switch back from 60Hz to `MAX_RATE` VRR**, and `power-profiles.sh` always forces 60Hz on `Power Saver` (and never restores high refresh rate when switching back to `Balanced`/`Performance`).
  2. **Critical Bug — Broken logout command in `power-menu.sh:27`**: Uses `hyprctl dispatch 'hl.dsp.exit()'` (same Lua-in-dispatch bug as `binds.lua:73-74` and `Workspaces.qml:40`). Should be `hyprctl dispatch exit` (or `uwsm stop`).
  3. **Bug — Multi-monitor & Panel assumptions**:
     - `toggle-refresh.sh` & `power-profiles.sh` target `.[0]` unconditionally and hardcode `bitdepth = 10` (fails/flickers on 6/8-bit panels or bandwidth-limited external displays).
     - `screen-record.sh:163` omits `-o <focused_output>` on `wf-recorder`: on multi-monitor setups `wf-recorder` aborts immediately in background because it tries to prompt interactively on stdin for which monitor to record.
     - `screen-record.sh:106` skips `ffmpeg` H.264 encode test if `vainfo` exits 0 — decode-only VAAPI drivers pass `vainfo` yet fail recording; on hybrid GPUs `vainfo` doesn't receive `--device "$render_node"`.
     - `screen-record.sh:15-16` deletes `$PIDFILE` immediately after `SIGINT` without waiting for MP4 moov atom flush; `LABEL` hardcodes `1080p`.
  4. **Minor Bugs**:
     - `battery.sh:6` checks `/sys/class/power_supply/BAT*` only (misses `CMB*` batteries; should check `type == Battery` & `scope != Device`).
     - `power-profiles.sh:3` fails without guard if `powerprofilesctl` / daemon missing (desktops).
     - `clipboard-menu.sh:29` uses `echo "$FINAL_MENU"` instead of `printf '%s\n'` (unsafe if clipboard item starts with `-n`/`-e` or contains escapes).
     - `wallpaper-changer.sh:117` exit trap does not kill active `$SLEEP_PID`.

### 3.2 `bin/helpers/*` & `plugins/battery-conservation/`
- **Files**: [battery-conservation.sh](file:///home/kunjan/HyprVibe/bin/helpers/battery-conservation.sh), [calculate-replaygain.sh](file:///home/kunjan/HyprVibe/bin/helpers/calculate-replaygain.sh), [rename-theme-wallpapers.sh](file:///home/kunjan/HyprVibe/bin/helpers/rename-theme-wallpapers.sh), [update-package-list.sh](file:///home/kunjan/HyprVibe/bin/helpers/update-package-list.sh), [wallpaper-theming.sh](file:///home/kunjan/HyprVibe/bin/helpers/wallpaper-theming.sh), [llama-server.sh](file:///home/kunjan/HyprVibe/bin/helpers/llama-server.sh), [sd-server.sh](file:///home/kunjan/HyprVibe/bin/helpers/sd-server.sh), [plugins/battery-conservation/install.sh](file:///home/kunjan/HyprVibe/plugins/battery-conservation/install.sh)
- **Findings**:
  1. **Critical Bug (Stow Violation) — `llama-server.sh:138` & `sd-server.sh:95` overwrite git-tracked configs**: `save_config()` writes directly to `~/.config/llama-server/llama-server.conf` and `~/.config/sd-server/sd-server.conf`, which are Stow symlinks into the repo! Changing model/settings dirties git. Mutable runtime overrides belong in `~/.local/state/`.
  2. **Critical Bug — Duplicate menu key `3)` in `sd-server.sh:614-620`**: When `sd-server` is running, menu prints BOTH `3) Restart Server` and `3) Open Generated Images Folder`, making folder open unreachable.
  3. **Bugs in `sd-server.sh`**:
     - Lines 163–208 (`apply_model_defaults`, `find_models`) are dead code (never wired to menu); `generate_image` prints `"Generating image with FLUX.1..."` + prompt twice (lines 367–375) and names all files `flux_*.png`.
     - Line 586 writes unvalidated `GUIDANCE` unquoted into sourced conf; `--detect-type`/`--generate` crash under `set -u`/`shift 2` if arg omitted; lines 29-37 reuse global `WIDTH`/`HEIGHT` variables used for generation size.
  4. **Bugs in `llama-server.sh`**:
     - `--restart` fails if `LAST_MODEL` is empty (no fallback to `found[0]`); `--model`/`--models-dir` crash on missing arg; `LOG_FILE` writes to `$HOME/llama-server.log` instead of state dir; Option 4 (`MODELS_DIR`) & `sd-server.sh` Option 5 (`OUTPUT_DIR`) don't expand `~`; high-VRAM defaults (`CTX_SIZE=65536`, `GPU_LAYERS=99`) have no GPU/VRAM detection.
  5. **Hardware Limitation — `battery-conservation.sh` & `plugins/battery-conservation/install.sh`**:
     - Only supports Lenovo IdeaPad `ideapad_acpi` `conservation_mode`, ignoring standard `/sys/class/power_supply/BAT*/charge_control_end_threshold` (ThinkPad, ASUS, Framework, MSI, Dell) even though `hyprvibe-battery-status` already supports it.
     - `battery-conservation.sh` still invokes `sudo tee` even though `install.sh` creates a `0666` udev rule (which itself hardcodes `${found_path}` instead of `%S%p/conservation_mode` or `$sys$devpath`).
  6. **Bugs in `wallpaper-theming.sh`, `calculate-replaygain.sh`, `rename-theme-wallpapers.sh`, `update-package-list.sh`**:
     - `wallpaper-theming.sh`: `--palette` defaults silently to index `0` on unknown slug; missing arg crashes `$2` (`set -u`); `mktemp` lacks `EXIT` cleanup trap; `touch "$target_file"` before `lutgen` leaves 0-byte files on failure; doesn't use `readlink -f`.
     - `calculate-replaygain.sh:174`: exits immediately on invalid dir without pause so floating terminal closes before error is read.
     - `rename-theme-wallpapers.sh:107`: renames ALL non-dot files in `backgrounds/` instead of filtering image extensions.
     - `update-package-list.sh:85`: raw `pacman -Qneq`/`-Qmeq` bakes host-specific GPU/kernel/microcode/personal packages into `packages/*.txt`.
  7. **Code Duplication & Hyprland Rule Leak**: All 6 interactive helpers duplicate the same 25-line `MON_INFO` + `hyprctl eval` floating-`foot` wrapper, accumulating duplicate dynamic `hl.window_rule` rules on each launch and breaking if `"$@"` contains single quotes.

---

## Phase 4: Theme Switching System

- **Files**: [hyprvibe-theme](file:///home/kunjan/HyprVibe/bin/hyprvibe-theme), [theme-engine.sh](file:///home/kunjan/HyprVibe/bin/lib/theme-engine.sh), [themes/*/colors.toml](file:///home/kunjan/HyprVibe/themes/catppuccin/colors.toml), [templates/themed/*.tpl](file:///home/kunjan/HyprVibe/templates/themed/shell.toml.tpl)
- **Findings**:
  1. **Critical Bug — Dunst dynamic theme (`dunst.conf.tpl`) is never applied**: `hyprvibe-theme` renders `~/.local/state/hyprvibe/current/dunst.conf`, yet `dotfiles/dunst/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf` is a static git-tracked monochrome file and `dunstrc` never sources `STATE_DIR/dunst.conf`. Running `dunstctl reload` reloads the static monochrome file every time.
  2. **Critical Bug — SDDM system theme permissions & extension mismatch (`hyprvibe-theme:183,200-218`)**: `/usr/share/sddm/themes/hyprvibe` is only updated `if [[ -w "$sddm_theme_dir" ]]` — if root-owned after install, user-level theme switches silently skip updating SDDM. Also copies `.png`/`.webp` wallpapers to `default-bg.jpg` with mismatched extension.
  3. **Bug — `hyprvibe-theme:8` fails if symlinked**: Uses `dirname "${BASH_SOURCE[0]}"` without `readlink -f`, breaking `THEME_LIB` lookup when invoked via a symlink in `~/.local/bin`.
  4. **Bug — `theme-engine.sh` sed escaping & trap collision**:
     - `render_template` / `render_all_templates` interpolate raw values into `s|{{ key }}|value|g` without escaping `|`, `&`, or `\`.
     - `render_all_templates:142,160` sets `trap '...' EXIT RETURN` and clears `trap - EXIT RETURN`, clobbering any `EXIT` trap of the caller and referencing local `sed_script` on `EXIT` under `set -u`.
     - Non-atomic `>` writes into `STATE_DIR` trigger concurrent `FileView` / `uv.new_fs_event()` reloads mid-render.
  5. **Bug — Theme menu underscore mismatch (`hyprvibe-theme:272,319`)**: `format_theme_title` converts both `-` and `_` to spaces, while `cmd_set` converts spaces only to `-`, so any custom theme with `_` in its folder name fails to apply from Rofi menu.
  6. **Redundant/Inefficient Behavior**:
     - `hyprvibe-theme:137-139` deletes and re-copies all wallpapers into `~/Pictures/Current-Wallpapers/` on every theme switch instead of symlinking or pointing `wallpaper-changer.sh` directly at `$STATE_DIR/theme/backgrounds`.
     - `hyprvibe-theme` doesn't call `quickshell ipc call shell applyTheme` (relies on `FileView` watch on `colors.toml` + `shell.toml`, causing two partial reloads), while `nvim` reload sends `<Cmd>doautocmd FocusGained<CR>` in addition to `nvim`'s own `fs_event` watcher.
     - All 5 `themes/*/icons.theme` files are 0 bytes (`icons.theme` logic unused).
     - `foot.ini.tpl` only writes `[colors-dark]` even though `hyprvibe-theme` checks `mode == "light"`.
     - `shell.toml.tpl` retains orphaned `[launcher]` and `[image-picker]` sections not read by `ThemeColor.qml`.

---

## Phase 5: CachyOS Installer, Stow & Hardware Detection

- **Files**: [install.sh](file:///home/kunjan/HyprVibe/bin/install.sh), [common.sh](file:///home/kunjan/HyprVibe/bin/lib/common.sh), [hardware-detect.sh](file:///home/kunjan/HyprVibe/bin/lib/hardware-detect.sh), [install-packages.sh](file:///home/kunjan/HyprVibe/bin/install-packages.sh), [stow-dotfiles.sh](file:///home/kunjan/HyprVibe/bin/stow-dotfiles.sh), [theme-assets-installer.sh](file:///home/kunjan/HyprVibe/bin/theme-assets-installer.sh), [miscellaneous.sh](file:///home/kunjan/HyprVibe/bin/miscellaneous.sh), [github-auth.sh](file:///home/kunjan/HyprVibe/bin/github-auth.sh), [pacman.txt](file:///home/kunjan/HyprVibe/packages/pacman.txt), [yay.txt](file:///home/kunjan/HyprVibe/packages/yay.txt), [glitch.script](file:///home/kunjan/HyprVibe/plymouth-theme/glitch/glitch.script)
- **Findings**:
  1. **Critical Bug — `stow-dotfiles.sh:170` & `hardware-detect.sh:245` dirty git-tracked repo files**:
     - `stow-dotfiles.sh:170` overwrites git-tracked `dotfiles/dunst/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf` with a symlink to `~/.local/state/hyprvibe/current/dunst.conf`.
     - `hardware-detect.sh:245` overwrites git-tracked `dotfiles/sddm/hyprland.lua` with machine-specific monitor output/mode/scale.
     - On re-running `install.sh`, `git pull --rebase` (`install.sh:196`) fails due to uncommitted modifications!
  2. **Critical Bug — Missing runtime packages in `packages/pacman.txt` for fresh CachyOS installs**:
     - Missing `inotify-tools`: `PluginRegistry.qml:666` spawns `inotifywait`, restarting and failing every 1000ms in a tight loop if missing.
     - Missing `iw`: `hyprvibe-network-band` & `hyprvibe-network-status` rely on `iw dev ... link` (`pacman.txt` only has `wireless_tools`).
     - Missing `zenity`: `wallpaper-theming.sh` & `calculate-replaygain.sh` use `zenity` for file/directory pickers and progress bars.
     - Missing explicit `python-dbus` & `python-gobject`: required by `hyprvibe-bluetooth-pair`.
     - Conflicting/bloated packages: both `dunst` and `mako`, both `polkit-gnome` and `polkit-kde-agent`, full KDE Plasma stack (`plasma-workspace`, `kwin`, `kscreenlocker`, `breeze`, etc.), `grub` + `cachyos-grub-theme` (even if fresh CachyOS uses `systemd-boot` or `limine`), `cachyos-plymouth-theme` alongside custom `glitch` theme.
  3. **Critical Bug — Stow directory folding breaks GTK CSS `@import` & Flatpak & pollutes repo**:
     - `stow-dotfiles.sh:184` runs `stow` without `--no-folding`. Packages with single directories (`gtk-3.0`, `gtk-4.0`, `mpv`) fold as directory symlinks into `~/HyprVibe/dotfiles/...`.
     - Consequently, relative `@import "../../.local/state/hyprvibe/current/gtk.css"` breaks if any parser resolves symlinks, AND `miscellaneous.sh` (`configure_flatpak_themes`) mounts `~/.config/gtk-3.0:ro` without `~/.local/state/hyprvibe:ro` or `~/HyprVibe/dotfiles/gtk-*`, breaking Flatpak GTK theming completely.
     - `chromium/flags.txt` is never stowed/copied anywhere.
     - `~/.tmux/plugins/tpm` (`tmux.conf:25`) is never cloned/installed by any script.
  4. **Critical Hardware Detection Gaps (`hardware-detect.sh`, `install-packages.sh`, `miscellaneous.sh`)**:
     - **Single-monitor truncation (`hardware-detect.sh:117`)**: `detect_monitor_info` breaks on the first connected DRM connector and writes `output = ""` global fallback with the first monitor's `scale`, blowing up 1080p secondary monitors when primary is HiDPI (e.g., 1.8x).
     - **Refresh rate mismatch (`hardware-detect.sh:22`)**: `hyprctl` branch grabs max `@Hz` across *all* `availableModes`, not matching `${width}x${height}@`.
     - **EDID bugs (`hardware-detect.sh:78-98`)**:
       - `od -An -N23 -j21` reads 23 bytes instead of 2 (`-N2 -j21`).
       - Does not guard `h_cm == 0` (EDID 1.4 aspect-ratio encoding), miscomputing DPI.
       - Bit-depth check on EDID byte 20 skips EDID version (`byte 19 >= 4`) and digital flag (`bit 7`), risking false `bitdepth = 10` on legacy panels.
     - **GPU/Drivers (`install-packages.sh` & `miscellaneous.sh`)**:
       - `pacman.txt` forces Intel (`vulkan-intel`, `intel-media-driver`), AMD (`vulkan-radeon`, `xf86-video-amdgpu`), and Nouveau (`vulkan-nouveau`, `xf86-video-nouveau`) onto every machine regardless of GPU; no NVIDIA proprietary/open driver detection (`chwd` / `nvidia-smi` / PCI vendor `10de`), no laptop-vs-desktop filtering (`power-profiles-daemon`, `brightnessctl`, battery scripts), no bootloader detection (`grub` vs `systemd-boot` vs `limine`) when configuring Plymouth `splash` kernel cmdline or `mkinitcpio.conf` `plymouth` hook.
       - `detect_gpu_driver` in `miscellaneous.sh:161` returns only the first GPU on hybrid systems (`iGPU + dGPU`) and leaves trailing whitespace in `MODULES=(amdgpu )` when `MODULES=()` was empty; `miscellaneous.sh` never adds `plymouth` hook to `mkinitcpio.conf` or `splash` to bootloader config.
  5. **Security & UX Issues in Installer**:
     - `theme-assets-installer.sh:224-225` `chown`s and `chmod 775`s the ENTIRE `/usr/share/sddm/themes/hyprvibe/` (including `Main.qml` executed by SDDM greeter) to the normal user instead of only writable `assets/` and `theme.conf`.
     - `github-auth.sh:44-50` disables `stty echo` without `INT`/`TERM` trap; `write_ssh_config` overwrites `~/.ssh/config` `Host github.com` to `~/.ssh/id_ed25519` unconditionally; requires `ssh-agent` (`AddKeysToAgent yes`), which is never started in `autostart.lua` or `miscellaneous.sh`.
     - `install.sh:120` `tee` process substitution combined with `>/dev/tty 2>&1` in `install-packages.sh` drops `pacman`/`yay` output from `~/hyprvibe-log.txt`.
     - Missing `~/.local/bin` in session `PATH` (`environment.lua` / `environment.d`): breaks all 12 Quickshell `.local/bin/hyprvibe-*` helpers and `~/.local/bin/btop` on fresh SDDM -> Hyprland logins.

---

## Phase 6: Holistic Cross-File Synthesis & Remediation Blueprint

### 6.1 Cross-Cutting Root Causes
1. **Hyprland-Lua vs `hyprctl` Protocol Confusion**:
   - `binds.lua:73-74` (`hl.dsp.dpms`), `Workspaces.qml:40` (`hl.dsp.focus`), and `power-menu.sh:27` (`hl.dsp.exit`) pass Lua syntax to `hyprctl dispatch` (requires raw dispatchers like `dpms off`, `workspace N`, `exit`, or `Hyprland.dispatch()` in QML).
   - `toggle-refresh.sh:30` and `power-profiles.sh:55` query `hyprctl getoption misc.vrr -j` instead of `misc:vrr`, breaking high-refresh/VRR restoration permanently.
2. **Stow Architecture & Repo-Mutation Hazards**:
   - `stow-dotfiles.sh` runs without `--no-folding`, and `stow-dotfiles.sh:170` (`dunst`), `hardware-detect.sh:245` (`sddm/hyprland.lua`), `llama-server.sh:138`, and `sd-server.sh:95` write directly into git-tracked paths. This dirties git on normal usage and causes `install.sh`'s `git pull --rebase` to fail on re-runs.
   - Directory folding on `gtk-3.0/` & `gtk-4.0/` puts relative `@import "../../.local/state/..."` at risk and breaks Flatpak theming (`miscellaneous.sh:242-243` lacks `--filesystem=~/.local/state/hyprvibe:ro`).
3. **Missing Session `PATH` & Undeclared Runtime Dependencies**:
   - `~/.local/bin` is exported only in `.zshrc`, not in `environment.lua` or `~/.config/environment.d/`. SDDM -> Hyprland -> Quickshell panels call all 12 `hyprvibe-*` helpers and `btop` wrapper via bare names.
   - `packages/pacman.txt` is missing `inotify-tools`, `iw`, `zenity`, `python-dbus`, `python-gobject`, while bundling conflicting/bloated KDE Plasma, `mako`+`dunst`, `polkit-gnome`+`polkit-kde-agent`, and hardcoded all-vendor GPU/bootloader packages (`grub`, `amd-ucode`, `vulkan-intel`, `vulkan-radeon`, `xf86-video-nouveau`).
4. **Hardware-Adaptive Gaps for Varying CachyOS Machines**:
   - **Displays (`hardware-detect.sh`, `hyprlock.conf`, `sddm/hyprland.lua`)**: Single-monitor truncation (`break`), wrong `availableModes` Hz matching without resolution filter, EDID `od -N23` / missing `h_cm == 0` / EDID 1.4 bpc checks, global `output = ""` inheriting primary HiDPI scale onto secondary 1080p monitors, and `hyprlock.conf:38` fixed `-560` vertical offset colliding on 1080p displays.
   - **GPUs (`install-packages.sh`, `miscellaneous.sh`, `screen-record.sh`, `llama-server.sh`, `sd-server.sh`)**: No NVIDIA/AMD/Intel/hybrid GPU/VRAM detection; `screen-record.sh` lacks `-o <focused_output>` for multi-monitor `wf-recorder` and trusts `vainfo` exit 0 without verifying H.264 encode entrypoint or `--device`.
   - **Laptop/Power (`Backlight.qml`, `PowerProfile.qml`, `battery.sh`, `hyprvibe-battery-status`, `battery-conservation.sh`)**: Desktops without backlight/PPD keep polling and showing dummy UI; battery scripts miss `CMB*` batteries and `battery-conservation.sh` supports only Lenovo IdeaPad instead of generic `charge_control_end_threshold`.
   - **Bootloader/Plymouth (`miscellaneous.sh`)**: Doesn't add `plymouth` hook to `mkinitcpio.conf` `HOOKS`, handles only single GPU in `MODULES`, and doesn't configure `quiet splash` across `limine` / `systemd-boot` / `grub`.

---

### 6.2 Prioritized Fix & Improvement Matrix

#### Priority 0 — Broken Functionality & Fresh-Install Blockers
1. **Fix `rmpc/config.ron:210`**: Remove stray trailing `}`.
2. **Fix `hyprctl` protocol calls**:
   - `binds.lua:73-74` -> `hl.dsp.dpms("off")` / `hl.dsp.dpms("on")` (or `hyprctl dispatch dpms off/on`).
   - `Workspaces.qml:40` -> `Hyprland.dispatch("workspace " + id)`.
   - `power-menu.sh:27` -> `hyprctl dispatch exit`.
   - `toggle-refresh.sh:30` & `power-profiles.sh:55` -> `hyprctl getoption misc:vrr -j`.
3. **Fix session `PATH`**: Export `$HOME/.local/bin` in `environment.lua` (and/or `~/.config/environment.d/10-hyprvibe.conf`).
4. **Fix `packages/pacman.txt` + dynamic hardware package selection (`install-packages.sh`)**:
   - Add `inotify-tools`, `iw`, `zenity`, `python-dbus`, `python-gobject`, `edid-decode`.
   - Split `packages/pacman.txt` into clean core HyprVibe packages (strip KDE Plasma, `mako`, `polkit-gnome`, hardcoded `grub`, `cachyos-plymouth-theme`, `xf86-video-*`) + hardware modules selected dynamically via `lspci`/`chwd` (CPU microcode, AMD/Intel/NVIDIA GPU packages, laptop power/backlight tools).
5. **Eliminate repo-dirtying mutations & Stow folding**:
   - Remove `00-hyprvibe-theme.conf` from git tracking (or load `~/.local/state/hyprvibe/current/dunst.conf` via `dunst -conf` / non-tracked drop-in created outside repo) and generate `/usr/share/sddm/hyprland.lua` from a `templates/sddm/hyprland.lua.template` instead of overwriting `dotfiles/sddm/hyprland.lua`.
   - Move mutable state for `llama-server.sh` and `sd-server.sh` into `~/.local/state/{llama,sd}-server/*.conf` (leaving stowed `.config/*.conf` as read-only defaults).
   - Run `stow --no-folding -t "$USER_HOME" "${PACKAGES[@]}"` and switch `gtk.css` / `waybar/style.css` `@import` + Flatpak overrides (`--filesystem=~/.local/state/hyprvibe:ro`) so symlink canonicalization never breaks CSS imports.
6. **Fix Quickshell panel blockers**:
   - `network/Panel.qml:515`: Replace nonexistent `hyprvibe-launch-floating-terminal-with-presentation` with `foot` floating launcher (matching helpers pattern); add `onExited` to `enterpriseConnect`; bind line 1745 to `row.isFailed ? root.failureReason : ...`.
   - `audio/Panel.qml:621`: Replace `root.allMuted` with `!root.anyAudible`.
   - `bluetooth/Panel.qml:126` vs `Model.js:145`: Align `visibleSections` and `sectionVisible` on `!root.scanning`; clear `pendingActions` on panel close.
   - `hyprvibe-network-status:138`: Guard `speed` sysfs read with `|| true` (`< .../speed` fails with `EINVAL` on virtual NICs) and handle LAN-only routing when `1.1.1.1` unreachable.
7. **Fix `sd-server.sh:614-620`**: Renumber menu options so `Restart` and `Open Generated Images Folder` don't both use `3)`, wire `find_models`/`apply_model_defaults` into a model selector, fix duplicate print and `flux_*.png` prefix.

#### Priority 1 — Hardware Detection, Security & Reliability
1. **Multi-monitor & accurate EDID detection (`hardware-detect.sh`)**:
   - Iterate **all** connected DRM outputs (don't `break` after first), generate per-output `hl.monitor(...)` rules with per-display scale/mode/refresh, and filter `availableModes` by `${width}x${height}@` in Hyprland JSON path.
   - Fix `od -An -N2 -j21`, verify `w_cm > 0 && h_cm > 0`, and check EDID revision (`>= 4`) + digital flag (`bit 7`) before enabling `bitdepth = 10`.
   - Make `screen-record.sh` pass `-o <focused_output>` to `wf-recorder`, verify H.264 VAAPI encode via `ffmpeg` (not bare `vainfo`), and wait for `wf-recorder` PID exit before clearing `$PIDFILE`.
   - Make `toggle-refresh.sh` & `power-profiles.sh` target the focused/internal monitor, avoid forcing `bitdepth = 10` blindly, and restore VRR/max Hz when leaving `power-saver`.
2. **Dynamic Laptop/Desktop Capabilities**:
   - Hide `Backlight.qml` when `/sys/class/backlight/*` is empty; gate `PowerProfile.qml` & `power-profiles.sh` on `powerprofilesctl`/D-Bus availability.
   - Support both `BAT*` and `CMB*` batteries (`type == Battery && scope != Device`) in `battery.sh` & `hyprvibe-battery-status`.
   - Extend `battery-conservation.sh` to support generic `/sys/class/power_supply/*/charge_control_end_threshold` alongside Lenovo `ideapad_acpi`.
3. **Security & Hardening**:
   - `theme-assets-installer.sh`: Keep `/usr/share/sddm/themes/hyprvibe/Main.qml` root-owned `0644`; only grant user write access to `theme.conf` and `assets/` (or update via polkit/sudo helper in `hyprvibe-theme`).
   - `hypridle.conf`: Invoke `hyprlock` + DPMS off on idle timeout (or keep `madsnake` before locking with `hyprlock`) so idle actually locks the session.
   - `hyprvibe-dns`: Write `/etc/systemd/resolved.conf.d/20-hyprvibe-dns.conf` drop-in instead of overwriting `/etc/systemd/resolved.conf`, and avoid permanently mutating individual NM connection profiles.
   - `github-auth.sh`: Add `trap 'stty echo </dev/tty' INT TERM` around `read_secret_from_tty`; avoid clobbering existing GitHub SSH keys/config blocks unless requested; wire `ssh-agent` or `systemd` user unit if using passphrased keys.
4. **Bootloader/Plymouth (`miscellaneous.sh`)**:
   - Add `plymouth` hook to `/etc/mkinitcpio.conf` `HOOKS` (after `base udev`/`systemd`), include all detected DRM GPU drivers in `MODULES`, and detect `limine`/`systemd-boot`/`grub` to append `quiet splash` safely.
   - Install `tmux` TPM (`~/.tmux/plugins/tpm`) and `chromium/flags.txt` (`~/.config/chromium-flags.txt`), or remove unused entries.

#### Priority 2 — Correctness Polish, Theme Engine & Efficiency
1. **Theme Engine (`hyprvibe-theme`, `theme-engine.sh`)**:
   - Use `readlink -f` for `SCRIPT_DIR`; handle underscore themes in `cmd_menu` (`mapfile`/associative lookup instead of lossy title round-trip); escape sed replacement metacharacters (`|`, `&`, `\`); remove caller-clobbering `EXIT` trap inside `render_all_templates`; render to temp dir and atomically swap/copy into `STATE_DIR` to eliminate partial-read races.
   - Replace wallpaper copy-delete churn with symlink/pointing `wallpaper-changer.sh` directly to `$STATE_DIR/theme/backgrounds`.
   - Call `quickshell ipc call shell applyTheme` once (or rely strictly on single watcher) and remove duplicate Neovim `doautocmd FocusGained`.
   - Delete or populate 0-byte `icons.theme` files and remove orphaned `[launcher]`/`[image-picker]` sections from `shell.toml.tpl`.
2. **UI & Config Polish**:
   - `hyprlock.conf`: Use percentage/relative layout (`position = 0, -28%` or center-relative offsets) so 1080p/1440p/4K screens never overlap.
   - `sddm/Main.qml`: Replace `shakeAnim` `x` animation on anchored `inputContainer` with `Translate` transform; respect `RememberLastSession` in `SessionSelect.qml`.
   - `ThemeColor.qml`: Wrap `pick(...)` color tokens in `flatColor(...)` so theme role names work uniformly; sync `Style.qml` fallback `fontBaseSize` (`14` vs `12`).
   - `Bar.qml`: Honor `config.position` and `ThemeColor.bar.background` alpha; add `margins` animations for all 4 edges; move bar polling (`Cpu`, `Memory`, `Media`, `Backlight`, `PowerProfile`) into shared singletons/services so multi-monitor doesn't spawn N× processes; use `Mpris` in `Media.qml` instead of polling `rmpc` every 1.5s.
   - `Button.qml` & `CursorSurface.qml`: Respect `Border.controlSpec(...)` from `shell.toml` instead of hardcoding `Border.flat(...)`; guard `PanelSlider.qml` `track.width > 0`.
   - `nvim`: Replace `lualine.setup()` with `lualine.refresh()`; debounce `fs_event` and skip `vim.cmd.colorscheme` when target colorscheme is already active; drop fake `dir = "~/.config/nvim"` plugin spec; enable `allow-passthrough on` in `tmux.conf`.
   - `.zshrc`: Quote `"${(s.:.)LS_COLORS}"`, remove duplicate `hist_ignore_all_dups`, use `compinit -C` / `fd` if present, avoid blocking synchronous `git clone` offline.
   - **Extract shared floating-foot helper launcher** (`bin/lib/helper-window.sh`) to eliminate 6× duplicated 25-line boilerplate across `bin/helpers/*.sh`, reuse a single static class rule in `rules.lua` (stopping runtime rule leaks), and safely quote args.
   - Remove/archive legacy `dotfiles/waybar/` if unused, and fix `binds.lua:22` hardcoded `~/HyprVibe` path.
