hl.env("XCURSOR_SIZE", "22")
hl.env("HYPRCURSOR_SIZE", "22")
hl.env("XCURSOR_THEME", "Simp1e")
hl.env("HYPRCURSOR_THEME", "Simp1e")
hl.env("TERMINAL", "foot")
hl.env("CLIPHIST_MAX_ITEMS", "20")
hl.env("CLIPHIST_MAX_ITEM_SIZE", "10485760")

local home = os.getenv("HOME")
local cur_path = os.getenv("PATH") or "/usr/local/sbin:/usr/local/bin:/usr/bin"
if home and not (":" .. cur_path .. ":"):find(":" .. home .. "/.local/bin:", 1, true) then
	hl.env("PATH", home .. "/.local/bin:" .. cur_path)
end
