-- Shadow Omarchy's monitor-owned workspace manager with native global actions.
-- Loaded through bootstrap's user-first module path; no ownership or renumbering.
o.workspaces = {
  focus = function(id)
    return hl.dsp.focus({ workspace = tostring(id) })
  end,
  move_window = function(id, follow)
    return hl.dsp.window.move({ workspace = tostring(id), follow = follow ~= false })
  end,
  move_to_monitor = function(direction)
    return hl.dsp.workspace.move({ monitor = direction })
  end,
  move_window_to_monitor = function(direction)
    return hl.dsp.window.move({ monitor = direction })
  end,
}

return o.workspaces
