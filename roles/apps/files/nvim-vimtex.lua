-- Managed by workstation-arch (roles/apps/files/nvim-vimtex.lua) - do not
-- edit by hand; personal additions belong in another file under lua/.
-- Deployed as lua/plugins/vimtex.lua: lazy.nvim (LazyVim's plugin manager)
-- picks it up through the starter's `{ import = "plugins" }`.
--
-- VimTeX for .tex files: latexmk (TeX Live, roles/development) compiles,
-- Zathura (roles/apps) shows the PDF. Deliberately no LaTeX LSP (texlab) -
-- LazyVim's lang.tex extra would add one through Mason.
-- Commands on the local leader (LazyVim: "\"), only in .tex buffers:
--   \ll compile on/off (latexmk -pvc: rebuilds on every save)
--   \lk stop   \lc clean auxiliary files   \lv forward search to Zathura
--   \le errors \lt table of contents       (README "LaTeX")

return {
  {
    "lervag/vimtex",
    -- VimTeX loads itself per filetype (ftplugin); lazy-loading it breaks
    -- that and backward search, so its documentation says not to.
    lazy = false,
    init = function()
      vim.g.tex_flavor = "latex" -- an ambiguous .tex is LaTeX, not plain TeX
      vim.g.vimtex_compiler_method = "latexmk" -- continuous (-pvc), -synctex=1 by default
      -- zathura_simple: Zathura with SyncTeX forward search, without
      -- xdotool (X11 only - this is a Wayland session).
      vim.g.vimtex_view_method = "zathura_simple"
    end,
  },
}
