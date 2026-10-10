-- Managed by workstation-arch (roles/apps/files/nvim-languages.lua) - do not
-- edit by hand; personal additions belong in another file under lua/.
-- Deployed as lua/plugins/workstation-languages.lua. README "Shell and
-- Neovim" -> "Languages".
--
-- The languages LazyVim's own extras cover are switched on in lazyvim.json
-- (Ansible adds them there, next to any extras you chose with :LazyExtras):
-- lang.java/python/markdown/ansible/yaml/clangd/rust/json/toml/docker/
-- typescript, dap.core, formatting.prettier. This file only adds what no
-- extra provides - one server per language, never a second one:
--   HTML html (vscode-html-language-server), CSS cssls, Bash bashls
--   (+ shellcheck through bashls, shfmt through LazyVim's conform),
--   Assembly asm_lsp (instruction/register docs + completion for GAS/NASM
--   and others - NOT a semantic checker: errors come from the assembler)
--   Python: pyright uses the project's .venv when there is one
--   LaTeX: VimTeX's own completion (omnifunc) in blink.cmp - VimTeX stays
--   as configured in vimtex.lua, still no texlab
-- Ansible vs. YAML: nvim-ansible (lang.ansible) marks Ansible files
-- (roles/*/tasks, handlers, playbooks/...) as yaml.ansible -> ansiblels
-- (+ ansible-lint); every other YAML file -> yamlls with SchemaStore.
-- yamlls does not attach to yaml.ansible, so a file never gets both.
--
-- Servers and tools come from Mason (installed by the bootstrap, list in
-- roles/apps/defaults apps_nvim_mason_packages); compilers and toolchains
-- (gcc, JDK, rust + rust-analyzer, nodejs for Mason's npm packages) from
-- pacman.

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "asm", "nasm", "bash", "c", "css", "dockerfile", "html", "java",
        "javascript", "json", "lua", "markdown", "markdown_inline", "python",
        "rust", "toml", "yaml",
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        html = {},
        cssls = {},
        bashls = {},
        asm_lsp = {},
        pyright = {
          -- A project's own .venv (uv, python -m venv) wins over whatever
          -- Python is on PATH - imports resolve against the project.
          before_init = function(_, config)
            local root = config.root_dir
            if root and vim.uv.fs_stat(root .. "/.venv/bin/python") then
              config.settings = config.settings or {}
              config.settings.python = vim.tbl_deep_extend("force", config.settings.python or {}, {
                pythonPath = root .. "/.venv/bin/python",
              })
            end
          end,
        },
      },
    },
  },

  {
    "saghen/blink.cmp",
    optional = true,
    opts = {
      sources = {
        per_filetype = {
          tex = { inherit_defaults = true, "omni" },
        },
      },
    },
  },
}
