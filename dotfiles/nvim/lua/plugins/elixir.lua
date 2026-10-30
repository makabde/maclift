-- Elixir/Phoenix Development Configuration

return {
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- elixir-tools.nvim - Modern Elixir Development
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {
    "elixir-tools/elixir-tools.nvim",
    version = "*",
    event = { "BufReadPre", "BufNewFile" },
    ft = { "elixir", "heex", "eex" },
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      local elixir = require("elixir")
      local elixirls = require("elixir.elixirls")

      elixir.setup({
        -- Use ElixirLS (battle-tested, matching your VSCode setup)
        elixirls = {
          enable = true,
          settings = elixirls.settings({
            -- Enable Dialyzer (matching your VSCode dialyzerEnabled: true)
            dialyzerEnabled = true,
            dialyzerFlags = {
              "--ignore-exit-status",
              "--format",
              "dialyxir",
              "--ignore-warnings",
              ".dialyzer-ignore",
            },
            -- Enable test lenses
            enableTestLenses = true,
            -- Suggest specs
            suggestSpecs = true,
            -- Don't fetch deps automatically (manual control)
            fetchDeps = false,
            -- Mix env
            mixEnv = "dev",
            -- Mix target
            mixTarget = "host",
          }),
          on_attach = function(client, bufnr)
            -- Enable completion
            vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

            -- Keybindings
            local map = function(mode, lhs, rhs, desc)
              vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
            end

            -- LSP actions
            map("n", "gd", vim.lsp.buf.definition, "Go to definition")
            map("n", "gD", vim.lsp.buf.declaration, "Go to declaration")
            map("n", "gr", vim.lsp.buf.references, "Go to references")
            map("n", "gi", vim.lsp.buf.implementation, "Go to implementation")
            map("n", "K", vim.lsp.buf.hover, "Hover documentation")
            map("n", "<leader>ca", vim.lsp.buf.code_action, "Code actions")
            map("n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
            map("n", "<leader>cf", function()
              vim.lsp.buf.format({ async = false })
            end, "Format document")

            -- Diagnostics
            map("n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
            map("n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
            map("n", "<leader>cd", vim.diagnostic.open_float, "Show diagnostic")

            -- Elixir-specific
            if client.name == "elixirls" then
              map("n", "<leader>ep", "<cmd>ElixirFromPipe<cr>", "Elixir: From pipe")
              map("v", "<leader>ep", "<cmd>ElixirFromPipe<cr>", "Elixir: From pipe")
              map("n", "<leader>ei", "<cmd>ElixirToPipe<cr>", "Elixir: To pipe")
              map("v", "<leader>ei", "<cmd>ElixirToPipe<cr>", "Elixir: To pipe")
              map("n", "<leader>em", "<cmd>ElixirExpandMacro<cr>", "Elixir: Expand macro")
            end
          end,
        },

        -- Projectionist for smart file navigation
        projectionist = {
          enable = true,
        },

        -- Next LS (alternative, disabled by default)
        nextls = {
          enable = false,
        },

        -- Credo for linting (already included in LazyVim Elixir extra)
        credo = {
          enable = true,
        },
      })
    end,
  },

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- Disable default ElixirLS from LazyVim to avoid conflict
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Disable default elixirls, we use elixir-tools.nvim
        elixirls = false,
      },
    },
  },

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- vim-projectionist - Smart file navigation for Phoenix
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {
    "tpope/vim-projectionist",
    lazy = false,
    config = function()
      vim.g.projectionist_heuristics = {
        ["mix.exs"] = {
          ["lib/*.ex"] = {
            type = "source",
            alternate = "test/{}_test.exs",
            template = { "defmodule {camelcase|capitalize|dot} do", "end" },
          },
          ["test/*_test.exs"] = {
            type = "test",
            alternate = "lib/{}.ex",
          },
          ["lib/**/controllers/*_controller.ex"] = {
            type = "controller",
            alternate = "test/{dirname}/controllers/{basename}_controller_test.exs",
          },
          ["lib/**/views/*_view.ex"] = {
            type = "view",
            alternate = "test/{dirname}/views/{basename}_view_test.exs",
          },
          ["lib/**/live/*_live.ex"] = {
            type = "liveview",
            alternate = "test/{dirname}/live/{basename}_live_test.exs",
          },
          ["lib/**/channels/*_channel.ex"] = {
            type = "channel",
            alternate = "test/{dirname}/channels/{basename}_channel_test.exs",
          },
        },
      }
    end,
  },
}
