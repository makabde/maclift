-- Treesitter Configuration for Syntax Highlighting

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      -- Ensure these parsers are installed
      vim.list_extend(opts.ensure_installed or {}, {
        -- Elixir ecosystem
        "elixir",
        "heex",
        "eex",

        -- Web development
        "html",
        "css",
        "scss",
        "javascript",
        "typescript",
        "tsx",
        "json",
        "yaml",

        -- Config and documentation
        "lua",
        "vim",
        "vimdoc",
        "markdown",
        "markdown_inline",

        -- Shell and DevOps
        "bash",
        "dockerfile",

        -- Git
        "git_config",
        "gitcommit",
        "gitignore",
        "git_rebase",
      })

      -- Configure treesitter
      opts.highlight = { enable = true }
      opts.indent = { enable = true }
      opts.incremental_selection = {
        enable = true,
        keymaps = {
          init_selection = "<C-space>",
          node_incremental = "<C-space>",
          scope_incremental = false,
          node_decremental = "<bs>",
        },
      }

      -- Folding based on treesitter
      vim.opt.foldmethod = "expr"
      vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
      vim.opt.foldenable = false -- Don't fold by default
    end,
  },

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- Treesitter Context - Show sticky context (function/module/class)
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "VeryLazy",
    opts = {
      enable = true,
      max_lines = 3,
      min_window_height = 20,
      multiline_threshold = 1,
    },
  },
}
