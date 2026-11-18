-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>t", function()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
        vim.api.nvim_set_current_win(win)
        vim.cmd.startinsert()
        return
      end
    end
  end
  vim.cmd.tabnew()
  vim.cmd.terminal()
  vim.cmd.startinsert()
end, { desc = "Terminal tab" })

-- Disable LazyVim's line-moving shortcuts to avoid accidental swaps.
vim.keymap.del({ "n", "i", "v" }, "<A-j>")
vim.keymap.del({ "n", "i", "v" }, "<A-k>")

vim.keymap.set("n", "<leader>cc", function()
  if type(vim.g.compile_command) == "string" and vim.g.compile_command ~= "" then
    vim.cmd.Recompile()
  else
    vim.cmd.Compile()
  end
end, { desc = "Compile project" })
