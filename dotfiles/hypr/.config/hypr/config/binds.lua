local terminal = "foot"
local fileManager = "thunar"
local menu = "hyprvibe-dmenu --preset drun --toggle"
local mainMod = "SUPER"

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("madsnake"))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.fullscreen({ mode = 0 }))
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(menu), { submap_universal = true })
hl.bind(mainMod .. " + D", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/toggle-refresh.sh"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("chromium"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("foot --override=main.pad=0x0 --override=colors-dark.alpha=1.0 -e nvim"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("quickshell ipc call hyprvibe.bar toggle"))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd(os.getenv("HOME") .. "/hyprvibe/bin/hyprvibe-theme menu"), { submap_universal = true })
hl.bind(mainMod .. " + comma", hl.dsp.exec_cmd("quickshell ipc call hyprvibe.settings toggle"), { submap_universal = true })

hl.bind(
	"F12",
	hl.dsp.exec_cmd(
		[[mkdir -p ~/Pictures/Screenshots && geom=$(slurp) && grim -g "$geom" - | tee ~/Pictures/Screenshots/Screenshot-$(date +%Y-%m-%d_%H-%M-%S).png | wl-copy && notify-send "Screenshot" "Screenshot of the region taken" -t 1000]]
	),
	{ submap_universal = true }
)
hl.bind(
	"SHIFT + F12",
	hl.dsp.exec_cmd(
		[[mkdir -p ~/Pictures/Screenshots && grim - | tee ~/Pictures/Screenshots/Screenshot-$(date +%Y-%m-%d_%H-%M-%S).png | wl-copy && notify-send "Screenshot" "Screenshot of whole screen taken" -t 1000]]
	),
	{ submap_universal = true }
)

hl.bind("SHIFT + F11", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/screen-record.sh"), { submap_universal = true })
hl.bind(mainMod .. " + grave", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/clipboard-menu.sh"), { submap_universal = true })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/power-profiles.sh"), { submap_universal = true })
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/power-menu.sh"), { submap_universal = true })
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + SHIFT + L", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.focus({ workspace = "r-1" }))

hl.bind(mainMod .. " + CTRL + L", hl.dsp.window.move({ workspace = "r+1" }))
hl.bind(mainMod .. " + CTRL + H", hl.dsp.window.move({ workspace = "r-1" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Repeating media keys
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true, submap_universal = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true, submap_universal = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { repeating = true, submap_universal = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { repeating = true, submap_universal = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { repeating = true, submap_universal = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { repeating = true, submap_universal = true })

-- Locked media keys
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true, submap_universal = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, submap_universal = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, submap_universal = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true, submap_universal = true })

-- Switches
hl.bind("switch:on:Lid Switch", function()
	hl.timer(function()
		hl.dispatch(hl.dsp.dpms({ action = "off" }))
	end, { timeout = 500, type = "oneshot" })
end, { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.dpms({ action = "on" }), { locked = true })

-- Helpers menu
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/helpers-menu.sh"), { submap_universal = true })

-- Modal overlay protection: block accidental SUPER+C closes & window/workspace binds while overlays open
hl.define_submap("hyprvibe-overlay", function()
	hl.bind(mainMod .. " + C", hl.dsp.no_op())
end)

local overlay_namespaces = {
	["hyprvibe-launcher"] = true,
	["hyprvibe-settings"] = true,
}

local function has_active_overlay_layer(excluding)
	local excl_addr = excluding and excluding.address or nil
	for _, layer in ipairs(hl.get_layers()) do
		if layer and overlay_namespaces[layer.namespace] and layer.mapped ~= false then
			if not excl_addr or layer.address ~= excl_addr then
				return true
			end
		end
	end
	return false
end

hl.on("layer.opened", function(layer)
	if layer and overlay_namespaces[layer.namespace] and hl.get_current_submap() == "" then
		hl.dispatch(hl.dsp.submap("hyprvibe-overlay"))
	end
end)

hl.on("layer.closed", function(layer)
	if layer and overlay_namespaces[layer.namespace]
		and hl.get_current_submap() == "hyprvibe-overlay"
		and not has_active_overlay_layer(layer) then
		hl.dispatch(hl.dsp.submap("reset"))
	end
end)

-- Resize submap
hl.bind(mainMod .. " + Y", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
	hl.bind("H", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), { repeating = true })
	hl.bind("J", hl.dsp.window.resize({ x = 0, y = 10, relative = true }), { repeating = true })
	hl.bind("K", hl.dsp.window.resize({ x = 0, y = -10, relative = true }), { repeating = true })
	hl.bind("L", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), { repeating = true })
	hl.bind("escape", hl.dsp.submap("reset"))
end)

-- Submap notifications (only resize mode announces itself)
local active_submap = hl.get_current_submap()
hl.on("keybinds.submap", function(name)
	local prev = active_submap
	active_submap = name or ""
	if active_submap == "resize" then
		hl.exec_cmd("notify-send -t 2000 'Resize Mode ON'")
	elseif prev == "resize" and active_submap == "" then
		hl.exec_cmd("notify-send -t 2000 'Resize Mode OFF'")
	end
end)
