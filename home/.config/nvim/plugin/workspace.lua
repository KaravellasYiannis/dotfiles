-- Each project keeps its own editor and jobs alive while the UI switches servers.
local uv = vim.uv
local windows = vim.fn.has("win32") == 1
local state = vim.fn.stdpath("state")
local registry = vim.fs.joinpath(state, "workspaces")
-- Hash the profile and project paths to keep socket addresses short and distinct.
local namespace = vim.fn.sha256(windows and state:lower() or state):sub(1, 16)
local socket_dir = vim.fs.joinpath(vim.env.XDG_RUNTIME_DIR or "/tmp", "nvim-ws-" .. namespace)

local function directory(path)
  local resolved = uv.fs_realpath(vim.fn.fnamemodify(path, ":p"))
  return resolved and vim.fn.isdirectory(resolved) == 1 and vim.fs.normalize(resolved, { expand_env = false }) or nil
end

local function workspace(path)
  local id = vim.fn.sha256(windows and path:lower() or path):sub(1, 20)
  return {
    path = path,
    id = id,
    address = windows and ([[\\.\pipe\nvim-ws-]] .. namespace .. "-" .. id)
      or vim.fs.joinpath(socket_dir, id),
  }
end

local function listening(address)
  local ok, channel = pcall(vim.fn.sockconnect, "pipe", address)
  if ok and channel > 0 then
    vim.fn.chanclose(channel)
    return true
  end
  return false
end

local function registered_workspaces()
  local targets = {}
  if uv.fs_stat(registry) then
    for name in vim.fs.dir(registry) do
      if name:match("%.json$") then
        local readable, lines = pcall(vim.fn.readfile, vim.fs.joinpath(registry, name), "", 1)
        local valid, path = pcall(vim.json.decode, readable and lines[1] or "")
        if valid and type(path) == "string" then
          local target = workspace(path)
          if name == target.id .. ".json" then
            targets[#targets + 1] = target
          end
        end
      end
    end
  end
  return targets
end

local function is_current(address)
  -- Neovim can report Windows pipe addresses with forward slashes.
  return vim.v.servername:gsub("\\", "/") == address:gsub("\\", "/")
end

local function remote_eval(address, expression)
  local result = vim.system({
    vim.v.progpath, "--server", address, "--remote-expr", expression,
  }, { timeout = 500, text = true }):wait()
  return result.code == 0 and vim.trim(result.stdout) or nil
end

local attaching = false
-- Run readiness checks in a separate process so a busy server cannot stall the UI.
local wait_for_workspace = [[
  -- shortcut: Neovim 0.12 can keep stale multigrid cells after detach. Remove this
  -- temporary single-grid UI once Neovim resends a full grid on reattach.
  local refresh_tabs = [=[
    local current = vim.api.nvim_get_current_tabpage()
    -- Refresh hidden grids without firing TabEnter or changing the alternate tab.
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if tab ~= current then
        vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tab), function()
          vim.cmd.redraw({ bang = true })
        end)
      end
    end
    vim.cmd.redraw({ bang = true })
  ]=]

  local function reset_grid(width, height)
    local pipe = vim.uv.new_pipe(false)
    local unpack = vim.mpack.Unpacker()
    local detached = false
    local address = arg[1]
    if vim.fn.has("win32") == 1 then
      address = address:gsub("/", "\\")
    end

    pipe:connect(address, function(err)
      assert(not err, err)
      pipe:read_start(function(read_error, data)
        assert(not read_error, read_error)
        if not data then return end
        local offset = 1
        while offset <= #data do
          local message
          message, offset = unpack(data, offset)
          -- Advance only on RPC replies and discard the temporary UI's redraw events.
          if message and message[1] == 1 then
            assert(message[3] == vim.NIL, vim.inspect(message))
            if message[2] == 1 then
              pipe:write(vim.mpack.encode({ 0, 2, "nvim_exec_lua", { refresh_tabs, {} } }))
            elseif message[2] == 2 then
              pipe:write(vim.mpack.encode({ 0, 3, "nvim_ui_detach", {} }))
            else
              detached = true
            end
          end
        end
      end)
      pipe:write(vim.mpack.encode({ 0, 1, "nvim_ui_attach", { width, height, { ext_linegrid = true } } }))
    end)
    assert(vim.wait(8000, function() return detached end))
    pipe:close()
  end

  local channel
  local readiness = arg[3] ~= "" and "get(g:, 'local_workspace_ready', 0)" or "1"
  assert(vim.wait(8000, function()
    if not channel then
      local ok, id = pcall(vim.fn.sockconnect, "pipe", arg[1], { rpc = true })
      if not ok or id <= 0 then
        return false
      end
      channel = id
    end
    -- A detached server can be waiting for Enter before it handles normal RPC.
    local mode = vim.rpcrequest(channel, "nvim_get_mode")
    if mode.blocking and mode.mode == "r" then
      vim.rpcnotify(channel, "nvim_input", "<CR>")
    end
    return vim.rpcrequest(channel, "nvim_eval", readiness) == 1
  end, 100))
  if arg[4] == "multigrid" then
    local size = vim.rpcrequest(channel, "nvim_eval", "get(g:, 'neovide', 0) && empty(nvim_list_uis()) ? [&columns, &lines] : []")
    if #size > 0 then
      reset_grid(size[1], size[2])
    end
  end
  vim.rpcrequest(channel, "nvim_exec_lua", [=[
    local source, path = ...
    -- Store the return address on the destination so repeated toggles work both ways.
    vim.g.local_workspace_previous = source
    local root = path ~= "" and path or vim.g.local_workspace_path or vim.fn.getcwd(-1, -1)
    vim.g.local_workspace_path = root
    local name = vim.fs.basename(root)

    -- The reset UI is already gone. Show the message when the real UI arrives.
    vim.api.nvim_create_autocmd("UIEnter", {
      group = vim.api.nvim_create_augroup("WorkspaceNotification", { clear = true }),
      once = true,
      callback = vim.schedule_wrap(function()
        vim.notify("Switched to " .. (name ~= "" and name or root))
      end),
    })
  ]=], { arg[2], arg[3] })
]]

local function start_workspace(target)
  if not windows then
    uv.fs_mkdir(socket_dir, 448)
    local stat = uv.fs_lstat(socket_dir)
    if not stat or stat.type ~= "directory" or stat.uid ~= uv.getuid() or bit.band(stat.mode, 511) ~= 448 then
      error("Cannot use private workspace socket directory " .. socket_dir, 0)
    end
  end

  if not listening(target.address) then
    local job = vim.fn.jobstart({
      vim.v.progpath, "--headless", "--listen", target.address,
      "--cmd", "let g:neovide_detach_on_quit = 'always_detach'",
      "-c", "let g:local_workspace_ready = 1",
    }, { cwd = target.path, detach = true, stdin = "null" })
    if job <= 0 then
      error("Could not start Neovim for " .. target.path, 0)
    end
  end
end

local function attach(target)
  if is_current(target.address) then
    return
  end
  if attaching then
    error("A workspace switch is already in progress", 0)
  end
  if target.path then
    start_workspace(target)
  elseif not listening(target.address) then
    vim.notify("The previous workspace is no longer running", vim.log.levels.INFO)
    return
  end

  local source = vim.v.servername ~= "" and vim.v.servername or vim.fn.serverstart()
  local multigrid = vim.tbl_contains(vim.api.nvim_list_uis(), function(ui)
    return ui.ext_multigrid
  end, { predicate = true })
  local probe = vim.system({
    vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE",
    "-l", "-", target.address, source, target.path or "", multigrid and "multigrid" or "single-grid",
  }, { stdin = wait_for_workspace }, vim.schedule_wrap(function(result)
    attaching = false
    if #vim.api.nvim_list_uis() == 0 then
      return
    end
    if result.code ~= 0 or result.signal ~= 0 then
      vim.notify("Workspace did not respond at " .. (target.path or target.address), vim.log.levels.ERROR)
      return
    end

    if target.path then
      vim.fn.mkdir(registry, "p", 448)
      vim.fn.writefile({ vim.json.encode(target.path) }, vim.fs.joinpath(registry, target.id .. ".json"))
    end
    vim.cmd.connect({ args = { target.address }, magic = { file = false, bar = false } })
  end))
  attaching = true
  -- The probe can still be inside an RPC request when the deadline expires.
  vim.defer_fn(function()
    if not probe:is_closing() then
      probe:kill("sigkill")
    end
  end, 8000)
end

-- :qall can close these buffer types even when they are marked modified.
local dirty_buffers = [[len(filter(getbufinfo({'bufmodified': 1}), ]]
  .. [[{_, buf -> index(['nofile', 'nowrite', 'terminal'], getbufvar(buf.bufnr, '&buftype')) == -1}))]]

local function stop_error(target)
  local status = remote_eval(target.address, "get(g:, 'local_workspace_ready', 0) == 1 ? " .. dirty_buffers .. " : -1")
  local modified = tonumber(status)
  if not modified or modified < 0 then
    return "Could not verify workspace " .. target.path
  end
  if modified > 0 then
    return "Save changes in workspace " .. target.path .. " before stopping it"
  end
end

local function request_quit(address)
  local ok, channel = pcall(vim.fn.sockconnect, "pipe", address, { rpc = true })
  if ok and channel > 0 then
    vim.rpcnotify(channel, "nvim_command", "qall")
    vim.fn.chanclose(channel)
  end
end

local function stop_workspace(picker, item)
  if not item then
    return
  end
  local target = item.target
  if is_current(target.address) then
    picker:close()
    vim.cmd.qall()
    return
  end
  if not listening(target.address) then
    picker:find()
    vim.notify("Workspace is already stopped: " .. target.path)
    return
  end
  local err = stop_error(target)
  if err then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  request_quit(target.address)
  local deadline = uv.hrtime() + 3e9
  local function refresh_when_stopped()
    if not listening(target.address) then
      picker:find()
    elseif uv.hrtime() < deadline then
      vim.defer_fn(refresh_when_stopped, 50)
    else
      vim.notify("Could not stop workspace " .. target.path, vim.log.levels.WARN)
    end
  end
  refresh_when_stopped()
end

local function workspace_items()
  local items, seen = {}, {}
  local function add(path, live_only)
    path = directory(path)
    if not path then
      return
    end
    local target = workspace(path)
    if seen[target.id] then
      return
    end
    local live = live_only and listening(target.address)
    if not live_only or live then
      seen[target.id] = true
      items[#items + 1] = { text = path, target = target, live = live }
    end
  end

  for _, target in ipairs(registered_workspaces()) do
    add(target.path, true)
  end

  add(vim.fn.getcwd())
  local roots = vim.fs.joinpath(vim.fn.stdpath("config"), "workspace-roots")
  -- Reuse allmux's project roots when no Neovim roots file is configured.
  if not windows and vim.fn.filereadable(roots) == 0 then
    roots = vim.fs.joinpath(vim.env.XDG_CONFIG_HOME or "~/.config", ".allmux")
    roots = vim.fn.fnamemodify(roots, ":p")
  end
  if vim.fn.filereadable(roots) == 1 then
    for _, line in ipairs(vim.fn.readfile(roots)) do
      local root = vim.trim(line)
      root = root ~= "" and directory(root) or nil
      if root then
        for name, kind in vim.fs.dir(root) do
          if name:sub(1, 1) ~= "." and (kind == "directory" or kind == "link") then
            add(vim.fs.joinpath(root, name))
          end
        end
      end
    end
  end
  return items
end

local function pick()
  Snacks.picker.pick({
    title = "Workspaces",
    finder = workspace_items,
    layout = { preset = "select" },
    actions = { stop_workspace = { action = stop_workspace, desc = "Stop workspace" } },
    win = {
      input = { keys = { ["<C-x>"] = { "stop_workspace", mode = { "i", "n" } } } },
      list = { keys = { ["<C-x>"] = "stop_workspace" } },
    },
    format = function(item)
      local current = is_current(item.target.address)
      local color = current and "DiagnosticInfo" or (item.live and "DiagnosticOk" or "Comment")
      return {
        { (current or item.live) and "● " or "○ ", color },
        { vim.fn.fnamemodify(item.text, ":~") },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        attach(item.target)
      end
    end,
  })
end

local function force_quit(address)
  -- Fast RPC can acknowledge a hit-enter prompt even while normal RPC is blocked.
  local quit = ([[
    local channel = vim.fn.sockconnect("pipe", %s, { rpc = true })
    local mode = vim.rpcrequest(channel, "nvim_get_mode")
    if mode.blocking and mode.mode == "r" then
      vim.rpcrequest(channel, "nvim_input", "<CR>")
    end
    if vim.rpcrequest(channel, "nvim_eval", "get(g:, 'local_workspace_ready', 0)") == 1 then
      pcall(vim.rpcrequest, channel, "nvim_command", "qall!")
    end
  ]]):format(vim.inspect(address))
  vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-c", "lua " .. quit, "-c", "qall!" },
    { timeout = 2500 })
end

local function stop_all(force)
  if not force and vim.fn.eval(dirty_buffers) > 0 then
    error("Save changes in the current editor before stopping workspaces", 0)
  end

  local peers = {}
  for _, target in ipairs(registered_workspaces()) do
    if not is_current(target.address) and listening(target.address) then
      if not force then
        local err = stop_error(target)
        if err then
          error(err, 0)
        end
      end
      peers[#peers + 1] = target
    end
  end

  for _, target in ipairs(peers) do
    if force then
      force_quit(target.address)
    else
      request_quit(target.address)
    end
  end

  local stopped = vim.wait(3000, function()
    peers = vim.tbl_filter(function(target)
      return listening(target.address)
    end, peers)
    return #peers == 0
  end, 50)
  if not stopped then
    error("Could not stop workspaces: " .. table.concat(vim.tbl_map(function(target)
      return target.path
    end, peers), ", "), 0)
  end

  vim.cmd.qall({ bang = force })
end

vim.api.nvim_create_user_command("Workspace", function(opts)
  if vim.fn.exists(":connect") ~= 2 or #vim.api.nvim_list_uis() == 0 then
    error("Workspace requires an attached Neovim 0.12+ UI with :connect support", 0)
  end
  if opts.args == "" then
    pick()
  else
    local path = directory(opts.args) or directory((opts.args:gsub("\\ ", " ")))
    if not path then
      error("Workspace directory does not exist: " .. opts.args, 0)
    end
    attach(workspace(path))
  end
end, { nargs = "?", complete = "dir", desc = "Switch to a local workspace" })

vim.keymap.set({ "n", "t" }, "<C-b>f", "<Cmd>Workspace<CR>", { desc = "Find workspace" })
vim.keymap.set({ "n", "t" }, "<C-b>L", function()
  local address = vim.g.local_workspace_previous
  if not address or address == "" then
    vim.notify("No previous workspace", vim.log.levels.INFO)
    return
  end
  attach({ address = address })
end, { desc = "Switch to previous workspace" })

vim.api.nvim_create_user_command("WorkspaceStopAll", function(opts)
  stop_all(opts.bang)
end, { bang = true, desc = "Stop local workspace servers and exit Neovim" })
