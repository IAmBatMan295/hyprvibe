-- HyprVibe Dynamic Theme Sync
local theme = require("config.theme")

local function apply_theme(name)
  theme.apply_theme(name)
end

local function sync_from_disk_if_changed()
  local disk_theme = theme.read_disk_theme()
  if disk_theme and disk_theme ~= theme.active_theme then
    theme.last_state_theme = disk_theme
    apply_theme(disk_theme)
  end
end

return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        apply_theme()
      end,
    },
    init = function()
      local group = vim.api.nvim_create_augroup("HyprVibeThemeSync", { clear = true })

      -- Auto-reload on focus only if disk theme actually changed
      vim.api.nvim_create_autocmd("FocusGained", {
        group = group,
        pattern = "*",
        callback = sync_from_disk_if_changed,
      })

      -- Debounced file watcher for live theme reload
      local uv = vim.uv or vim.loop
      local watcher = uv.new_fs_event()
      local debounce = uv.new_timer()
      if watcher and debounce then
        local watch_dir = vim.fn.expand("~/.local/state/hyprvibe/current")
        vim.fn.mkdir(watch_dir, "p")
        pcall(function()
          watcher:start(watch_dir, {}, vim.schedule_wrap(function()
            debounce:stop()
            debounce:start(80, 0, vim.schedule_wrap(sync_from_disk_if_changed))
          end))
        end)
      end

      -- Sync background on any ColorScheme change
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        pattern = "*",
        callback = function()
          theme.sync_terminal_bg()
        end,
      })

      -- Reset terminal default background on exit (OSC 111) in interactive UIs
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
          if #vim.api.nvim_list_uis() == 0 then
            return
          end
          pcall(function()
            local osc111 = "\x1b]111\x1b\\"
            local seq = os.getenv("TMUX") and ("\x1bPtmux;\x1b" .. osc111:gsub("\x1b", "\x1b\x1b") .. "\x1b\\") or osc111
            io.stdout:write(seq)
            io.stdout:flush()
          end)
        end,
      })
    end,
  },
}
