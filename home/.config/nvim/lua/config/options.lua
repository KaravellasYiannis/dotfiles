-- Options are automatically loaded before lazy.nvim startup.
require("config.remote_clipboard").setup()

vim.opt.relativenumber = false
vim.g.autoformat = false

vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4

vim.opt.listchars = "tab:> ,trail:·,space:·"

-- Reuse LazyVim's Snacks Zen mode so the previous UI state is restored on exit.
vim.api.nvim_create_user_command("ToggleFocus", function()
  Snacks.zen({
    center = false,
    toggles = { indent = false },
    show = { statusline = false, tabline = false },
    win = {
      width = 0,
      backdrop = false,
      wo = {
        number = false,
        relativenumber = false,
        signcolumn = "no",
        statuscolumn = "",
        foldcolumn = "0",
        list = false,
        colorcolumn = "",
        cursorline = false,
        winbar = "",
      },
    },
  })
end, { desc = "Toggle a distraction-free LazyVim view" })
