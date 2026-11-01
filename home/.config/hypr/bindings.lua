-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- Logitech MX Keys examples:
-- o.bind("SUPER + SHIFT + S", nil, "omarchy-capture-screenshot")
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- SUPER+SHIFT+LEFT/RIGHT previously swapped the focused window.
-- Move the current workspace between monitors instead; retire the old shortcuts.
hl.unbind("SUPER + SHIFT + LEFT")
hl.unbind("SUPER + SHIFT + RIGHT")
hl.unbind("SUPER + SHIFT + ALT + LEFT")
hl.unbind("SUPER + SHIFT + ALT + RIGHT")
o.bind("SUPER + SHIFT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
o.bind("SUPER + SHIFT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))

-- SUPER+S previously toggled the scratchpad; SUPER+ALT+SPACE opened the Apps menu.
hl.unbind("SUPER + S")
hl.unbind("SUPER + ALT + SPACE")
o.bind("SUPER + S", "Apps menu", "omarchy-menu toggle apps")

-- Keep SUPER+W and also close the focused window with ALT+F4.
o.bind("ALT + F4", "Close window", hl.dsp.window.close())

-- SUPER+V previously performed universal paste; use it for clipboard history.
hl.unbind("SUPER + V")
hl.unbind("SUPER + CTRL + V")
o.bind("SUPER + V", "Clipboard manager", "omarchy-shell shell toggle omarchy.clipboard")

-- SUPER+L previously toggled the workspace layout; use it to lock the system.
hl.unbind("SUPER + L")
o.bind("SUPER + L", "Lock system", "omarchy system lock")

-- Switch layouts with AltGr + Left Shift, in either key-press order.
-- Right Alt acts as Alt via lv3:ralt_alt; Left Alt + Left Shift also works.
o.bind("ALT + Shift_L", "Switch input language", "hyprctl switchxkblayout all next")
o.bind("SHIFT + Alt_R", "Switch input language", "hyprctl switchxkblayout all next")
