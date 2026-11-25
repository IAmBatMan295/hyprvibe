-- HyprVibe Dynamic Theme Loader for Neovim
local M = {}

M.theme_file = vim.fn.expand("~/.local/state/hyprvibe/current/theme.name")
M.active_theme = nil
M.last_state_theme = nil

M.theme_map = {
  ["catppuccin"] = "catppuccin-mocha",
  ["monochrome"] = "immortal",
  ["iron-man"] = "ashen",
  ["everforest"] = "everforest",
  ["gruvbox"] = "gruvbox",
  ["forest-green"] = "forest-green",
}

M.plugin_map = {
  ["catppuccin-mocha"] = "catppuccin",
  ["immortal"] = "black-metal",
  ["ashen"] = "ashen",
  ["everforest"] = "everforest",
  ["gruvbox"] = "gruvbox",
  ["forest-green"] = "forest-green",
}

function M.read_disk_theme()
  if vim.fn.filereadable(M.theme_file) == 1 then
    local lines = vim.fn.readfile(M.theme_file)
    if #lines > 0 and lines[1] ~= "" then
      return vim.trim(lines[1])
    end
  end
  return nil
end

function M.get_hyprvibe_theme()
  local disk_theme = M.read_disk_theme()

  -- Detect external system theme changes
  if disk_theme and disk_theme ~= M.last_state_theme then
    M.last_state_theme = disk_theme
    M.active_theme = disk_theme
    return disk_theme
  end

  return M.active_theme or disk_theme or "catppuccin"
end

function M.sync_terminal_bg()
  if #vim.api.nvim_list_uis() == 0 then
    return
  end
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal" })
  local bg = normal_hl.bg
  if bg then
    local r = bit.band(bit.rshift(bg, 16), 0xff)
    local g = bit.band(bit.rshift(bg, 8), 0xff)
    local b = bit.band(bg, 0xff)
    local osc11 = string.format("\x1b]11;rgb:%02x%02x/%02x%02x/%02x%02x\x1b\\", r, r, g, g, b, b)
    local seq = os.getenv("TMUX") and ("\x1bPtmux;\x1b" .. osc11:gsub("\x1b", "\x1b\x1b") .. "\x1b\\") or osc11
    pcall(function()
      io.stdout:write(seq)
      io.stdout:flush()
    end)
  end
end

function M.apply_theme(name)
  local theme_name = name or M.get_hyprvibe_theme()
  M.active_theme = theme_name
  local cs = M.theme_map[theme_name] or theme_name or "catppuccin-mocha"

  -- Ensure lazy plugin is loaded if needed
  local plugin_pkg = M.plugin_map[cs]
  if plugin_pkg and package.loaded["lazy"] then
    pcall(require("lazy").load, { plugins = { plugin_pkg } })
  end

  -- Theme-specific pre-hooks
  if cs == "everforest" then
    vim.g.everforest_background = "hard"
    vim.g.everforest_transparent_background = 0
    vim.g.everforest_enable_italic = true
    vim.g.everforest_better_performance = 1
  elseif cs == "immortal" then
    pcall(function()
      require("black-metal").setup({ theme = cs, variant = "dark", transparent = false })
    end)
  elseif cs == "catppuccin-mocha" or cs == "catppuccin" then
    vim.g.catppuccin_flavour = "mocha"
  end

  local ok, _ = pcall(vim.cmd.colorscheme, cs)
  if not ok then
    pcall(vim.cmd.colorscheme, "default")
  end

  M.sync_terminal_bg()

  -- Live reload Lualine without wiping custom opts
  if package.loaded["lualine"] then
    pcall(function()
      require("lualine").refresh()
    end)
  end
end

return M
