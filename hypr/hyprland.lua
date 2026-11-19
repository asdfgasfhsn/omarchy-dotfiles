-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Omarchy's Quake console refits its gaps on every hop between screens. With
-- two differently sized screens the gaps change on each hop, and re-applying
-- them makes the scrolling layout pull the focused window fully into view: a
-- column you hovered at the shared edge slides the whole row along. Only let
-- that hook run while the console is open. Opening it still sizes it, through
-- the console's own workspace.special_active hook.
do
  local on = hl.on
  hl.on = function(event, callback, ...)
    local source = debug.getinfo(callback, "S").source
    if event == "monitor.focused" and source:find("qconsole.lua", 1, true) then
      local inner = callback
      callback = function(...)
        local console = hl.get_workspace("special:qconsole")
        if console and console.visible then return inner(...) end
      end
    end
    return on(event, callback, ...)
  end
  require("default.hypr.omarchy")
  hl.on = on
end

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")


-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Glass surfaces: summoned shell popups (polkit, clipboard, emojis) use the
-- bar's sans instead of monospace. Takes effect on the next shell start.
hl.env("OMARCHY_MENU_FONT", "Adwaita Sans")

do local p = os.getenv("HOME") .. "/.config/hypr/theme_studio_border.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end  -- Theme Studio: window border colors (written by its panel)
do local p = os.getenv("HOME") .. "/.config/hypr/recessed_windows.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end  -- Depth: recessed/raised windows (written by its panel)

do local d = debug.getinfo(1, "S").source:match("^@(.*/)") or os.getenv("HOME") .. "/.config/hypr/"; local p = d .. "tricky-tiles.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end -- Tricky Tiles (remove via its panel)
do local d = debug.getinfo(1, "S").source:match("^@(.*/)") or os.getenv("HOME") .. "/.config/hypr/"; local p = d .. "softly.lua"; local f = io.open(p); if f then f:close(); dofile(p) end end -- Softly (remove via its panel)
