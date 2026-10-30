-- TailwindCSS Integration for Phoenix/HEEx

return {
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- tailwind-tools.nvim - TailwindCSS tooling
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {
    "luckasRanarison/tailwind-tools.nvim",
    ft = { "html", "heex", "elixir", "eex", "css", "scss" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      -- Document color (inline color preview)
      document_color = {
        enabled = true,
        kind = "inline",
        inline_symbol = "󰝤 ",
      },
      -- Conceal long class strings
      conceal = {
        enabled = true,
        min_length = 20,
        symbol = "󱏿",
      },
      -- Custom queries for HEEx
      custom_filetypes = {
        "heex",
        "elixir",
      },
    },
  },

  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  -- Configure TailwindCSS LSP for HEEx files
  -- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tailwindcss = {
          filetypes = { "html", "heex", "elixir", "eex", "css", "scss", "javascript", "typescript" },
          init_options = {
            userLanguages = {
              elixir = "phoenix-heex",
              heex = "phoenix-heex",
              eex = "phoenix-heex",
            },
          },
          settings = {
            tailwindCSS = {
              includeLanguages = {
                elixir = "html",
                heex = "html",
                eex = "html",
              },
              experimental = {
                classRegex = {
                  -- Match class in HEEx
                  'class[:]?\\s*"([^"]*)"',
                  'class[:]?\\s*\'([^\']*)\'',
                  -- Match class in Elixir assigns
                  '~H""".*class[:]?\\s*"([^"]*)".*"""',
                },
              },
            },
          },
        },
      },
    },
  },
}
