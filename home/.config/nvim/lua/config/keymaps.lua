-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>cc", function()
  if type(vim.g.compile_command) == "string" and vim.g.compile_command ~= "" then
    vim.cmd.Recompile()
  else
    vim.cmd.Compile()
  end
end, { desc = "Compile project" })
