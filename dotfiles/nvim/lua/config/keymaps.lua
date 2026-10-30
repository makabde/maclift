-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local map = vim.keymap.set

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- VSCodeVim Compatibility Keybindings
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Insert mode: jk to escape (matching your VSCode jk -> Esc)
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Normal mode: <leader>w to save (matching VSCode)
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })

-- Normal mode: <leader>d for delete line (dd)
map("n", "<leader>d", "dd", { desc = "Delete line" })

-- Normal mode: Ctrl-n to clear search highlight
map("n", "<C-n>", "<cmd>nohl<cr>", { desc = "Clear search highlight" })

-- Normal mode: <leader>t to toggle sidebar (matching VSCode)
map("n", "<leader>t", "<cmd>Neotree toggle<cr>", { desc = "Toggle file tree" })

-- Normal mode: <leader>c to comment line (matching VSCode)
-- LazyVim already has this via Comment.nvim with gcc, but add explicit mapping
map("n", "<leader>c", function()
  require("Comment.api").toggle.linewise.current()
end, { desc = "Toggle comment" })

map("v", "<leader>c", "<Plug>(comment_toggle_linewise_visual)", { desc = "Toggle comment", remap = true })

-- Normal mode: <leader>f to reveal in explorer
map("n", "<leader>f", "<cmd>Neotree reveal<cr>", { desc = "Reveal in file tree" })

-- Normal mode: <leader>sh / <leader>sl for moving window
map("n", "<leader>sh", "<C-w>H", { desc = "Move window left" })
map("n", "<leader>sl", "<C-w>L", { desc = "Move window right" })

-- Normal mode: <leader>h / <leader>l for buffer navigation
map("n", "<leader>h", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<leader>l", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- Visual mode: > and < for indent/outdent (staying in visual mode)
map("v", ">", ">gv", { desc = "Indent" })
map("v", "<", "<gv", { desc = "Outdent" })

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Better Window Navigation
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Navigate between splits (Ctrl + hjkl)
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Resize windows with arrow keys
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Better Text Movement
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Move selected lines up/down in visual mode
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move up" })

-- Keep cursor centered when jumping
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up" })
map("n", "n", "nzzzv", { desc = "Next search result" })
map("n", "N", "Nzzzv", { desc = "Previous search result" })

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Elixir-Specific Keybindings
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <leader>m prefix for Mix tasks
map("n", "<leader>mt", "<cmd>terminal mix test<cr>", { desc = "Mix test" })
map("n", "<leader>mf", "<cmd>terminal mix format<cr>", { desc = "Mix format" })
map("n", "<leader>mc", "<cmd>terminal mix compile<cr>", { desc = "Mix compile" })
map("n", "<leader>ms", "<cmd>terminal iex -S mix phx.server<cr>", { desc = "Phoenix server" })
map("n", "<leader>md", "<cmd>terminal mix dialyzer<cr>", { desc = "Mix dialyzer" })

-- <leader>e prefix for Elixir-specific actions
map("n", "<leader>ep", "<cmd>ElixirFromPipe<cr>", { desc = "Elixir: From pipe" })
map("n", "<leader>ei", "<cmd>ElixirToPipe<cr>", { desc = "Elixir: To pipe" })
map("n", "<leader>em", "<cmd>ElixirExpandMacro<cr>", { desc = "Elixir: Expand macro" })

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Testing with Neotest
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

map("n", "<leader>tn", function()
  require("neotest").run.run()
end, { desc = "Run nearest test" })

map("n", "<leader>tf", function()
  require("neotest").run.run(vim.fn.expand("%"))
end, { desc = "Run file tests" })

map("n", "<leader>ts", function()
  require("neotest").summary.toggle()
end, { desc = "Toggle test summary" })

map("n", "<leader>to", function()
  require("neotest").output.open({ enter = true })
end, { desc = "Show test output" })

map("n", "<leader>tO", function()
  require("neotest").output_panel.toggle()
end, { desc = "Toggle test output panel" })

map("n", "<leader>tS", function()
  require("neotest").run.stop()
end, { desc = "Stop test" })

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- LSP Keybindings (already set by LazyVim, but documented here)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- gd          - Go to definition
-- gD          - Go to declaration
-- gr          - Go to references
-- gi          - Go to implementation
-- K           - Hover documentation
-- <leader>ca  - Code actions
-- <leader>rn  - Rename
-- [d / ]d     - Previous/next diagnostic
-- <leader>cf  - Format

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Telescope Keybindings (already set by LazyVim, but documented here)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- <leader>ff  - Find files
-- <leader>fg  - Live grep
-- <leader>fb  - Find buffers
-- <leader>fh  - Find help
-- <leader>fr  - Recent files
-- <leader>fw  - Find word under cursor

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Git Keybindings
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

map("n", "<leader>gs", "<cmd>Git<cr>", { desc = "Git status" })
map("n", "<leader>gc", "<cmd>Git commit<cr>", { desc = "Git commit" })
map("n", "<leader>gp", "<cmd>Git push<cr>", { desc = "Git push" })
map("n", "<leader>gl", "<cmd>Git log<cr>", { desc = "Git log" })
map("n", "<leader>gb", "<cmd>Git blame<cr>", { desc = "Git blame" })
map("n", "<leader>gd", "<cmd>Gdiffsplit<cr>", { desc = "Git diff" })

-- Gitsigns keybindings (hunk navigation)
map("n", "]h", function()
  require("gitsigns").next_hunk()
end, { desc = "Next git hunk" })

map("n", "[h", function()
  require("gitsigns").prev_hunk()
end, { desc = "Previous git hunk" })

map("n", "<leader>hp", function()
  require("gitsigns").preview_hunk()
end, { desc = "Preview git hunk" })

map("n", "<leader>hr", function()
  require("gitsigns").reset_hunk()
end, { desc = "Reset git hunk" })

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Quick Quality of Life Improvements
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Better paste (don't replace clipboard)
map("v", "p", '"_dP', { desc = "Paste without yanking" })

-- Select all
map("n", "<C-a>", "ggVG", { desc = "Select all" })

-- Quick save with Ctrl-S
map({ "n", "i", "v" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })

-- Quit all
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit all" })
