-- Telescope - Fuzzy finder

return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    },
    keys = {
      -- File finding
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>fw", "<cmd>Telescope grep_string<cr>", desc = "Find word under cursor" },

      -- Buffer/window navigation
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Find buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>", desc = "Find keymaps" },

      -- Git
      { "<leader>fgc", "<cmd>Telescope git_commits<cr>", desc = "Git commits" },
      { "<leader>fgb", "<cmd>Telescope git_branches<cr>", desc = "Git branches" },
      { "<leader>fgs", "<cmd>Telescope git_status<cr>", desc = "Git status" },

      -- LSP
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document symbols" },
      { "<leader>fS", "<cmd>Telescope lsp_workspace_symbols<cr>", desc = "Workspace symbols" },

      -- Other
      { "<leader>fc", "<cmd>Telescope commands<cr>", desc = "Commands" },
      { "<leader>fo", "<cmd>Telescope vim_options<cr>", desc = "Vim options" },
      { "<leader>fm", "<cmd>Telescope marks<cr>", desc = "Marks" },
    },
    opts = {
      defaults = {
        prompt_prefix = " ",
        selection_caret = " ",
        path_display = { "truncate" },
        file_ignore_patterns = {
          "node_modules",
          "_build",
          "deps",
          ".elixir_ls",
          "cover",
          ".git/",
          "%.lock",
        },
        mappings = {
          i = {
            ["<C-j>"] = function(...)
              require("telescope.actions").move_selection_next(...)
            end,
            ["<C-k>"] = function(...)
              require("telescope.actions").move_selection_previous(...)
            end,
            ["<C-n>"] = function(...)
              require("telescope.actions").cycle_history_next(...)
            end,
            ["<C-p>"] = function(...)
              require("telescope.actions").cycle_history_prev(...)
            end,
          },
        },
        layout_config = {
          horizontal = {
            prompt_position = "top",
            preview_width = 0.55,
          },
          width = 0.87,
          height = 0.80,
          preview_cutoff = 120,
        },
        sorting_strategy = "ascending",
      },
      pickers = {
        find_files = {
          hidden = true,
        },
        live_grep = {
          additional_args = function()
            return { "--hidden" }
          end,
        },
      },
    },
    config = function(_, opts)
      local telescope = require("telescope")
      telescope.setup(opts)
      telescope.load_extension("fzf")
    end,
  },
}
