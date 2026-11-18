local uv = vim.uv
local windows = vim.fn.has("win32") == 1
local state = vim.fn.stdpath("state")
local registry = vim.fs.joinpath(state, "workspaces")
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

local function ready(address)
  return listening(address) and remote_eval(address, "get(g:, 'local_workspace_ready', 0)") == "1"
end

local function attach(target)
  if is_current(target.address) then
    return
  end
  if attaching then
    error("A workspace is already starting", 0)
  end
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

  attaching = true
  local responded = vim.wait(8000, function()
    return ready(target.address)
  end, 100)
  attaching = false
  if not responded then
    error("Workspace did not respond at " .. target.path, 0)
  end

  vim.fn.mkdir(registry, "p", 448)
  vim.fn.writefile({ vim.json.encode(target.path) }, vim.fs.joinpath(registry, target.id .. ".json"))
  vim.cmd.connect({ args = { target.address }, magic = { file = false, bar = false } })
end

local function pick()
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
      items[#items + 1] = { text = (live and "[live] " or "") .. path, target = target }
    end
  end

  for _, target in ipairs(registered_workspaces()) do
    add(target.path, true)
  end

  add(vim.fn.getcwd())
  local roots = vim.fs.joinpath(vim.fn.stdpath("config"), "workspace-roots")
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

  Snacks.picker.pick({
    title = "Workspaces",
    items = items,
    layout = { preset = "select" },
    format = "text",
    confirm = function(picker, item)
      picker:close()
      if item then
        attach(item.target)
      end
    end,
  })
end

-- :qall can close these buffer types even when they are marked modified.
local dirty_buffers = [[len(filter(getbufinfo({'bufmodified': 1}), ]]
  .. [[{_, buf -> index(['nofile', 'nowrite', 'terminal'], getbufvar(buf.bufnr, '&buftype')) == -1}))]]

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
        local status = remote_eval(target.address, "get(g:, 'local_workspace_ready', 0) == 1 ? " .. dirty_buffers .. " : -1")
        local modified = tonumber(status)
        if not modified or modified < 0 then
          error("Could not verify workspace " .. target.path, 0)
        end
        if modified > 0 then
          error("Save changes in workspace " .. target.path .. " before stopping workspaces", 0)
        end
      end
      peers[#peers + 1] = target
    end
  end

  for _, target in ipairs(peers) do
    if force then
      force_quit(target.address)
    else
      local ok, channel = pcall(vim.fn.sockconnect, "pipe", target.address, { rpc = true })
      if ok and channel > 0 then
        vim.rpcnotify(channel, "nvim_command", "qall")
        vim.fn.chanclose(channel)
      end
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

vim.api.nvim_create_user_command("WorkspaceStopAll", function(opts)
  stop_all(opts.bang)
end, { bang = true, desc = "Stop local workspace servers and exit Neovim" })
