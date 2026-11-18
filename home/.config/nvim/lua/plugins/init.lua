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
    opts = {
      explorer = { enabled = true },
      dashboard = { enabled = false },
    },
    keys = {
      { "<leader>e", false },
      { "<leader>E", function() Snacks.explorer() end, desc = "Explorer Snacks (cwd)" },
      { "<leader>fe", false },
      { "<leader>fE", false },
    },
  },
  {
    "stevearc/oil.nvim",
    lazy = false,
    dependencies = { "nvim-mini/mini.icons" },
    opts = {
      view_options = { show_hidden = true },
    },
    keys = {
      { "<leader>e", "<cmd>Oil<cr>", desc = "Explorer Oil (File Directory)" },
    },
  },
  { "akinsho/bufferline.nvim", enabled = false },
  { "folke/flash.nvim", enabled = false },
  {
    "folke/noice.nvim",
    enabled = false,
    opts = {
      cmdline = { enabled = false },
      messages = { enabled = false },
      popupmenu = { enabled = false },
    },
  },
  {
    "saghen/blink.cmp",
    opts = {
      completion = {
        ghost_text = { enabled = false },
        list = { selection = { preselect = false } },
      },
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
      explorer = {
        view_mode = "tree",
        line_stats = { enabled = true },
      },
      keymaps = {
        view = { next_hunk = "]c", prev_hunk = "[c" },
      },
    },
  },
  { "nvim-mini/mini.pairs", enabled = false },
  { "folke/todo-comments.nvim", enabled = false },
  {
    "nvim-mini/mini.hipatterns",
    opts = {
      highlighters = {
        fixme = { pattern = "%f[%w]()FIXME()%f[%W]", group = "MiniHipatternsFixme" },
        hack = { pattern = "%f[%w]()HACK()%f[%W]", group = "MiniHipatternsHack" },
        todo = { pattern = "%f[%w]()TODO()%f[%W]", group = "MiniHipatternsFixme" },
        note = { pattern = "%f[%w]()NOTE()%f[%W]", group = "MiniHipatternsNote" },
      },
    },
  },
  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    opts = {},
  },
  { "ej-shafran/compile-mode.nvim" },
  { dir = "~/devel/dolores.nvim/" },
}
