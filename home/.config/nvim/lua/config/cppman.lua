vim.api.nvim_create_user_command("Cppman", function(opts)
    if vim.fn.executable("cppman") == 0 then
        vim.notify("cppman executable not found", vim.log.levels.ERROR)
        return
    end

    local width = tostring(vim.api.nvim_win_get_width(0) - 2)
    local result = vim.system({ "cppman", "--force-columns", width, opts.args }, { text = true }):wait()
    if result.code ~= 0 then
        vim.notify(vim.trim(result.stderr), vim.log.levels.ERROR)
        return
    end

    vim.cmd.new({ mods = opts.smods })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(result.stdout, "\n", { plain = true }))
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.swapfile = false
    vim.bo.filetype = "man"
    vim.bo.modifiable = false
end, { nargs = 1, desc = "Open C++ documentation with cppman" })
