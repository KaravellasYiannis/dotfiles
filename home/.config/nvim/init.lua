vim.api.nvim_create_autocmd("UIEnter", {
  callback = function()
    if vim.g.neovide then
      vim.o.guifont = "monospace:h14"
    end
  end,
})

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
