return {
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    opts = function(_, opts)
      -- Reserve these keys for diff hunks instead of class navigation.
      opts.move.keys.goto_next_start["]c"] = nil
      opts.move.keys.goto_previous_start["[c"] = nil
    end,
  },
  {
    "NMAC427/guess-indent.nvim",
    lazy = false,
    opts = {},
  },
  {
    "folke/snacks.nvim",
    opts = { explorer = { enabled = false } },
    keys = {
      { "<leader>e", false },
      { "<leader>E", false },
      { "<leader>fe", false },
      { "<leader>fE", false },
    },
  },
  {
    "stevearc/oil.nvim",
    lazy = false,
    dependencies = { "nvim-mini/mini.icons" },
    opts = {},
    keys = {
      { "<leader>e", "<cmd>Oil<cr>", desc = "Explorer Oil (File Directory)" },
    },
  },
  { "akinsho/bufferline.nvim", enabled = false },
  { "folke/flash.nvim", enabled = false },
  {
    "folke/noice.nvim",
    opts = {
      cmdline = { enabled = false },
      messages = { enabled = false },
      popupmenu = { enabled = false },
    },
  },
  {
    "saghen/blink.cmp",
    opts = {
      completion = { ghost_text = { enabled = false } },
    },
  },
  {
    "kawre/leetcode.nvim",
    cmd = "Leet",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "folke/snacks.nvim",
    },
    opts = {
      picker = { provider = "snacks-picker" },
    },
  },
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    keys = {
      { "<leader>gg", "<cmd>Neogit<cr>", desc = "Open Neogit" },
    },
    dependencies = { "esmuellert/codediff.nvim", "folke/snacks.nvim" },
    opts = {
      integrations = { codediff = true, snacks = true },
    },
  },
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    opts = {
      keymaps = {
        view = { next_hunk = "]c", prev_hunk = "[c" },
      },
    },
  },
  { "nvim-mini/mini.pairs", enabled = false },
  { "ej-shafran/compile-mode.nvim" },
  { dir = "~/devel/dolores.nvim/", opts = { styles = { transparency = true } } },
}
