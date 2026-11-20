local modes = { "n", "i", "v", "c", "t" }

local function zoom(factor)
  return function()
    local scale = (vim.g.neovide_scale_factor or 1) * factor
    vim.g.neovide_scale_factor = math.max(0.5, math.min(3, scale))
  end
end

local zoom_in = zoom(1.1)
local bindings = {
  -- Neovide can report Ctrl+Shift+= as Ctrl+= on keyboards with + on the = key.
  { "<C-=>", zoom_in, "Zoom in" },
  { "<C-+>", zoom_in, "Zoom in" },
  { "<C-->", zoom(1 / 1.1), "Zoom out" },
  { "<C-S-v>", function()
    vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
  end, "Paste from clipboard" },
}

-- Workspace servers start headless and can later be attached to either frontend.
local mapped = false
local windows = vim.fn.has("win32") == 1

local function update_title_background()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  vim.g.neovide_title_background_color = normal.bg and ("#%06x"):format(normal.bg) or nil
end

vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    if mapped and windows then
      update_title_background()
    end
  end,
})

vim.api.nvim_create_autocmd({ "UIEnter", "UILeave" }, {
  callback = function()
    -- Inspect attached clients because g:neovide can outlive the GUI connection.
    local attached = vim.tbl_contains(vim.api.nvim_list_uis(), function(ui)
      local client = vim.api.nvim_get_chan_info(ui.chan).client
      return client and client.name == "neovide"
    end, { predicate = true })
    if attached == mapped then
      return
    end
    mapped = attached

    if attached and windows then
      vim.o.titlestring = "%{getcwd(-1)}"
      vim.o.titlelen = 0
      vim.o.title = true
      update_title_background()
    end

    if attached and (vim.o.guifont == "" or (windows and vim.o.guifont:match("^Cascadia Code,Cascadia Mono,"))) then
      vim.o.guifont = windows and "CaskaydiaCove NFM:h14" or "monospace:h14"
    end
    for _, binding in ipairs(bindings) do
      if attached then
        vim.keymap.set(modes, binding[1], binding[2], { silent = true, desc = binding[3] })
      else
        vim.keymap.del(modes, binding[1])
      end
    end
  end,
})
