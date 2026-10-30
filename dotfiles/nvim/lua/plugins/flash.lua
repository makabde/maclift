-- Flash.nvim - Modern motion plugin (replaces easymotion)

return {
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      -- Flash configuration matching easymotion behavior
      labels = "asdfghjklqwertyuiopzxcvbnm",
      search = {
        multi_window = true,
        forward = true,
        wrap = true,
        mode = "exact",
        incremental = false,
      },
      jump = {
        jumplist = true,
        pos = "start",
        history = false,
        register = false,
        nohlsearch = true,
        autojump = false,
      },
      label = {
        uppercase = true,
        rainbow = {
          enabled = false,
        },
      },
      modes = {
        search = {
          enabled = true,
        },
        char = {
          enabled = true,
          jump_labels = true,
          multi_line = true,
          label = { exclude = "hjkliardc" },
        },
      },
      prompt = {
        enabled = true,
        prefix = { { "⚡", "FlashPromptIcon" } },
      },
    },
    keys = {
      -- Flash jump (matching your easymotion usage)
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash",
      },
      -- Flash treesitter (navigate by syntax)
      {
        "S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash Treesitter",
      },
      -- Remote Flash (jump from operator-pending mode)
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote Flash",
      },
      -- Treesitter search
      {
        "R",
        mode = { "o", "x" },
        function()
          require("flash").treesitter_search()
        end,
        desc = "Treesitter Search",
      },
      -- Toggle Flash in search
      {
        "<c-s>",
        mode = { "c" },
        function()
          require("flash").toggle()
        end,
        desc = "Toggle Flash Search",
      },
    },
  },
}
