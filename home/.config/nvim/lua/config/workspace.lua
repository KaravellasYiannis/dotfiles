-- The UI switches connections. Each workspace keeps its own editor and jobs.
local M = {}
local uv = vim.uv
local windows = vim.fn.has("win32") == 1
local module_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local local_host = {
  config = vim.fn.stdpath("config"),
  state = vim.fn.stdpath("state"),
  nvim = vim.v.progpath,
  module = module_path,
  app = vim.env.NVIM_APPNAME or "",
}
local wsl_boot

local function fail(message)
  error(message, 0)
end

local function namespace(host)
  return vim.fn.sha256(windows and host.state:lower() or host.state):sub(1, 16)
end

local function socket_dir(name)
  return vim.fs.joinpath(vim.env.XDG_RUNTIME_DIR or "/tmp", "nvim-ws-" .. name)
end

local function private_socket_dir(dir)
  uv.fs_mkdir(dir, 448)
  local stat = uv.fs_lstat(dir)
  if not stat or stat.type ~= "directory" or stat.uid ~= uv.getuid() or bit.band(stat.mode, 511) ~= 448 then
    fail("Cannot use private workspace socket directory " .. dir)
  end
  return dir
end

local function wsl_path(path)
  if path:sub(1, 2) == [[\\]] then
    path = path:gsub("\\", "/")
  end
  local server, distro, linux = path:match("^//([^/]+)/([^/]+)(.*)$")
  if server and (server:lower() == "wsl.localhost" or server:lower() == "wsl$") then
    return distro, linux == "" and "/" or linux
  end
end

local function wsl_call(distro, op, args)
  local input = ([[
    if vim.v.servername ~= "" then vim.fn.serverstop(vim.v.servername) end
    local module = dofile(vim.env.NVIM_WORKSPACE_MODULE)
    io.write(vim.json.encode(module[%q](unpack(vim.json.decode(%q)))))
  ]]):format(op, vim.json.encode(args))
  return vim.system({
    "wsl.exe",
    "--distribution",
    distro,
    "--cd",
    "/",
    "--exec",
    "sh",
    "-c",
    [[
      export PATH="$PATH:/snap/bin"
      export NVIM_WORKSPACE_MODULE="$(wslpath -u "$1")" || exit
      exec nvim --headless -u NONE -i NONE -l -
    ]],
    "workspace",
    module_path,
  }, { stdin = input, timeout = 5000 })
end

local function wsl_result(process)
  local result = process:wait()
  if result.code == 0 then
    local ok, value = pcall(vim.json.decode, result.stdout or "")
    if ok then
      return value
    end
  end
  return nil, vim.trim(result.stderr or "")
end

local function directory(path)
  if windows then
    local distro, linux = wsl_path(path)
    if distro then
      -- A direct :Workspace path can be resolved without booting a Neovim helper.
      local ok, process = pcall(vim.system, {
        "wsl.exe",
        "--distribution",
        distro,
        "--cd",
        "/",
        "--exec",
        "sh",
        "-c",
        [[CDPATH=; cd -P "$1" && printf '%s\000' "$PWD"]],
        "workspace",
        linux,
      }, { timeout = 5000 })
      local result = ok and process:wait()
      local found = result and result.code == 0 and result.stdout:match("^(.-)%z$")
      return found and ("//wsl.localhost/" .. distro .. found) or nil
    end
  end
  local resolved = uv.fs_realpath(vim.fn.fnamemodify(path, ":p"))
  return resolved and vim.fn.isdirectory(resolved) == 1 and vim.fs.normalize(resolved, { expand_env = false }) or nil
end

local function scan_root(path, add)
  local dir = directory(path)
  local files = dir and uv.fs_scandir(dir)
  if not files then
    return
  end
  for name, kind in uv.fs_scandir_next, files do
    if name:sub(1, 1) ~= "." then
      local child = dir:gsub("/$", "") .. "/" .. name
      if kind == "directory" then
        add(child)
      elseif kind == "link" or kind == "unknown" or not kind then
        child = directory(child)
        if child then
          add(child)
        end
      end
    end
  end
end

local function discover(excluded)
  return dofile(vim.fs.dirname(module_path) .. "/workspace_discovery.lua")(excluded)
end

function M.scan_wsl(roots, excluded)
  local paths = {}
  for _, root in ipairs(roots) do
    scan_root(root, function(path)
      paths[#paths + 1] = path
    end)
  end
  return { paths = paths, sessions = discover(excluded) }
end

local function target_for(host, path)
  local distro, linux
  if windows then
    distro, linux = wsl_path(path)
  end
  -- The distro name is case-insensitive, but the filesystem inside it is not.
  local key = distro and ("wsl:" .. distro:lower() .. ":" .. linux) or (windows and path:lower() or path)
  local id = vim.fn.sha256(key):sub(1, 20)
  local name = namespace(host)
  local target = { path = path, id = id, distro = distro, linux = linux }
  if not distro then
    target.address = windows and ([[\\.\pipe\nvim-ws-]] .. name .. "-" .. id) or vim.fs.joinpath(socket_dir(name), id)
  end
  return target
end

local function registry(host, id)
  local dir = vim.fs.joinpath(host.state, "workspaces")
  return id and vim.fs.joinpath(dir, id .. ".json") or dir
end

local function register(host, target)
  vim.fn.mkdir(registry(host), "p", 448)
  local path = registry(host, target.id)
  local tmp = path .. "." .. uv.os_getpid() .. ".tmp"
  local entry = target.distro and { path = target.path, address = target.address } or target.path
  vim.fn.writefile({ vim.json.encode(entry) }, tmp)
  local ok, err = uv.fs_rename(tmp, path)
  if not ok then
    uv.fs_unlink(tmp)
    fail("Cannot register workspace " .. target.path .. ": " .. err)
  end
end

local function read_target(host, name)
  local readable, lines = pcall(vim.fn.readfile, vim.fs.joinpath(registry(host), name), "", 1)
  local valid, entry = pcall(vim.json.decode, readable and lines[1] or "")
  if not valid then
    return
  end
  local path = type(entry) == "table" and entry.path or entry
  if type(path) ~= "string" then
    return
  end
  local target = target_for(host, path)
  if name ~= target.id .. ".json" then
    return
  end
  if target.distro then
    local address = type(entry) == "table" and entry.address
    if type(address) ~= "string" or not address:match("^127%.0%.0%.1:%d+$") then
      return
    end
    target.address = address
  end
  return target
end

local function registered(host)
  local targets = {}
  if uv.fs_stat(registry(host)) then
    for name in vim.fs.dir(registry(host)) do
      if name:match("%.json$") then
        targets[#targets + 1] = read_target(host, name)
      end
    end
  end
  return targets
end

local function connection(address, rpc)
  if not address then
    return
  end
  local kind = address:match("^127%.0%.0%.1:") and "tcp" or "pipe"
  local ok, channel = pcall(vim.fn.sockconnect, kind, address, { rpc = rpc })
  return ok and channel > 0 and channel or nil
end

local function listening(address)
  local channel = connection(address, false)
  if channel then
    vim.fn.chanclose(channel)
    return true
  end
  return false
end

local function same_address(a, b)
  return a and b and a:gsub("\\", "/") == b:gsub("\\", "/")
end

local wsl_launch = [[
export PATH="$PATH:/snap/bin"
export NVIM_WORKSPACE_MODULE="$(wslpath -u "$1")" || exit
export NVIM_WORKSPACE_BOOT="$2"
exec nvim --headless --listen 127.0.0.1:0 \
  --cmd 'lua local ok, err = pcall(function() dofile(vim.env.NVIM_WORKSPACE_MODULE).begin_wsl() end); if not ok then io.stderr:write(tostring(err), "\n"); vim.cmd.cquit() end' \
  -c 'lua local ok, err = pcall(require("config.workspace").finish_wsl); if not ok then io.stderr:write(tostring(err), "\n"); vim.cmd.cquit() end'
]]

local function start(host, target)
  local command, cwd, input
  if target.distro then
    local wsl = {
      "wsl.exe",
      "--distribution",
      target.distro,
      "--cd",
      target.linux,
      "--exec",
      "sh",
      "-c",
      wsl_launch,
      "workspace",
      host.module,
      vim.base64.encode(vim.json.encode({ host = host, target = target, namespace = namespace(host) })),
    }
    -- Keep WSL interop alive without starting wsl.exe as a detached console
    -- process, which disables Windows' no-window flag.
    command = { host.nvim, "--headless", "-u", "NONE", "-i", "NONE", "-l", "-" }
    input = ([[
      vim.uv.disable_stdio_inheritance()
      if vim.v.servername ~= "" then vim.fn.serverstop(vim.v.servername) end
      local result = vim.system(vim.json.decode(%q), {
        stdout = false,
        stderr = function(_, data)
          if data then
            io.stderr:write(data)
            io.stderr:flush()
          end
        end,
      }):wait()
      if result.code ~= 0 then
        vim.cmd.cquit()
      end
    ]]):format(vim.json.encode(wsl))
  else
    if not windows then
      private_socket_dir(socket_dir(namespace(host)))
    end
    cwd = target.path
    command = {
      host.nvim,
      "--headless",
      "--listen",
      target.address,
      "--cmd",
      "let g:neovide_detach_on_quit = 'always_detach'",
      "-c",
      "let g:local_workspace_ready = 1",
    }
  end
  local stderr = {}
  local job = vim.fn.jobstart(command, {
    cwd = cwd,
    detach = true,
    stdin = input and "pipe" or "null",
    env = { NVIM_APPNAME = host.app },
    on_stderr = function(_, data)
      vim.list_extend(stderr, data)
    end,
  })
  if job <= 0 then
    fail("Could not start Neovim for " .. target.path)
  end
  if input then
    vim.fn.chansend(job, input)
    vim.fn.chanclose(job, "stdin")
  end
  return function()
    return vim.trim(table.concat(stderr, "\n"))
  end
end

function M.begin_wsl()
  -- The stable Unix socket prevents two launchers from starting the same project.
  wsl_boot = vim.json.decode(vim.base64.decode(vim.env.NVIM_WORKSPACE_BOOT))
  vim.env.NVIM_WORKSPACE_BOOT = nil
  vim.env.NVIM_WORKSPACE_MODULE = nil
  vim.fn.serverstart(vim.fs.joinpath(private_socket_dir(socket_dir(wsl_boot.namespace)), wsl_boot.target.id))
  package.loaded["config.workspace"] = M
  -- Use the Windows frontend's GUI setup, even when WSL has an older copy.
  package.loaded["config.neovide"] = dofile(vim.fs.dirname(module_path) .. "/neovide.lua") or true
  vim.g.neovide_detach_on_quit = "always_detach"
end

local function windows_path_in_wsl(path)
  local result = vim.system({ "wslpath", "-u", path }, { text = true }):wait(2000)
  if result.code ~= 0 or vim.trim(result.stdout) == "" then
    fail("WSL could not resolve " .. path)
  end
  return vim.trim(result.stdout)
end

function M.adopt_wsl(host, target)
  if not wsl_boot then
    local nvim = windows_path_in_wsl(host.nvim)
    target.address = vim.fn.serverstart("127.0.0.1:0")
    wsl_boot = { host = host, target = target, nvim = nvim }
    package.loaded["config.workspace"] = M
    vim.g.neovide_detach_on_quit = "always_detach"
    -- Replace an older copy of this config's GUI hooks before Windows attaches.
    local config = "@" .. vim.fn.stdpath("config") .. "/lua/config/neovide.lua"
    local hooks = {}
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = { "UIEnter", "UILeave" } })) do
      if type(autocmd.callback) == "function" and debug.getinfo(autocmd.callback, "S").source == config then
        hooks[autocmd.id] = true
      end
    end
    for id in pairs(hooks) do
      vim.api.nvim_del_autocmd(id)
    end
    if next(hooks) then
      package.loaded["config.neovide"] = dofile(vim.fs.dirname(module_path) .. "/neovide.lua") or true
    end
    M.setup()
  end
  if not vim.tbl_contains(vim.fn.serverlist(), wsl_boot.target.address) then
    wsl_boot.target.address = vim.fn.serverstart("127.0.0.1:0")
  end
  return wsl_boot.target.address
end

function M.bridge_wsl(host, target)
  local channel = connection(target.socket, true)
  if not channel then
    fail("The WSL Neovim session is no longer running")
  end
  return vim.rpcrequest(
    channel,
    "nvim_exec_lua",
    [[
    local module, host, target = ...
    if vim.uv.os_getpid() ~= target.pid then
      error("The WSL Neovim session changed")
    end
    local workspace = package.loaded["config.workspace"]
    if type(workspace) ~= "table" or not workspace.adopt_wsl then
      workspace = dofile(module)
    end
    return workspace.adopt_wsl(host, target)
  ]],
    { module_path, host, target }
  )
end

function M.finish_wsl()
  local host, target = wsl_boot.host, wsl_boot.target
  local registry_host = { state = windows_path_in_wsl(host.state) }
  wsl_boot.nvim = windows_path_in_wsl(host.nvim)
  target.address = vim.v.servername
  vim.g.local_workspace_path = target.path
  M.setup()
  vim.g.local_workspace_ready = 1
  vim.g.local_workspace_id = target.id
  register(registry_host, target)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      -- The Unix socket still holds the workspace lock during shutdown.
      uv.fs_unlink(registry(registry_host, target.id))
    end,
  })
end

-- Neovim 0.12 can keep stale multigrid cells after detach. Refresh them with a
-- temporary single-grid UI before the real UI reconnects.
local function reset_grid(address, width, height)
  local port = address:match("^127%.0%.0%.1:(%d+)$")
  local stream = port and uv.new_tcp() or uv.new_pipe(false)
  local unpack = vim.mpack.Unpacker()
  local detached, failure
  local function accept(err)
    if err then
      failure = err
      return
    end
    local function send(id, method, args)
      stream:write(vim.mpack.encode({ 0, id, method, args }))
    end
    stream:read_start(function(read_error, data)
      if not data then
        failure = read_error or "Connection closed during grid refresh"
        return
      end
      local offset = 1
      while offset <= #data do
        local message
        message, offset = unpack(data, offset)
        if message and message[1] == 1 then
          if message[3] ~= vim.NIL then
            failure = vim.inspect(message[3])
          elseif message[2] == 1 then
            send(2, "nvim_exec_lua", {
              [[
              local current = vim.api.nvim_get_current_tabpage()
              for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
                if tab ~= current then
                  vim.api.nvim_win_call(vim.api.nvim_tabpage_get_win(tab), function()
                    vim.cmd.redraw({ bang = true })
                  end)
                end
              end
              vim.cmd.redraw({ bang = true })
            ]],
              {},
            })
          elseif message[2] == 2 then
            send(3, "nvim_ui_detach", {})
          else
            detached = true
          end
        end
      end
    end)
    send(1, "nvim_ui_attach", { width, height, { ext_linegrid = true } })
  end
  if port then
    stream:connect("127.0.0.1", tonumber(port), accept)
  else
    stream:connect(windows and address:gsub("/", "\\") or address, accept)
  end
  vim.wait(2000, function()
    return detached or failure ~= nil
  end)
  stream:close()
  if not detached then
    fail(failure or "Workspace grid refresh timed out")
  end
end

local function wake(channel)
  local mode = vim.rpcrequest(channel, "nvim_get_mode")
  if mode.blocking and mode.mode == "r" then
    vim.rpcnotify(channel, "nvim_input", "<CR>")
  end
end

local function verify(channel, target)
  if target.pid then
    return vim.rpcrequest(
      channel,
      "nvim_exec_lua",
      [[
      local pid, wsl = ...
      return vim.uv.os_getpid() == pid and (vim.fn.has('win32') == 0 or not wsl)
    ]],
      { target.pid, target.distro ~= nil }
    )
  end
  return not target.distro or vim.rpcrequest(channel, "nvim_eval", "get(g:, 'local_workspace_id', '')") == target.id
end

local function prepare(host, args)
  local target = args.target
  if args.path then
    local path = directory(args.path) or directory((args.path:gsub("\\ ", " ")))
    if not path then
      fail("Workspace directory does not exist: " .. args.path)
    end
    target = target_for(host, path)
  end
  if same_address(target.address, args.source.address) then
    return
  end
  local bridging = target.pid and target.distro and not target.address
  if bridging then
    local address, detail = wsl_result(wsl_call(target.distro, "bridge_wsl", { host, target }))
    if not address then
      fail("Could not connect to Neovim in " .. target.distro .. (detail ~= "" and ("\n" .. detail) or ""))
    end
    target.address = address
  elseif target.distro and not args.previous and not target.pid then
    local saved = read_target(host, target.id .. ".json")
    target.address = saved and saved.address
  end
  local channel = connection(target.address, true)
  local stderr
  if not channel and not bridging then
    if args.previous or target.pid then
      fail(args.previous and "The previous workspace is no longer running" or "The Neovim session is no longer running")
    end
    stderr = start(host, target)
  end

  -- WSL may publish its Windows localhost forward after serverstart returns.
  local ready = vim.wait(bridging and 2000 or 8000, function()
    if not channel then
      if target.distro and not args.previous and not target.pid then
        local saved = read_target(host, target.id .. ".json")
        target.address = saved and saved.address
      end
      channel = connection(target.address, true)
      if not channel then
        return false
      end
    end
    if target.pid then
      return true
    end
    wake(channel)
    return args.previous or vim.rpcrequest(channel, "nvim_eval", "get(g:, 'local_workspace_ready', 0)") == 1
  end, 50)
  if not ready or not verify(channel, target) then
    local detail = stderr and stderr() or ""
    fail(
      "Workspace did not respond at " .. (target.path or target.address) .. (detail ~= "" and ("\n" .. detail) or "")
    )
  end
  if same_address(target.address, args.source.address) then
    return
  end
  if args.multigrid then
    local size =
      vim.rpcrequest(channel, "nvim_eval", "get(g:, 'neovide', 0) && empty(nvim_list_uis()) ? [&columns, &lines] : []")
    if #size > 0 then
      reset_grid(target.address, size[1], size[2])
    end
  end
  local ui = vim.fs.joinpath(vim.fs.dirname(module_path), "workspace_ui.lua")
  vim.rpcrequest(channel, "nvim_exec_lua", table.concat(vim.fn.readfile(ui), "\n"), {
    args.source,
    not target.pid and target.path or "",
    args.gui or false,
    target.pid and not target.distro and host.module or nil,
  })
  if target.path and not args.previous and not target.distro and not target.pid then
    register(host, target)
  end
  return target.address
end

-- :qall can close these buffer types even when they are marked modified.
local dirty_buffers = [[len(filter(getbufinfo({'bufmodified': 1}), ]]
  .. [[{_, buf -> index(['nofile', 'nowrite', 'terminal'], getbufvar(buf.bufnr, '&buftype')) == -1}))]]

local function stop_channel(target)
  local channel = connection(target.address, true)
  if not channel then
    return
  end
  wake(channel)
  if
    not verify(channel, target) or vim.rpcrequest(channel, "nvim_eval", "get(g:, 'local_workspace_ready', 0)") ~= 1
  then
    fail("Could not verify workspace " .. target.path)
  end
  if vim.rpcrequest(channel, "nvim_eval", dirty_buffers) > 0 then
    fail("Save changes in workspace " .. target.path .. " before stopping it")
  end
  return channel
end

local function stop_targets(targets)
  local channels = {}
  for _, target in ipairs(targets) do
    channels[#channels + 1] = stop_channel(target)
  end
  for _, channel in ipairs(channels) do
    vim.rpcnotify(channel, "nvim_command", "qall")
  end
  local stopped = vim.wait(3000, function()
    targets = vim.tbl_filter(function(target)
      return listening(target.address)
    end, targets)
    return #targets == 0
  end, 50)
  if not stopped then
    fail("Could not stop workspaces: " .. table.concat(
      vim.tbl_map(function(target)
        return target.path
      end, targets),
      ", "
    ))
  end
end

local function force_stop_linux(distro)
  local command = distro and { "wsl.exe", "--distribution", distro, "--cd", "/", "--exec" } or {}
  vim.list_extend(command, { "sh", "-c", [[uid=$(id -u) && exec pkill -KILL -u "$uid" -x nvim]] })
  local result = vim.system(command):wait(5000)
  local detail = vim.trim(result.stderr or "")
  if result.code ~= 0 and (result.code ~= 1 or detail ~= "") then
    fail("Could not stop Neovim in " .. (distro or "Linux") .. (detail ~= "" and ("\n" .. detail) or ""))
  end
end

local function running_distros(strict)
  if vim.fn.executable("wsl.exe") ~= 1 then
    return {}
  end
  local result = vim.system({ "wsl.exe", "--list", "--running", "--quiet" }):wait(5000)
  local output = result.stdout or ""
  if result.code ~= 0 then
    local message = (output .. (result.stderr or "")):gsub("\0", "")
    if
      strict
      and not message:find("WSL_E_WSL_NOT_INSTALLED", 1, true)
      and not message:find("WSL_E_DEFAULT_DISTRO_NOT_FOUND", 1, true)
      and not message:find("0x8007019e", 1, true)
    then
      fail("Could not list running WSL distributions")
    end
    return {}
  end
  if output:find("\0", 1, true) then
    output = vim.iconv(output, "utf-16le", "utf-8")
  end
  return vim.split(vim.trim(output:gsub("^\239\187\191", "")), "\r?\n", { trimempty = true })
end

local function force_stop_windows()
  for _, distro in ipairs(running_distros(true)) do
    -- Each WSL launcher can itself be a Windows Neovim process. Stop Linux first.
    force_stop_linux(distro)
  end

  local username = vim.env.USERNAME
  if not username or username == "" then
    fail("Could not determine the Windows account")
  end
  local domain = vim.env.USERDOMAIN or ""
  local account = domain ~= "" and (domain .. "\\" .. username) or username
  local result = vim
    .system({
      "taskkill.exe",
      "/F",
      "/IM",
      "nvim.exe",
      "/FI",
      "USERNAME eq " .. account,
      "/FI",
      "PID ne " .. uv.os_getpid(),
    })
    :wait(5000)
  if result.code ~= 0 then
    fail("Could not stop Windows Neovim processes\n" .. vim.trim((result.stderr or "") .. (result.stdout or "")))
  end
end

local function items(host, args, emit)
  local entries, seen, running, excluded = {}, {}, {}, {}
  local function add(target, status, key)
    key = key or target.id
    if seen[key] or (status == "Stopped" and running[target.id]) then
      return
    end
    seen[key] = true
    if status ~= "Stopped" then
      running[target.id] = true
    end
    local platform = target.distro and ("WSL " .. target.distro) or (windows and "Windows" or "Linux")
    local path = target.linux or vim.fn.fnamemodify(target.path, ":~")
    if windows and not target.distro then
      path = path:gsub("/", "\\")
    end
    entries[#entries + 1] = {
      text = table.concat({ path, platform, status, target.pid or "" }, " "),
      target = target,
      path = path,
      linux = target.distro ~= nil or not windows,
      status = status,
    }
  end

  local function add_session(session, distro)
    local prefix = distro and ("//wsl.localhost/" .. distro) or ""
    local cwd = distro and session.cwd or vim.fs.normalize(session.cwd, { expand_env = false })
    local target = target_for(host, prefix .. cwd)
    target.pid = session.pid
    target.address = not distro and session.address or nil
    target.socket = distro and session.address or nil
    add(target, "Running", (distro or "") .. ":" .. target.pid)
  end

  local order = { Current = 1, Running = 2, Stopped = 3 }
  local function sorted()
    table.sort(entries, function(a, b)
      if a.status ~= b.status then
        return order[a.status] < order[b.status]
      end
      return a.text:lower() < b.text:lower()
    end)
    return entries
  end

  local current_registered
  for _, target in ipairs(registered(host)) do
    if listening(target.address) then
      local current = same_address(target.address, args.source.address)
      current_registered = current_registered or current
      excluded[target.address] = true
      add(target, current and "Current" or "Running")
    end
  end
  excluded[args.source.address] = true
  local root = args.source.path or (windows and wsl_path(args.cwd) and args.cwd) or directory(args.cwd)
  if root and not current_registered then
    local current = target_for(host, root)
    current.address, current.pid = args.source.address, args.source.pid
    add(current, "Current", current.address)
  end
  for _, session in ipairs(discover(excluded)) do
    add_session(session)
  end

  local function add_directory(path)
    add(target_for(host, path), "Stopped")
  end
  if args.cwd ~= root then
    local cwd = (windows and wsl_path(args.cwd) and args.cwd) or directory(args.cwd)
    if cwd then
      add_directory(cwd)
    end
  end

  local wsl_roots = {}
  local roots = vim.fs.joinpath(host.config, "workspace-roots")
  if not windows and vim.fn.filereadable(roots) == 0 then
    roots = vim.fn.fnamemodify(vim.fs.joinpath(vim.env.XDG_CONFIG_HOME or "~/.config", ".allmux"), ":p")
  end
  if vim.fn.filereadable(roots) == 1 then
    for _, line in ipairs(vim.fn.readfile(roots)) do
      local path = vim.trim(line):gsub("^\239\187\191", "")
      if path ~= "" and not path:match("^#") then
        local distro, linux
        if windows then
          distro, linux = wsl_path(path)
        end
        if distro then
          local key = distro:lower()
          wsl_roots[key] = wsl_roots[key] or { distro = distro, paths = {} }
          table.insert(wsl_roots[key].paths, linux)
        else
          scan_root(path, add_directory)
        end
      end
    end
  end
  if windows then
    if emit then
      emit(sorted())
    end
    local workers = {}
    local function scan_wsl(distro, paths)
      local skip = {}
      if args.source.socket and distro:lower() == args.source.distro:lower() then
        skip[args.source.socket] = true
      end
      local ok, process = pcall(wsl_call, distro, "scan_wsl", { paths, skip })
      if ok then
        workers[distro] = process
      end
    end
    for _, wsl in pairs(wsl_roots) do
      scan_wsl(wsl.distro, wsl.paths)
    end
    for _, distro in ipairs(running_distros(false)) do
      if not wsl_roots[distro:lower()] then
        scan_wsl(distro, {})
      end
    end
    for distro, process in pairs(workers) do
      local result = wsl_result(process)
      if result then
        for _, session in ipairs(result.sessions) do
          add_session(session, distro)
        end
        for _, path in ipairs(result.paths) do
          add_directory("//wsl.localhost/" .. distro .. path)
        end
      end
    end
  end
  return sorted()
end

function M.dispatch(op, host, args, emit)
  vim.env.NVIM_APPNAME = host.app ~= "" and host.app or nil
  if op == "items" then
    return items(host, args, emit)
  elseif op == "prepare" then
    return prepare(host, args)
  elseif op == "stop" then
    stop_targets({ args.target })
  elseif op == "force_stop_all" then
    force_stop_windows()
  elseif op == "stop_all" then
    stop_targets(vim.tbl_filter(function(target)
      return not same_address(target.address, args.source.address)
    end, registered(host)))
  end
end

-- A Windows frontend must be able to reach the destination. Run that check and
-- the registry operations on Windows even when the current editor is in WSL.
local function host_call(op, args, callback, on_error, on_partial)
  local host = wsl_boot and wsl_boot.host or local_host
  local executable = wsl_boot and wsl_boot.nvim or host.nvim
  local input = ([[
    -- A detached Windows launcher must not hold the helper's reply pipes open.
    vim.uv.disable_stdio_inheritance()
    if vim.v.servername ~= "" then vim.fn.serverstop(vim.v.servername) end
    local module, op, host, args = unpack(vim.json.decode(%q))
    local function emit(entries)
      io.write(vim.json.encode(entries), "\n")
      io.stdout:flush()
    end
    local ok, result = pcall(dofile(module).dispatch, op, host, args, %s)
    io.write(vim.json.encode({ ok = ok, result = result }))
  ]]):format(vim.json.encode({ host.module, op, host, args }), on_partial and "emit" or "nil")
  local command = { executable, "--headless", "-u", "NONE", "-i", "NONE", "-l", "-" }
  local force = op == "force_stop_all"
  if force and wsl_boot then
    -- Detach on Windows so the worker survives the end of the WSL interop session.
    input = ([[
      vim.uv.disable_stdio_inheritance()
      local command = { vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", "-" }
      local result = vim.system(command, { stdin = %q, detach = true }):wait()
      io.write(result.stdout or "")
      io.stderr:write(result.stderr or "")
      if result.code ~= 0 then vim.cmd.cquit() end
    ]]):format(input)
  end
  local opts = { stdin = input, text = true, detach = force, timeout = not force and 12000 or nil }
  local buffer = ""
  if on_partial then
    opts.stdout = function(_, chunk)
      if not chunk then
        return
      end
      buffer = buffer .. chunk
      local newline = buffer:find("\n", 1, true)
      if newline then
        local line = buffer:sub(1, newline - 1)
        buffer = buffer:sub(newline + 1)
        vim.schedule(function()
          local ok, entries = pcall(vim.json.decode, line)
          if ok then
            on_partial(entries)
          end
        end)
      end
    end
  end
  local function finish(result)
    local decoded, reply = pcall(vim.json.decode, result.stdout or buffer)
    if result.code ~= 0 or not decoded then
      local detail = vim.trim(result.stderr or "")
      vim.notify(detail ~= "" and detail or "Workspace operation timed out or could not run", vim.log.levels.ERROR)
    elseif not reply.ok then
      vim.notify(reply.result, vim.log.levels.ERROR)
    else
      callback(reply.result)
      return
    end
    if on_error then
      on_error()
    end
  end
  local ok, err = pcall(vim.system, command, opts, vim.schedule_wrap(finish))
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

local function source()
  local target = wsl_boot and wsl_boot.target
  return {
    address = target and target.address or (vim.v.servername ~= "" and vim.v.servername or vim.fn.serverstart()),
    path = vim.g.local_workspace_path,
    distro = target and target.distro,
    id = target and target.id,
    pid = target and target.pid,
    socket = target and target.socket,
  }
end

local function host_path(path)
  if wsl_boot and not wsl_path(path) and not path:match("^%a:[/\\]") and not path:match("^[/\\][/\\]") then
    local native = vim.fn.fnamemodify(path, ":p")
    if native ~= "/" then
      native = native:gsub("/$", "")
    end
    return "//wsl.localhost/" .. wsl_boot.target.distro .. native
  end
  return path
end

local attaching = false

local function ui_ffi()
  local version = vim.version()
  if version.major ~= 0 or version.minor ~= 12 or version.patch ~= 6 then
    return
  end
  local ffi = require("ffi")
  ffi.cdef([[
    extern uint64_t current_ui;
    void nvim__chan_set_detach(uint64_t channel_id, bool detach, void *err);
  ]])
  return ffi
end

local function keep_embedded_server(channel)
  -- In 0.12.6 the RPC form can only mark its own channel. The Windows binary
  -- exports the same function with the target channel as its first argument.
  return pcall(function()
    ui_ffi().C.nvim__chan_set_detach(channel, true, nil)
  end)
end

local function connect_ui(address, ui_channel)
  -- Send only to the initiating UI, even if another UI became active while
  -- preparing the switch. This also avoids the Windows :connect console.
  if ui_channel then
    local info = vim.api.nvim_get_chan_info(ui_channel)
    if not info.id then
      return
    end
    local detachable = info.stream == "socket"
      or (windows and info.stream == "stdio" and keep_embedded_server(ui_channel))
    if detachable then
      if pcall(vim.rpcnotify, ui_channel, "redraw", { "connect", { address } }) then
        vim.fn.chanclose(ui_channel)
        return
      end
    end
  end
  vim.cmd.connect({ args = { address }, magic = { file = false, bar = false } })
end

local function attach(args, picker)
  if attaching then
    fail("A workspace switch is already in progress")
  end
  args.source = source()
  local uis = vim.api.nvim_list_uis()
  local active = #uis == 1 and uis[1].chan or nil
  if not active then
    local ok, channel = pcall(function()
      return tonumber(ui_ffi().C.current_ui)
    end)
    active = ok and channel > 0 and channel or nil
  end
  local ui_channel
  for _, ui in ipairs(uis) do
    local client = vim.api.nvim_get_chan_info(ui.chan).client
    local gui = client and client.name == "neovide"
    if ui.chan == active and client and (gui or client.name == "nvim-tui") then
      ui_channel = ui.chan
    end
    if not active or ui.chan == active then
      args.multigrid = args.multigrid or ui.ext_multigrid or vim.g.local_workspace_composited_ui == ui.chan
    end
    if gui and (not active or ui.chan == active) then
      args.gui = {
        background = vim.o.background,
        font = vim.o.guifont,
        scale = vim.g.neovide_scale_factor or 1,
      }
    end
  end
  local function release()
    attaching = false
  end
  attaching = host_call("prepare", args, function(address)
    release()
    if address and #vim.api.nvim_list_uis() > 0 and (not picker or not picker.closed) then
      if picker then
        picker:close()
      end
      connect_ui(address, ui_channel)
    end
  end, release)
end

local function pick()
  local args = { source = source(), cwd = host_path(vim.fn.getcwd()) }
  local picker, entries
  local reloading = false
  local function update(updated)
    entries = updated
    if picker then
      if not picker.closed then
        picker:refresh()
      end
      return
    end
    if #vim.api.nvim_list_uis() == 0 then
      return
    end
    vim.api.nvim_set_hl(0, "WorkspaceExternal", { fg = "#ff9e64", ctermfg = 208, default = true })
    picker = Snacks.picker.pick({
      title = "Workspaces",
      finder = function()
        return entries
      end,
      layout = { preset = "select", layout = { min_width = math.min(80, vim.o.columns - 4) } },
      actions = {
        stop_workspace = {
          desc = "Stop workspace",
          action = function(picker, item)
            if not item or item.status == "Stopped" or (item.target.pid and item.status ~= "Current") then
              return
            end
            if item.status == "Current" then
              picker:close()
              vim.cmd.qall()
              return
            end
            host_call("stop", { target = item.target }, function()
              reloading = true
              host_call("items", args, update)
            end)
          end,
        },
      },
      win = {
        input = { keys = { ["<C-x>"] = { "stop_workspace", mode = { "i", "n" } } } },
        list = { keys = { ["<C-x>"] = "stop_workspace" } },
      },
      format = function(item)
        local color = ({ Current = "DiagnosticInfo", Running = "DiagnosticOk", Stopped = "Comment" })[item.status]
        if item.status == "Running" and item.target.pid then
          color = "WorkspaceExternal"
        end
        local marker = ({ Current = "◉ ", Running = "● ", Stopped = "○ " })[item.status]
        return {
          { marker, color },
          { item.linux and "  " or "  ", "Directory" },
          { item.path },
        }
      end,
      confirm = function(picker, item)
        if item and item.status ~= "Current" then
          attach({ target = item.target }, picker)
        else
          picker:close()
        end
      end,
    })
  end
  local function initial(rows)
    if not reloading then
      update(rows)
    end
  end
  host_call("items", args, initial, nil, initial)
end

function M.setup()
  vim.api.nvim_create_user_command("Workspace", function(opts)
    if vim.fn.exists(":connect") ~= 2 or #vim.api.nvim_list_uis() == 0 then
      fail("Workspace requires an attached Neovim 0.12+ UI with :connect support")
    end
    if opts.args == "" then
      pick()
    else
      attach({ path = host_path(opts.args) })
    end
  end, { nargs = "?", complete = "dir", desc = "Switch workspace" })

  vim.keymap.set({ "n", "t" }, "<C-b>f", "<Cmd>Workspace<CR>", { desc = "Find workspace" })
  vim.keymap.set({ "n", "t" }, "<C-b>L", function()
    local previous = vim.g.local_workspace_previous
    if not previous or previous == "" then
      vim.notify("No previous workspace")
      return
    end
    attach({ target = type(previous) == "string" and { address = previous } or previous, previous = true })
  end, { desc = "Switch to previous workspace" })

  vim.api.nvim_create_user_command("WorkspaceStopAll", function(opts)
    if opts.bang then
      if windows or wsl_boot then
        host_call("force_stop_all", {}, function() end)
      else
        force_stop_linux()
      end
      return
    end
    local function can_stop()
      return vim.fn.eval(dirty_buffers) == 0
    end
    if not can_stop() then
      fail("Save changes in the current editor before stopping workspaces")
    end
    host_call("stop_all", { source = source() }, function()
      if can_stop() then
        vim.cmd.qall()
      else
        vim.notify("Save changes in the current editor before stopping workspaces", vim.log.levels.WARN)
      end
    end)
  end, { bang = true, desc = "Stop workspaces (bang terminates all Neovim processes for this user)" })
end

return M
