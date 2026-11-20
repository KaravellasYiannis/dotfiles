-- Options are automatically loaded before lazy.nvim startup.
require("config.remote_clipboard").setup()
require("config.optional")

vim.opt.relativenumber = false
vim.opt.cursorlineopt = "number"
vim.g.autoformat = false

vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4

vim.opt.listchars = "tab:> ,trail:·,space:·"

-- Toggle editor chrome.
vim.g.focus_mode = false
vim.api.nvim_create_user_command("ToggleFocus", function()
  vim.g.focus_mode = not vim.g.focus_mode
  local focus = vim.g.focus_mode
  vim.opt.laststatus = focus and 0 or 3
  vim.opt.showtabline = focus and 0 or 2
  vim.opt.number = not focus
  vim.opt.signcolumn = focus and "no" or "yes"
  vim.opt.list = not focus
  vim.opt.cursorline = not focus
  vim.g.snacks_indent = not focus
  vim.lsp.inlay_hint.enable(not focus)
end, { desc = "Toggle distraction-free UI" })
