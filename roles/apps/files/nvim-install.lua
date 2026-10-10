-- Managed by workstation-arch (roles/apps/files/nvim-install.lua) - do not edit.
-- Run by the bootstrap:
--   WS_MASON="pkg pkg ..." nvim --headless "+luafile <this>"
-- Installs the missing lazy.nvim plugins (lazy's own install, e.g. those of
-- newly enabled extras), the missing Mason packages (the list from roles/apps
-- apps_nvim_mason_packages) and the missing Tree-sitter parsers (LazyVim's
-- resolved ensure_installed, i.e. its defaults + the enabled extras +
-- workstation-languages.lua), waits for both, then quits. Nothing that is
-- already installed is touched (no update). Last lines on stdout:
--   WS_RESULT {"plugins_installed": [...], "mason_installed": [...], "parsers_installed": [...], "failed": [...]}
--   WS_CHANGED yes|no
-- Exit 1 when something failed. Same effect as the first interactive start,
-- just before it.

local result = { plugins_installed = {}, mason_installed = {}, parsers_installed = {}, failed = {} }

local function finish()
  local changed = #result.plugins_installed + #result.mason_installed + #result.parsers_installed > 0
  io.stdout:write("WS_RESULT " .. vim.json.encode(result) .. "\n")
  io.stdout:write("WS_CHANGED " .. (changed and "yes" or "no") .. "\n")
  vim.cmd(#result.failed > 0 and "cquit 1" or "qall!")
end

local ok, err = pcall(function()
  -- ---- lazy.nvim plugins ------------------------------------------------
  local Config = require("lazy.core.config")
  for name, p in pairs(Config.plugins) do
    if not p._.installed then table.insert(result.plugins_installed, name) end
  end
  if #result.plugins_installed > 0 then
    require("lazy").install({ wait = true, show = false })
    for _, name in ipairs(result.plugins_installed) do
      if not Config.plugins[name]._.installed then table.insert(result.failed, "plugin:" .. name) end
    end
  end

  require("lazy").load({ plugins = { "mason.nvim", "nvim-treesitter" } })

  -- ---- Mason ----------------------------------------------------------
  local registry = require("mason-registry")
  local refreshed = false
  registry.refresh(function() refreshed = true end)
  vim.wait(120000, function() return refreshed end, 200)

  local wanted = vim.split(vim.env.WS_MASON or "", "%s+", { trimempty = true })
  for _, name in ipairs(wanted) do
    local has, pkg = pcall(registry.get_package, name)
    if not has then
      table.insert(result.failed, "mason:" .. name .. " (unknown package)")
    elseif not pkg:is_installed() then
      table.insert(result.mason_installed, name)
      if not pkg:is_installing() then pkg:install() end
    end
  end
  -- Wait for ours and for whatever LazyVim's own mason config started.
  vim.wait(1800000, function()
    for _, p in ipairs(registry.get_all_packages()) do
      if p:is_installing() then return false end
    end
    return true
  end, 500)
  for _, name in ipairs(result.mason_installed) do
    if not registry.get_package(name):is_installed() then
      table.insert(result.failed, "mason:" .. name)
    end
  end

  -- ---- Tree-sitter parsers (nvim-treesitter main branch) ----------------
  local plugin = require("lazy.core.config").spec.plugins["nvim-treesitter"]
  local opts = require("lazy.core.plugin").values(plugin, "opts", false)
  local ts = require("nvim-treesitter")
  local installed = {}
  for _, lang in ipairs(ts.get_installed()) do installed[lang] = true end
  local missing = {}
  for _, lang in ipairs(opts.ensure_installed or {}) do
    if not installed[lang] then table.insert(missing, lang) end
  end
  if #missing > 0 then
    ts.install(missing, { summary = true }):wait(1800000)
    local now = {}
    for _, lang in ipairs(ts.get_installed()) do now[lang] = true end
    for _, lang in ipairs(missing) do
      if now[lang] then table.insert(result.parsers_installed, lang)
      else table.insert(result.failed, "parser:" .. lang) end
    end
  end
end)

if not ok then table.insert(result.failed, "error: " .. tostring(err)) end
finish()
