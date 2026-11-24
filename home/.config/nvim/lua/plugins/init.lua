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
            scroll = { enabled = false },
            explorer = { enabled = true },
            dashboard = { enabled = false },
            picker = {
                sources = {
                    grep = {
                        layout = {
                            reverse = true,
                            layout = {
                                box = "vertical",
                                width = 0.9,
                                height = 0.9,
                                border = true,
                                title = "{title} {live} {flags}",
                                title_pos = "center",
                                { win = "preview", title = "{preview}", height = 0.4, border = "bottom" },
                                { win = "list", border = "none" },
                                { win = "input", height = 1, border = "top" },
                            },
                        },
                    },
                },
                win = {
                    input = {
                        keys = {
                            ["<c-u>"] = false,
                        },
                    },
                },
            },
        },
        keys = {
            { "<leader><space>", false },
            { "<leader>e", false },
            {
                "<leader>E",
                function()
                    Snacks.explorer()
                end,
                desc = "Explorer Snacks (cwd)",
            },
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
    {
        "nvim-lualine/lualine.nvim",
        opts = function(_, opts)
            local sections = opts.sections
            -- shortcut: use the pinned LazyVim section order; recheck if an update or extra changes it.
            local profiler, noice_command, noice_mode, debugger, _, diff = unpack(sections.lualine_x)
            local diagnostics = sections.lualine_c[2]
            local path = { LazyVim.lualine.pretty_path({ modified_sign = " [+]" }) }

            sections.lualine_a = { {
                "mode",
                fmt = function(mode)
                    return mode:sub(1, 1)
                end,
            } }
            sections.lualine_b = { { "branch", icon = "" } }
            -- Keep the breadcrumbs LazyVim appends after its four base components.
            sections.lualine_c = vim.list_extend({ path, diff }, sections.lualine_c, 5)
            sections.lualine_x = {
                noice_command,
                { "fileformat", symbols = { unix = "UNIX", dos = "CRLF", mac = "CR" } },
                "lsp_status",
                diagnostics,
                profiler,
                noice_mode,
                debugger,
            }
            sections.lualine_z = {}
        end,
    },
    { "folke/flash.nvim", enabled = false },
    {
        "folke/noice.nvim",
        enabled = true,
        opts = {
            cmdline = { enabled = false },
            messages = { enabled = false },
            -- popupmenu = { enabled = false },
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
        opts = { auto_close_console = false, integrations = { codediff = true, snacks = true } },
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
    { "dlyongemallo/diffview-plus.nvim", },

    { "dlyongemallo/diffview-plus.nvim" },
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
    {
        "dmtrKovalenko/fff",
        build = function()
            -- downloads a prebuilt binary or falls back to cargo build
            require("fff.download").download_or_build_binary()
        end,
        keys = {
            {
                "<leader><leader>",
                function()
                    require("fff").find_files()
                end,
                desc = "FFFind files",
            },
            {
                "<leader>fz",
                function()
                    require("fff").live_grep()
                end,
                desc = "LiFFFe grep",
            },
        },
        opts = {
            prompt = vim.fn.fnamemodify(vim.fn.getcwd(), ":~") .. "/",
            layout = { prompt_position = "top", show_path_first = true, height = 0.9, width = 0.9 },
            file_picker = { fuzzy_query_highlighting = true },
            hl = { matched = "SnacksPickerMatch", directory_path = "" },
            keymaps = {
                preview_scroll_up = "<C-b>",
                cycle_previous_query = "<C-p>",
                cycle_forward_query = "<C-n>",
            },
        },
    },
    { "karavellasyiannis/go-live-markdown.nvim" },
}
