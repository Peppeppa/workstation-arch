-- The workstation-arch theme interface for Neovim: the colorscheme of the
-- active workstation theme. The `theme` helper renders the spec on every
-- theme change (~/.config/workstation/theme/neovim.lua - Neovim ports of all
-- workstation themes + LazyVim's colorscheme) and tells running Neovims to
-- re-apply it. Delete this file to choose colorschemes yourself.
local spec = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config"))
  .. "/workstation/theme/neovim.lua"
if not (vim.uv or vim.loop).fs_stat(spec) then
  return {}
end
return dofile(spec)
