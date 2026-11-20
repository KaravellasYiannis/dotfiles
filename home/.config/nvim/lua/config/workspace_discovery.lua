local uv = vim.uv
local windows = vim.fn.has("win32") == 1

return function(excluded)
  local patterns = { "^nvim%.(%d+)%.%d+$" }
  if vim.env.NVIM_APPNAME and vim.env.NVIM_APPNAME ~= "nvim" then
    patterns[2] = "^" .. vim.pesc(vim.env.NVIM_APPNAME) .. "%.(%d+)%.%d+$"
  end
  local sessions, streams, scanned = {}, {}, {}
  local pending = 0
  local request = vim.mpack.encode({
    0,
    1,
    "nvim_exec_lua",
    {
      [[
      if vim.v.vim_did_enter == 1 then
        return { pid = vim.uv.os_getpid(), cwd = vim.fn.getcwd(-1, -1) }
      end
    ]],
      {},
    },
  })

  local function probe(address, pid)
    if excluded[address] or pid == uv.os_getpid() then
      return
    end
    local stream, unpack = uv.new_pipe(false), vim.mpack.Unpacker()
    streams[stream] = true
    pending = pending + 1
    local function close()
      if streams[stream] then
        streams[stream] = nil
        pending = pending - 1
        stream:close()
      end
    end
    local function read(err, data)
      if err or not data then
        close()
        return
      end
      local offset = 1
      while offset <= #data do
        local ok, reply, next_offset = pcall(unpack, data, offset)
        if not ok then
          close()
          return
        end
        offset = next_offset
        if type(reply) == "table" and reply[1] == 1 and reply[2] == 1 then
          local session = reply[4]
          if
            reply[3] == vim.NIL
            and type(session) == "table"
            and session.pid == pid
            and type(session.cwd) == "string"
          then
            session.address = address
            sessions[#sessions + 1] = session
          end
          close()
          return
        end
      end
    end
    local ok, handle = pcall(stream.connect, stream, address, function(err)
      if err then
        close()
        return
      end
      stream:read_start(read)
      stream:write(request, function(write_error)
        if write_error then
          close()
        end
      end)
    end)
    if not ok or not handle then
      close()
    end
  end

  local function scan(dir, nested)
    if scanned[dir] then
      return
    end
    scanned[dir] = true
    local files = uv.fs_scandir(dir)
    if not files then
      return
    end
    for name, kind in uv.fs_scandir_next, files do
      local path = windows and (dir .. name) or (dir .. "/" .. name)
      if nested and kind == "directory" then
        scan(path)
      elseif windows or kind == "socket" then
        for _, pattern in ipairs(patterns) do
          local pid = tonumber(name:match(pattern))
          if pid then
            probe(path, pid)
            break
          end
        end
      end
    end
  end

  if windows then
    scan([[\\.\pipe\]])
  else
    scan(vim.fn.stdpath("run"))
    scan("/run/user/" .. uv.getuid())
    local user = uv.os_get_passwd()
    if user then
      scan("/tmp/nvim." .. user.username, true)
    end
  end
  -- All candidates share one deadline, including editors waiting at a prompt.
  vim.wait(50, function()
    return pending == 0
  end, 5)
  for stream in pairs(streams) do
    streams[stream] = nil
    stream:close()
  end
  return sessions
end
