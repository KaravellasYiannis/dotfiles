return {
    "nvim-mini/mini.icons",
    lazy = false,
    priority = 1000,
    opts = { style = "ascii" },
    config = function(_, opts)
        require("mini.icons").setup(opts)
        MiniIcons.mock_nvim_web_devicons()
    end,
}
