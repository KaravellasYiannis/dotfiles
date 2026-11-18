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

    if attached then
      vim.o.guifont = "monospace:h14"
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
