-- Run on the destination editor before the frontend reconnects.
local source, path, gui, module = ...
vim.g.local_workspace_previous = source
if path ~= "" then
  vim.g.local_workspace_path = path
end
if module and vim.fn.exists(":Workspace") == 0 then
  dofile(module).setup()
end
if not gui then
  return
end

local function is_gui(channel)
  local client = vim.api.nvim_get_chan_info(channel).client
  return client and client.name == "neovide"
end

local uis = vim.api.nvim_list_uis()
for _, ui in ipairs(uis) do
  if is_gui(ui.chan) then
    return
  end
end

local previous_exit_hooks = {}
for _, hook in ipairs(vim.api.nvim_get_autocmds({ event = "VimLeavePre" })) do
  if hook.id then
    previous_exit_hooks[hook.id] = true
  end
end

local function guard_gui_exit(channel)
  -- Neovide's injected quit hook can outlive its RPC connection.
  for _, hook in ipairs(vim.api.nvim_get_autocmds({ event = "VimLeavePre" })) do
    if
      hook.id
      and not previous_exit_hooks[hook.id]
      and type(hook.callback) == "function"
      and debug.getinfo(hook.callback, "S").source == "<nvim>"
      and debug.getupvalue(hook.callback, 1) == "rpcrequest"
    then
      vim.api.nvim_del_autocmd(hook.id)
      vim.api.nvim_create_autocmd("VimLeavePre", {
        nested = true,
        pattern = hook.pattern,
        callback = function(event)
          if is_gui(channel) then
            return hook.callback(event)
          end
        end,
      })
    end
  end
end

local function use_compositor(ui)
  -- With a terminal attached, 0.12.6 negotiates one grid but leaves a
  -- multigrid GUI outside its compositor. Keep the same connection and
  -- register it as single-grid, using the ABI for this exact release.
  local version = vim.version()
  assert(version.major == 0 and version.minor == 12 and version.patch == 6)
  local ffi = require("ffi")
  assert(ffi.abi("64bit"))
  if not pcall(ffi.typeof, "WorkspaceUiOptions") then
    ffi.cdef([[
      typedef struct { const char *data; size_t size; } WorkspaceUiString;
      typedef struct { int type; union { bool boolean; size_t storage[3]; } data; } WorkspaceUiValue;
      typedef struct { WorkspaceUiString key; WorkspaceUiValue value; } WorkspaceUiOption;
      typedef struct { size_t size; size_t capacity; WorkspaceUiOption *items; } WorkspaceUiOptions;
      typedef struct { int type; char *msg; } WorkspaceUiError;
      void nvim_ui_detach(uint64_t channel, WorkspaceUiError *err);
      void nvim_ui_attach(uint64_t channel, int64_t width, int64_t height,
                          WorkspaceUiOptions options, WorkspaceUiError *err);
      void api_clear_error(WorkspaceUiError *err);
    ]])
  end
  local fields = { "ext_linegrid", "ext_hlstate", "ext_messages" }
  local entries = ffi.new("WorkspaceUiOption[?]", #fields)
  for i, name in ipairs(fields) do
    local entry = entries[i - 1]
    entry.key.data, entry.key.size = name, #name
    entry.value.type, entry.value.data.boolean = 1, ui[name]
  end
  local options = ffi.new("WorkspaceUiOptions", { #fields, #fields, entries })
  local err = ffi.new("WorkspaceUiError[1]", { { -1, nil } })
  local detach, attach, clear_error = ffi.C.nvim_ui_detach, ffi.C.nvim_ui_attach, ffi.C.api_clear_error
  detach(ui.chan, err)
  if err[0].type == -1 then
    attach(ui.chan, ui.width, ui.height, options, err)
  end
  if err[0].type ~= -1 then
    clear_error(err)
    error("Could not register Neovide with the compositor")
  end
  vim.g.local_workspace_composited_ui = ui.chan
end

local shared_grid = vim.tbl_contains(uis, function(ui)
  return not ui.ext_multigrid
end, { predicate = true })
local ui2 = shared_grid and package.loaded["vim._core.ui2"]
local paused = ui2 and ui2.cfg.enable and ui2.msg ~= nil
local function restore_cmdline()
  if paused then
    paused = false
    ui2.enable({ enable = true })
  end
end

-- Recreate the experimental cmdline floats after the grid is registered.
-- Existing floats can otherwise cover the first row of the new GUI.
if paused then
  ui2.enable({ enable = false })
  vim.defer_fn(restore_cmdline, 3000)
end

-- Apply the current background before Neovide reads the OS preference.
if gui.background then
  vim.o.background = gui.background
end
vim.o.guifont = gui.font
if not vim.g.neovide_channel_id and (vim.g.neovide_scale_factor or 1) ~= gui.scale then
  vim.g.neovide_scale_factor = gui.scale
end
vim.api.nvim_create_autocmd("UIEnter", {
  group = vim.api.nvim_create_augroup("WorkspaceGui", { clear = true }),
  callback = function()
    local channel = vim.v.event.chan
    if not is_gui(channel) then
      return
    end
    guard_gui_exit(channel)
    vim.o.guifont = gui.font
    if (vim.g.neovide_scale_factor or 1) ~= gui.scale then
      vim.g.neovide_scale_factor = gui.scale
    end
    if shared_grid then
      vim.schedule(function()
        for _, ui in ipairs(vim.api.nvim_list_uis()) do
          if ui.chan == channel and ui.ext_multigrid and not pcall(use_compositor, ui) then
            vim.notify("Use Neovide --no-multigrid when sharing a terminal session", vim.log.levels.WARN)
          end
        end
        vim.schedule(restore_cmdline)
      end)
    end
    return true
  end,
})
