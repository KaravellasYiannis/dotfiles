return {
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = { "esmuellert/codediff.nvim", "folke/snacks.nvim" },
    opts = {
      integrations = { codediff = true, snacks = true },
    },
  },
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    opts = {},
  },
  { "nvim-mini/mini.pairs", enabled = false },
}
