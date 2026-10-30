-- Emmet support for HEEx/EEx templates

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        emmet_ls = {
          filetypes = {
            "html",
            "css",
            "scss",
            "javascript",
            "typescript",
            "heex",
            "elixir",
            "eex",
          },
          init_options = {
            html = {
              options = {
                -- Emmet specific options
                ["bem.enabled"] = true,
              },
            },
          },
        },
      },
    },
  },
}
