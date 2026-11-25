# HyprVibe Correctness, Efficiency & Installer Remediation Plan

> **Companion to:** [PROJECT_ANALYSIS.md](file:///home/kunjan/HyprVibe/PROJECT_ANALYSIS.md)
> **Constraint:** No code has been changed yet. Phases **A–H** are modular so you can choose which phase(s) to execute one by one.

---

## 1. Empirical Verification Summary (Checking Claims vs Live CachyOS System)

Before locking in this plan, every questionable finding was verified against your live system (`Hyprland 0.57.2`, `/usr/share/hypr/stubs/hl.meta.lua`, live symlinks, Flatpak overrides, and `git ls-files`):

1. **Hyprland 0.57.2 Native Lua Syntax (`hl.dsp.*` & `misc.vrr`)**:
   - **Confirmed working (False alarm corrected):** Your live Hyprland runs in Lua mode (`hyprland.lua`). Both `hyprctl getoption misc.vrr -j` and `misc:vrr` work, and `hyprctl dispatch 'hl.dsp.exit()'` ([power-menu.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/power-menu.sh#L27)) and `hyprctl dispatch 'hl.dsp.focus({ workspace = "1" })'` ([Workspaces.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Workspaces.qml#L40)) **are valid Hyprland 0.57 Lua syntax** — we will **keep** them intact.
   - **Still needs fixing in `binds.lua:73-74`:** Official Hyprland Lua docs specify table arguments `hl.dsp.dpms({ action = "off" })` / `{ action = "on" }` rather than bare `"off"` strings, and inside `binds.lua` we can call Lua dispatchers/timers directly (or use the exact table signature).
   - **Why `Performance` mode didn't restore 120Hz VRR:** [power-profiles.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/power-profiles.sh#L43-L68) lowers refresh rate to `60Hz` + `vrr = 0` on `--power-saver`, but `--performance` never restores max/120Hz VRR.
2. **Dunst `00-hyprvibe-theme.conf` (Why it works on your PC, yet breaks on new clones/users)**:
   - **Verified with `git ls-files -s`:** [00-hyprvibe-theme.conf](file:///home/kunjan/HyprVibe/dotfiles/dunst/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf) was committed into git as a symlink pointing literally to `/home/kunjan/.local/state/hyprvibe/current/dunst.conf`. That is why Dunst themes live on your PC without appearing dirty in `git status`.
   - **Why it is still a bug:** Anyone installing on a different username (`!= kunjan`) has a broken symlink, and [stow-dotfiles.sh](file:///home/kunjan/HyprVibe/bin/stow-dotfiles.sh#L170) overwrites that git-tracked symlink inside the repo, dirtying git and blocking `git pull --rebase` on re-runs.
3. **GTK CSS `@import` & Thunar (Why Thunar works, yet Flatpak & repo cleanliness fail)**:
   - **Verified on live system:** `~/.config/gtk-3.0` is a folded directory symlink into `~/HyprVibe/dotfiles/gtk-3.0/.config/gtk-3.0`. Native Thunar resolves `~/.config/gtk-3.0/gtk.css` logically so `@import "../../.local/state/..."` works — **however**:
     - App-created files (`bookmarks`, `gtk-4.0/assets/`) leak right into the repo folder (needing `.gitignore` workarounds).
     - `~/.local/share/flatpak/overrides/global` mounts `~/.config/gtk-3.0:ro` and `~/.config/gtk-4.0:ro`, **without** `~/.local/state/hyprvibe:ro`, so **Flatpak GTK apps cannot read your HyprVibe dynamic theme colors**.
4. **SDDM Repo Pollution & Security Permissions (Items #1 & #5 from Section 9 — Verified live!)**:
   - **Item #1 (Git dirtying):** [hardware-detect.sh](file:///home/kunjan/HyprVibe/bin/lib/hardware-detect.sh#L245) overwrites git-tracked [dotfiles/sddm/hyprland.lua](file:///home/kunjan/HyprVibe/dotfiles/sddm/hyprland.lua). On any PC with a different monitor/scale, that dirties git and causes [install.sh](file:///home/kunjan/HyprVibe/bin/install.sh#L196)'s `git pull --rebase` to fail on future updates.
   - **Item #5 (Security & Logging):**
     - On your live system, `/usr/share/sddm/themes/hyprvibe/Main.qml` is currently owned by `kunjan` with permissions `775` ([theme-assets-installer.sh](file:///home/kunjan/HyprVibe/bin/theme-assets-installer.sh#L224-L225)). Because SDDM runs `Main.qml` as the privileged login greeter UI, only `theme.conf` and `assets/` should be user-writable — `Main.qml` should stay `root`-owned (`644`).
     - In [install-packages.sh](file:///home/kunjan/HyprVibe/bin/install-packages.sh#L37), `>/dev/tty 2>&1` bypasses [install.sh](file:///home/kunjan/HyprVibe/bin/install.sh#L120)'s `tee` logger, so `pacman`/`yay` errors vanish from `~/hyprvibe-log.txt`.
     - [github-auth.sh](file:///home/kunjan/HyprVibe/bin/github-auth.sh#L44-L50) disables `stty -echo` without a `Ctrl+C` (`INT`/`TERM`) cleanup trap.
5. **Wayland `ext-session-lock-v1`, `hypridle` & OLED Blanking (Verified `hypridle 0.1.8` supports `condition_cmd`):**
   - Because `hyprlock` uses Wayland `ext-session-lock-v1`, `madsnake` stays for unlocked idle (`timeout = 60`), while manual locking runs `hyprlock`.
   - `/usr/bin/hypridle` (`0.1.8-2.1`) supports `condition_cmd` + `condition_retry`, and `theme.lua` already enables `key_press_enables_dpms = true` & `mouse_move_enables_dpms = true`. So after 15s idle while `hyprlock` is active, DPMS turns your OLED display **completely off** (zero pixel wear), and moving mouse/pressing a key wakes directly back to `hyprlock`.
6. **Live Runtime Package Gap (`inotify-tools`)**:
   - Confirmed on your system: `which inotifywait` fails (`inotify-tools` is not installed), so Quickshell's [PluginRegistry.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/services/PluginRegistry.qml#L664-L688) respawns a failing `inotifywait` process every `1000ms` forever.
7. **Symlinked Wallpapers & `awww` (`wallpaper-changer.sh`)**:
   - Confirmed critical check in [wallpaper-changer.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/wallpaper-changer.sh#L53): `find "$WALL_DIR" -maxdepth 1 -type f` **ignores symlinks** unless `-L` (`find -L`) is passed! Fixing that makes symlinked theme wallpapers work cleanly with `awww`.

---

## 2. Agreed User Requirements & Boundaries

- **Clone Path:** Must stay fixed at `~/HyprVibe`. `install.sh` must refuse to proceed if the user manually cloned the repo to a different directory instead of `~/HyprVibe`.
- **Keep As-Is:**
  - `hyprsunset.conf` (`00:00 -> 3700K` permanent warm color temperature)
  - `autostart.lua` (`localsend --hidden &`)
  - `.zshrc` personal helper functions (`cpg`, `rustpg`, `pypg`)
  - Neovim `tokyonight.lua` plugin file (keep intact as LazyVim fallback dependency; keep full Markdown rendering intact)
  - `themes/*/icons.theme` (keep 0-byte placeholders; `YAMIS` remains active until Omarchy dynamic SVG icons stabilize)
  - `bin/helpers/update-package-list.sh` behavior (always snapshots your full `pacman -Qneq` and `pacman -Qmeq` setup into `packages/*.txt`)
  - Keep AI server configs (`llama-server`, `sd-server`) in repo for future hardware expansion while fixing their bugs & git pollution.
- **Explicit Removals:**
  - Remove `dotfiles/waybar/` completely.
  - Remove DNS management from Quickshell's Network panel (`DNS PROVIDER` row) and delete `hyprvibe-dns` (and dead DNS UI references).
  - Remove `dotfiles/chromium/` (`flags.txt`) and its manual throttle-disable flags.
- **Specific Additions/Upgrades:**
  - **OLED Protection (`hypridle.conf`):** Keep current `madsnake` idle trigger (`timeout = 60` when unlocked) and manual `hyprlock` trigger (`SUPER + M` -> Lock), AND add a `15s` lock-only DPMS listener (`condition_cmd = pgrep -x hyprlock`, `condition_retry = 2`) that completely blanks the OLED display after 15s locked — waking back to `hyprlock` on mouse/key activity.
  - Power Profiles (`performance`): Restore detected max/120Hz + VRR **once** when switching to `Performance`, without locking the user out of manually switching back to 60Hz afterwards.
  - `rename-theme-wallpapers.sh`: Strict pre-flight guardrail — abort with an error before renaming *anything* if non-image files exist inside `backgrounds/`.
  - `bin/helpers/*`: Keep unified floating-window visual design language; share common launcher boilerplate without repeating it across 7 files; show clear errors; pause interactive helpers at exit/error and close **only when `q` is pressed** (while preserving `--headless` / `--yes` behavior).
  - `install.sh` suite: Visually upgraded, professional interactive installer (pre-flight hardware/plan summary, step counters, clean prompts, reliable logging, dynamic hardware-aware package/driver/display/bootloader handling).

---

## 3. Execution Roadmap (Pick One Phase at a Time)

### Phase A — Core Hyprland, Shell, GTK & Neovim Fixes
**What breaks right now:** Lid switch uses wrong `hl.dsp.dpms` shape, `hyprlock` clock overlaps on 1080p displays, `.zshrc` tab-completion colors don't expand, `tmux` blocks Neovim terminal color sync, Neovim reloads unthrottled and breaks `lualine` formatting on theme change, legacy Waybar files still sit in repo.

- **Changes:**
  1. [binds.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/binds.lua): Fix lid-switch DPMS (`hl.dsp.dpms({ action = "off" })` / `{ action = "on" }` using `hl.timer` / `hl.dispatch`), clean `SUPER + B` to launch plain `chromium` (without unused background-battery flags), replace `date +%F_%T` with `date +%Y-%m-%d_%H-%M-%S`, pipe screenshots safely via `tee ... | wl-copy` (guarding cancelled `slurp`). Keep `~/HyprVibe/bin/hyprvibe-theme menu` per fixed path rule.
  2. [rules.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/rules.lua), [autostart.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/autostart.lua), [theme.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/theme.lua), [environment.lua](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/config/environment.lua):
     - Remove explicit `code` (`0.8 / 1.0`) rule from `rules.lua` (let VS Code inherit global rules); keep `localsend --hidden &`; keep `autostart.lua` clean; quote `"$bin"` check in `theme.lua:107`; export `~/.local/bin` in `environment.lua` so GUI launches always find `.local/bin` regardless of display manager.
  3. [hyprlock.conf](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/hyprlock.conf): Switch fixed `position = 0, -560` to screen-relative percentages (`valign = center`, proportional offsets) so 1080p, 1440p, and 4K displays align cleanly.
  4. [hypridle.conf](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/hypridle.conf):
     - Keep `madsnake` at `timeout = 60` when unlocked (`condition_cmd = ! pgrep -x hyprlock >/dev/null` so hidden `madsnake` isn't spawned behind a lockscreen).
     - Add OLED lock-blanking listener: `timeout = 15`, `condition_cmd = pgrep -x hyprlock >/dev/null`, `condition_retry = 2`, `on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'`, `on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'`.
     - Note: moving mouse or pressing any key turns OLED back on directly showing `hyprlock`.
  5. **Remove `dotfiles/waybar/` & `dotfiles/chromium/`** (and unused `templates/themed/waybar.css.tpl` if no script consumes it; verify references first).
  6. [gtk-4.0/gtk-dark.css](file:///home/kunjan/HyprVibe/dotfiles/gtk-4.0/.config/gtk-4.0/gtk-dark.css) & [gtk-3.0/gtk.css](file:///home/kunjan/HyprVibe/dotfiles/gtk-3.0/.config/gtk-3.0/gtk.css): Sync fallback `@define-color` variables into `gtk-dark.css` and remove unused `.nemo-window *` selectors while keeping Thunar styling untouched.
  7. [config.ron](file:///home/kunjan/HyprVibe/dotfiles/rmpc/.config/rmpc/config.ron): Remove stray `}` at line 210 and fix awkward wrapped keybind lines.
  8. [.zshrc](file:///home/kunjan/HyprVibe/dotfiles/shell-config/.zshrc) & [tmux.conf](file:///home/kunjan/HyprVibe/dotfiles/tmux/.config/tmux/tmux.conf):
     - Double-quote `"${(s.:.)LS_COLORS}"` (with `dircolors` fallback), remove duplicate `setopt hist_ignore_all_dups`, quote `"$ZINIT_HOME"` + fail safely offline, use cached `compinit -C` when fresh, use `fd` for `fzf` if installed, keep `cpg`/`rustpg`/`pypg`.
     - Add `set -g allow-passthrough on` to `tmux.conf`, fix `prefix + c` comment, and safely guard `tpm` execution if not yet installed.
  9. **Neovim** ([theme.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/config/theme.lua), [theme-sync.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/plugins/theme-sync.lua), [render-markdown.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/plugins/render-markdown.lua), [keymaps.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/config/keymaps.lua)):
     - Replace `require("lualine").setup()` with `require("lualine").refresh()` so statusline config stays intact.
     - Remove redundant startup reload & `dir = "~/.config/nvim"` fake plugin (move autocmds/watcher cleanly into [autocmds.lua](file:///home/kunjan/HyprVibe/dotfiles/nvim/.config/nvim/lua/config/autocmds.lua)), skip `colorscheme` calls if active theme matches `theme.name` on disk, debounce `uv.new_fs_event()` (~100ms timer), create watch dir if missing, guard OSC 11/111 stdout writes behind `#vim.api.list_uis() > 0`.
     - Switch `render-markdown.lua` dependency from full `nvim-mini/mini.nvim` to `nvim-mini/mini.icons` (identical rendering, lighter dependency), keep `tokyonight.lua` untouched, and refresh `_term_root` cleanly on `DirChanged`.
- **Safe Verification:** Parse `rmpc` RON syntax (`python`/`rmpc --version` or RON parser check), `luac -p` syntax check on all `.lua` files, `zsh -n ~/.zshrc`, `nvim --headless +qa` startup/check without side effects.

---

### Phase B — Quickshell Bar, Core UI, Wi-Fi & Bluetooth Polish + DNS Removal
**What breaks right now:** Clicking Custom DNS runs a missing binary, DNS clutters Network panel, Enterprise Wi-Fi hangs on `"Connecting…"` when failing, all Wi-Fi failures say `"Wrong password"`, Audio mute tooltip checks undefined `root.allMuted`, Bluetooth cursor enters hidden rows while scanning and fails to clear cancelled pair actions, Quickshell polls missing backlight/PPD hardware and multiplies per-monitor processes, virtual NICs crash `hyprvibe-network-status`, `hyprvibe-bluetooth-pair` blocks its own timeout loop.

- **Changes:**
  1. **Remove DNS stack**: Strip DNS UI row/pills/state/focus zone (`header <-> band <-> wifi`) from [network/Panel.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/network/Panel.qml) & [network/Model.js](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/network/Model.js), and remove [hyprvibe-dns](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.local/bin/hyprvibe-dns) (plus check stale `omarchy-dns` symlink).
  2. **Polish Wi-Fi (`network/Panel.qml`)**: Add `onExited` to `enterpriseConnect` so failed 802.1X attempts report failure immediately; render `root.failureReason` cleanly instead of hardcoded `"Wrong password"`; verify clean focus fallback on empty scan / disconnect.
  3. **Polish Bluetooth (`bluetooth/Panel.qml`, `Model.js`, `hyprvibe-bluetooth-pair`, `hyprvibe-bluetooth-device`)**:
     - Sync `Model.visibleSections` with `!root.scanning` so keyboard cursor matches visible UI rows; clear `pendingActions` on close/abort (`onOpenedChanged`).
     - Avoid firing redundant concurrent BlueZ D-Bus + `bluetoothctl scan on` calls.
     - Rewrite `hyprvibe-bluetooth-pair` stdin prompts using non-blocking GLib `io_add_watch` so timeouts never stall, and emit `RESULT error` if `dev.Connect()` fails; handle controller/error checks properly in `hyprvibe-bluetooth-device`.
  4. **Audio, Network Status & Battery Helpers**:
     - [audio/Panel.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/panels/audio/Panel.qml): Replace `root.allMuted` with `!root.anyAudible`.
     - [hyprvibe-network-status](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.local/bin/hyprvibe-network-status): Guard `cat /sys/class/net/$iface/speed` against `EINVAL` on virtual/USB NICs (`|| true`), handle LAN-only routing if `1.1.1.1` route probe fails.
     - [hyprvibe-battery-status](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.local/bin/hyprvibe-battery-status): Detect both `BAT*` and `CMB*` (`type == Battery && scope != Device`), handle full-charge display without blank `" ·  left · "`, avoid guessing IdeaPad charge threshold strictly from current percentage.
     - [hyprvibe-audio-input-set-default](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.local/bin/hyprvibe-audio-input-set-default): Add `timeout 2` protection matching output helper.
  5. **Core QML, Bar & Capability Awareness**:
     - [ThemeColor.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Commons/ThemeColor.qml) & [Style.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Commons/Style.qml): Wrap remaining 12 un-wrapped `pick(...)` getters with `flatColor(...)`; align startup `fontBaseSize` fallback (`14`).
     - [shell.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/shell.qml): Deduplicate `shell.json` watcher, avoid overwriting Stow symlinks via `atomicWrites` (route user mutations or guard safely), avoid redundant double theme loads.
     - [Bar.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/Bar.qml), [Backlight.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Backlight.qml), [PowerProfile.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/PowerProfile.qml), [Cpu.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Cpu.qml), [Media.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/plugins/bar/widgets/Media.qml):
       - Respect `config.position` & `[bar]` alpha from `ThemeColor`; animate all 4 bar margin edges; ensure `toggles/` dir exists. Keep `Workspaces.qml`'s verified `hl.dsp.focus` intact!
       - Auto-hide `Backlight.qml` when `/sys/class/backlight/*` is empty; gate `PowerProfile.qml` when `powerprofilesctl`/D-Bus daemon is absent; use `Mpris` / `cpufreq/scaling_cur_freq` and share singleton state across multi-monitor bars so N monitors don't run N× pollers or duplicate `IpcHandler`s.
       - [Button.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Ui/Button.qml), [CursorSurface.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Ui/CursorSurface.qml), [PanelSlider.qml](file:///home/kunjan/HyprVibe/dotfiles/quickshell/.config/quickshell/Ui/PanelSlider.qml): Honor `[controls]` theme border style and add `track.width > 0` guard.
- **Safe Verification:** `qmllint` / headless Quickshell check if available, `python3 -m py_compile` on `hyprvibe-bluetooth-pair`, bash `-n` & isolated unit tests (mocked sysfs/JSON) for `hyprvibe-*` scripts.

---

### Phase C — Hyprland Session Scripts & Symlinked Wallpaper Support
**What breaks right now:** Performance profile doesn't restore high refresh/VRR, refresh scripts hardcode monitor `0` and 10-bit depth, screen-recorder fails on multi-monitor setups and skips true H.264 encode probing, `wallpaper-changer.sh` skips symlinked images (`-type f`), `battery.sh` misses `CMB*` batteries. (Verified `power-menu.sh` `hl.dsp.exit()` works — keep untouched!)

- **Changes:**
  1. [power-profiles.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/power-profiles.sh) & [toggle-refresh.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/toggle-refresh.sh):
     - Target focused monitor dynamically instead of always `.[0]`; query `vrr` reliably via `jq -r '.int // empty'`.
     - Detect native max refresh rate (`@120` etc.) cleanly for that monitor's current resolution, and apply `bitdepth = 10` *only* if the display supports it (no blind forcing).
     - On `--performance`: set profile + trigger a **one-shot** switch to max Hz + `vrr = 2` (user can still hit `SUPER + R` afterwards to lock 60Hz manually!).
     - Gracefully handle missing `powerprofilesctl` on desktop installs.
  2. [screen-record.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/screen-record.sh): Pass `-o "$FOCUSED_OUTPUT"` to `wf-recorder`; verify `h264_vaapi` encoding directly with short `ffmpeg` probe on `"$render_node"` (catching decode-only GPUs & hybrid GPUs); wait for `wf-recorder` exit after `SIGINT` before removing `$PIDFILE`; show actual display resolution in notifications instead of hardcoded `1080p`.
  3. [wallpaper-changer.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/wallpaper-changer.sh): Change `find "$WALL_DIR" -maxdepth 1 -type f` -> **`find -L "$WALL_DIR" -maxdepth 1 -type f`** so symlinked wallpaper directories & files work seamlessly with `awww`; stop active `$SLEEP_PID` cleanly in `cleanup()`.
  4. [battery.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/battery.sh) & [clipboard-menu.sh](file:///home/kunjan/HyprVibe/dotfiles/hypr/.config/hypr/scripts/clipboard-menu.sh): Support `BAT*` and `CMB*` (`type == Battery && scope != Device`) in `battery.sh`; use `printf '%s\n'` in `clipboard-menu.sh`.
- **Safe Verification:** `bash -n` on all scripts + mocked `PATH` / `hyprctl` JSON test harness under `self_tests/` verifying multi-monitor JSON parsing and symlinked wallpaper discovery.

---

### Phase D — Helper Scripts Framework, Guardrails & AI/Battery Fixes
**What breaks right now:** 6 helpers repeat 25 lines of floating `foot` boilerplate & leak Hyprland window rules, errors vanish when windows close immediately, `rename-theme-wallpapers.sh` renames non-image files, `sd-server.sh` has duplicate `3)` menu options and dead model code, both AI helpers dirty git by writing into `~/.config/*.conf`, `battery-conservation.sh` supports only Lenovo IdeaPad.

- **Changes:**
  1. **Shared Helper UI & Launcher (`bin/lib/helper-ui.sh`)**:
     - Keep your exact visual design language (`HELPER_ICON  HELPER_TITLE`, clean indentation, `✅`/`❌`, 40% centered floating `foot`).
     - Deduplicate monitor sizing + floating spawn into one shared helper sourcing cleanly across all 7 `bin/helpers/*.sh` scripts; use safe shell-escaped argument forwarding (`printf '%q'`) and one reusable class rule (`rules.lua` matching `^hyprvibe-helper$` or fixed rule name) instead of leaking new runtime rules per launch.
     - Add unified error trap + `"Press 'q' to close..."` pause loop (`read -rsn1 key; [[ $key == [qQ] ]]`) for interactive runs so errors never vanish before you read them (while keeping `--headless` / `--yes` non-blocking).
  2. [rename-theme-wallpapers.sh](file:///home/kunjan/HyprVibe/bin/helpers/rename-theme-wallpapers.sh): Add **strict pre-flight validation** across all `themes/*/backgrounds/` before renaming a single file — if any non-image file exists (outside `.jpg/.jpeg/.png/.webp`), print all offending paths, show notification + `q`-to-close error pause, and abort with exit code 1.
  3. [wallpaper-theming.sh](file:///home/kunjan/HyprVibe/bin/helpers/wallpaper-theming.sh): Reject unknown `--palette` slugs instead of falling back to index `0`; check missing `--palette`/`--files` arguments safely; add `EXIT` cleanup trap for temp dir; output `lutgen` to a temp file before moving to final path so failures never create 0-byte images; use `readlink -f`; adopt shared UI + `q` close on error.
  4. [calculate-replaygain.sh](file:///home/kunjan/HyprVibe/bin/helpers/calculate-replaygain.sh): Adopt shared UI + `q` close on completion/errors (e.g., invalid directory, missing `rsgain`).
  5. [update-package-list.sh](file:///home/kunjan/HyprVibe/bin/helpers/update-package-list.sh): Keep exact `pacman -Qneq` / `-Qmeq` snapshotting behavior intact; adopt shared UI + `q`-to-close pause cleanly.
  6. [battery-conservation.sh](file:///home/kunjan/HyprVibe/bin/helpers/battery-conservation.sh) & [plugins/battery-conservation/install.sh](file:///home/kunjan/HyprVibe/plugins/battery-conservation/install.sh):
     - Detect Lenovo `ideapad_acpi/conservation_mode` **OR** standard kernel `/sys/class/power_supply/*/charge_control_end_threshold` (ThinkPad, ASUS, Framework, MSI, Dell).
     - Improve udev rule matching (`ACTION=="add"`, proper kernel syspath attributes for both `conservation_mode` and `charge_control_end_threshold`) and only call `sudo` when sysfs node is not already user-writable.
  7. [llama-server.sh](file:///home/kunjan/HyprVibe/bin/helpers/llama-server.sh) & [sd-server.sh](file:///home/kunjan/HyprVibe/bin/helpers/sd-server.sh):
     - Read repo-stowed defaults from `~/.config/{llama,sd}-server/*.conf` and persist all user edits/overrides strictly into `~/.local/state/hyprvibe/{llama,sd}-server.conf` (repo stays 100% clean!).
     - Fix `sd-server.sh` duplicate `3)` menu bug (renumber cleanly), wire dead `find_models`/`apply_model_defaults` into model picker, eliminate double generation banner, use active model slug in filenames, validate numeric `GUIDANCE`/`STEPS`/dimensions cleanly, move logs into `~/.local/state/hyprvibe/`, expand `~` in folder inputs, add missing CLI flag guards, and add optional GPU VRAM sanity hints for future hardware expansion.
- **Safe Verification:** `bash -n` across all helpers, isolated temp-dir tests verifying `rename-theme-wallpapers.sh` aborts cleanly without renames when a `.txt` file is present, and `sd-server.sh` menu / `llama-server.sh` config state isolation tests.

---

### Phase E — Theme Switching Engine & Symlinked Wallpapers
**What breaks right now:** Switching `~/Pictures/Current-Wallpapers/` copies/deletes gigabytes every switch, Dunst symlink inside git breaks on other usernames, SDDM skips updating if root-owned and mismatches `.png` -> `.jpg` extensions, `hyprvibe-theme` fails when symlinked, `sed` chokes on special chars (`|`, `&`, `\`), non-atomic writes race with watchers, `_` theme names fail from Rofi menu.

- **Changes:**
  1. [hyprvibe-theme](file:///home/kunjan/HyprVibe/bin/hyprvibe-theme):
     - Resolve `SCRIPT_DIR` via `readlink -f`.
     - Fix underscore `_` theme names in `cmd_menu` using direct row-index / map lookup instead of lossy title->hyphen reconstruction.
     - **Symlink wallpapers cleanly:** Instead of deleting & copying files into `~/Pictures/Current-Wallpapers/`, manage symlinks cleanly inside `~/Pictures/Current-Wallpapers/` (pointing to `${target_dir}/backgrounds/*`) — paired with `find -L` in Phase C's `wallpaper-changer.sh`.
     - Improve SDDM background handling (match actual format/extension or point `theme.conf` `background=assets/default-bg.<ext>` accurately while cleaning old `default-bg.*`, syncing into writable `assets/` and `theme.conf`).
     - Trigger Quickshell cleanly once and avoid double-reloading Neovim if `fs_event` already handles it (or rely on deduplicated Neovim `theme.name` check).
     - Keep `icons.theme` handling ready while leaving all 5 current 0-byte `icons.theme` files untouched.
  2. [theme-engine.sh](file:///home/kunjan/HyprVibe/bin/lib/theme-engine.sh):
     - Escape `\`, `&`, `|` in all `sed` replacement values before compiling template rules.
     - Remove caller-clobbering global `trap ... EXIT RETURN` inside `render_all_templates`.
     - Render all templates into a temp directory under `STATE_DIR` and atomically swap/update files so watchers never read partial files.
  3. [shell.toml.tpl](file:///home/kunjan/HyprVibe/templates/themed/shell.toml.tpl) & [foot.ini.tpl](file:///home/kunjan/HyprVibe/templates/themed/foot.ini.tpl): Remove dead `[launcher]`/`[image-picker]` keys from `shell.toml.tpl`; populate `[colors-light]` properly when `mode = "light"` in `foot.ini.tpl`.
  4. **Untrack Dunst git symlink**: `git rm --cached dotfiles/dunst/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf` (and `.gitignore` or remove file from repo) so `stow-dotfiles.sh` manages `~/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf` outside git.
- **Safe Verification:** Test `hyprvibe-theme` against a temporary `HOME` / `XDG_RUNTIME_DIR` sandbox checking underscore themes, symlinked wallpapers + `find -L`, `theme-engine.sh` special characters, and zero repo modifications.

---

### Phase F — SDDM Greeter & Template Separation
**What breaks right now:** Wrong-password shake animation fails (`x` vs `horizontalCenter`), session selector overrides `RememberLastSession`, `dotfiles/sddm/hyprland.lua` gets overwritten in git on every machine.

- **Changes:**
  1. [sddm/Main.qml](file:///home/kunjan/HyprVibe/dotfiles/sddm/themes/hyprvibe/Main.qml): Animate `Translate` transform on `inputContainer` instead of `x`.
  2. [SessionSelect.qml](file:///home/kunjan/HyprVibe/dotfiles/sddm/themes/hyprvibe/components/SessionSelect.qml): Cleanly prioritize Hyprland as initial default while respecting `RememberLastSession=true` (`model.lastIndex`) properly and fixing initial scroll positioning.
  3. **Move SDDM compositor config to template**: Add `templates/sddm/hyprland.lua.template` and stop `hardware-detect.sh` from modifying tracked `dotfiles/sddm/hyprland.lua` (write generated output directly to `/usr/share/sddm/hyprland.lua` via installer or gitignored staging dir).
- **Safe Verification:** `qmllint` on SDDM QML files and template substitution verification into temp file.

---

### Phase G — Hardware Detection, Stow & Package/Service Adaptation
**What breaks right now:** Multi-monitor setups get broken by `break` after first monitor + primary scale leak onto 1080p externals, EDID byte reads/checks are wrong (`-N23`, missing `h_cm == 0` / EDID 1.4 guards), `pacman.txt` misses `inotify-tools`/`iw`/`zenity`/`python-dbus`/`python-gobject` while forcing full KDE/conflicting agents/wrong GPU drivers onto varying PCs, `stow` lacks `--no-folding` breaking Flatpak themes, `miscellaneous.sh` misses `plymouth` hook and bootloader `quiet splash` across `grub`/`systemd-boot`/`limine`.

- **Changes:**
  1. [hardware-detect.sh](file:///home/kunjan/HyprVibe/bin/lib/hardware-detect.sh):
     - Enumerate **all** connected displays (remove single-monitor `break`) and write specific per-output `hl.monitor(...)` rules rather than pushing primary HiDPI scale into `output = ""`.
     - Filter `availableModes` strictly by `${width}x${height}@` in Hyprland JSON path.
     - Fix EDID reads (`od -An -N2 -j21`), guard `w_cm > 0 && h_cm > 0`, and check EDID rev `>= 4` + digital input bit 7 before enabling `bitdepth = 10`.
     - Generate `/usr/share/sddm/hyprland.lua` via template without touching tracked repo files.
  2. [stow-dotfiles.sh](file:///home/kunjan/HyprVibe/bin/stow-dotfiles.sh): Use `stow --no-folding -t "$USER_HOME" "${PACKAGES[@]}"` and create `~/.config/dunst/dunstrc.d/00-hyprvibe-theme.conf -> ~/.local/state/hyprvibe/current/dunst.conf` cleanly in `$USER_HOME` instead of inside `dotfiles/`.
  3. [install-packages.sh](file:///home/kunjan/HyprVibe/bin/install-packages.sh) & [pacman.txt](file:///home/kunjan/HyprVibe/packages/pacman.txt):
     - Ensure core runtime dependencies (`inotify-tools`, `iw`, `zenity`, `python-dbus`, `python-gobject`, `edid-decode`) are guaranteed in core requirements (and remember `update-package-list.sh` keeps full system snapshot — filter conflicts cleanly during install!).
     - Dynamically detect & filter during `install-packages.sh`:
       - **CPU:** `amd-ucode` vs `intel-ucode`, `ryzen_smu-dkms-git` only on AMD.
       - **GPU (`lspci` / CachyOS `chwd`):** Include only matching Intel / AMD / NVIDIA drivers (don't blindly install `xf86-video-nouveau`, `vulkan-nouveau`, `vulkan-intel`, `vulkan-radeon` on machines without those GPUs; detect NVIDIA `10de` cleanly!).
       - **Chassis (Laptop vs Desktop):** Skip `brightnessctl` / laptop battery/PPD assumptions when desktop lacks battery/backlight hardware.
       - **Conflict Resolution:** Avoid conflicting dual agents (`mako` vs `dunst`, `polkit-gnome` vs `polkit-kde-agent`, `cachyos-plymouth-theme` vs `glitch`, unneeded `grub` if target uses `systemd-boot` or `limine`).
  4. [miscellaneous.sh](file:///home/kunjan/HyprVibe/bin/miscellaneous.sh):
     - Support multi-GPU Early KMS modules (`amdgpu`, `i915`, `xe`) without leaving trailing space in `MODULES=(...)`.
     - Ensure `plymouth` hook exists in `/etc/mkinitcpio.conf` `HOOKS=(...)`, and detect bootloader (`grub`, `systemd-boot`, or `limine`) to safely ensure `quiet splash` (backed up cleanly before edits).
     - Add `flatpak override --user --filesystem="$HOME/.local/state/hyprvibe:ro"` so Flatpak GTK themes resolve cleanly.
     - Ensure `tmux` TPM (`~/.tmux/plugins/tpm`) is installed cleanly (no Chromium flags installed).
- **Safe Verification:** Dry-run hardware-detection & package-filtering tests simulating AMD laptop, Intel+NVIDIA hybrid laptop, and Desktop dual-monitor configurations without modifying host `/etc` or running `pacman`.

---

### Phase H — Security Hardening & Professional Installer TUI/UX
**What breaks right now:** Manual clones outside `~/HyprVibe` quietly duplicate repo into `~/HyprVibe`, SDDM QML theme script is user-writable (`775`), `github-auth.sh` leaks disabled terminal echo on `Ctrl+C`, `install-packages.sh` drops logs via `>/dev/tty`, terminal prompts feel plain/minimal.

- **Changes:**
  1. [install.sh](file:///home/kunjan/HyprVibe/bin/install.sh) & [common.sh](file:///home/kunjan/HyprVibe/bin/lib/common.sh):
     - **Strict repo path enforcement:** If invoked from a cloned HyprVibe repo outside `~/HyprVibe`, abort immediately with clear instructions to clone at `~/HyprVibe` instead of silently re-cloning.
     - **Fix log capture:** Route interactive `pacman`/`yay` runs through PTY/tee (`script` / logged TTY wrapper) so `~/hyprvibe-log.txt` records full install errors AND terminal prompts still work seamlessly.
     - **Professional Installer TUI/UX:** Add styled ASCII/box header, pre-flight system & hardware summary screen (OS, CPU, GPU, Displays, Chassis, Bootloader, Target dir, Log file) with explicit confirmation prompt before installing, unified progress indicators (`[1/8]`), clean summary dashboard at finish (installed components, any skipped optional items, log path, and clean reboot prompt).
  2. [theme-assets-installer.sh](file:///home/kunjan/HyprVibe/bin/theme-assets-installer.sh): Keep `/usr/share/sddm/themes/hyprvibe` (`Main.qml`, `components/`, `metadata.desktop`) **root-owned (`root:root`, `644`/`755`)**; set user write ownership **only** on `/usr/share/sddm/themes/hyprvibe/assets` and `theme.conf` so `hyprvibe-theme` can still dynamically sync themes safely.
  3. [github-auth.sh](file:///home/kunjan/HyprVibe/bin/github-auth.sh): Add `trap 'stty echo </dev/tty 2>/dev/null || true' INT TERM` inside `read_secret_from_tty`, prevent clobbering user's existing `Host github.com` entries unnecessarily, and document/enable `ssh-agent` handling cleanly.
- **Safe Verification:** `bash -n` on all installer scripts + simulated dry-run checks for path enforcement (`!= ~/HyprVibe`), logging capture, and SDDM permission boundaries.

---

## 4. Pro Architecture Roadmap (Recommended *After* Finishing Phases A–H)

Once Phases **A–H** are fixed and verified, optional larger structural upgrades to make HyprVibe look and behave like a production Linux project:

1. **Cleaner Directory Boundaries (`bin/` vs `dotfiles/`):** Separate provisioning/installer scripts (`install/`), runtime CLI commands (`bin/` on `PATH`), shared libraries (`lib/`), and Stow packages (`dotfiles/`).
2. **Systemd User Units for Session Daemons:** Replace fire-and-forget `&` background scripts in `autostart.lua` (`wallpaper-changer.sh`, `battery.sh`, optional `llama-server`) with `systemd --user` services for automatic restarts and unified `journalctl --user` logs.
3. **Structured Package Manifests + Personal Snapshot Separation:** Split monolithic `packages/pacman.txt` into modular lists (`core.txt`, `hyprland.txt`, `amd.txt`, `intel.txt`, `nvidia.txt`, `laptop.txt`, `apps.txt`) while keeping personal `update-package-list.sh` snapshots isolated cleanly.
4. **Automated CI & Linting (`self_tests/`):** Run `shellcheck`, `luac -p`, `qmllint`, and sandboxed `$HOME` tests automatically on commits/PRs (GitHub Actions + local test runner) plus a `hyprvibe doctor` command checking dependencies, symlinks, and permissions.
