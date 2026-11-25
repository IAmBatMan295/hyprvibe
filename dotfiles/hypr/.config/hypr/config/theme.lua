hl.config({
	general = {
		gaps_in = 3,
		gaps_out = 5,
		border_size = 2,
		col = {
			active_border = "rgba(4e4e4eff)",
			inactive_border = "rgba(1a1a1aff)",
		},
		resize_on_border = false,
		allow_tearing = true,
		layout = "dwindle",
	},
	decoration = {
		rounding = 0,
		rounding_power = 2,
		active_opacity = 1.0,
		inactive_opacity = 0.8,
		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},
		blur = {
			enabled = true,
			size = 6,
			passes = 2,
			vibrancy = 0.1696,
			ignore_opacity = true,
		},
	},
	animations = { enabled = true },
	dwindle = { preserve_split = true },
	master = { new_status = "master" },
	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		vrr = 2,
		key_press_enables_dpms = true,
		mouse_move_enables_dpms = true,
	},
	render = {
		direct_scanout = 0,
		cm_auto_hdr = 0,
	},
	xwayland = { force_zero_scaling = true },
})

-- Modern 120Hz Curves (Fast start, buttery smooth deceleration)
hl.curve("md3_decel", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("md3_accel", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

-- Fluid Snappy 120Hz Animation Tree
hl.animation({ leaf = "global", enabled = true, speed = 3, bezier = "md3_decel" })
hl.animation({ leaf = "border", enabled = true, speed = 4, bezier = "md3_decel" })
hl.animation({ leaf = "windows", enabled = true, speed = 2.8, bezier = "md3_decel", style = "popin" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.8, bezier = "md3_decel", style = "popin" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.8, bezier = "md3_accel", style = "popin" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.8, bezier = "md3_decel", style = "slide" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.5, bezier = "md3_decel" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.8, bezier = "md3_accel" })
hl.animation({ leaf = "fade", enabled = true, speed = 2.5, bezier = "md3_decel" })
hl.animation({ leaf = "layers", enabled = true, speed = 2.8, bezier = "md3_decel", style = "popin" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 2.8, bezier = "md3_decel", style = "popin" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.8, bezier = "md3_accel", style = "popin" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2.5, bezier = "md3_decel" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.8, bezier = "md3_accel" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3.2, bezier = "md3_decel", style = "slide" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 3.2, bezier = "md3_decel", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 3.2, bezier = "md3_decel", style = "slide" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 3, bezier = "md3_decel" })

-- Dynamic Theme Integration
local home = os.getenv("HOME") or ""
local state_theme = home .. "/.local/state/hyprvibe/current/hyprland.lua"
local f = io.open(state_theme, "r")

if not f then
	local function run_ok(cmd)
		local res = os.execute(cmd)
		return res == true or res == 0
	end

	-- Try resolving hyprvibe-theme binary via symlink or standard paths
	local repo_bin = ""
	local p = io.popen("readlink -f \"$HOME/.config/hypr/config/theme.lua\" 2>/dev/null", "r")
	if p then
		local real_path = p:read("*l") or ""
		p:close()
		if real_path ~= "" then
			repo_bin = real_path:gsub("/dotfiles/hypr/.config/hypr/config/theme%.lua$", "/bin/hyprvibe-theme")
		end
	end

	local candidates = {
		repo_bin,
		home .. "/hyprvibe/bin/hyprvibe-theme",
		home .. "/.local/bin/hyprvibe-theme",
		"hyprvibe-theme",
	}

	for _, bin in ipairs(candidates) do
		if bin and bin ~= "" then
			local check = (bin:sub(1, 1) == "/" and string.format("test -x %q", bin) or string.format("command -v %q >/dev/null 2>&1", bin))
			if run_ok(check) then
				run_ok(string.format("%q set monochrome >/dev/null 2>&1", bin))
				break
			end
		end
	end
	f = io.open(state_theme, "r")
end

if f then
	f:close()
	dofile(state_theme)
end
