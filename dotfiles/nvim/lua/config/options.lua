-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Leader key (space is already default in LazyVim, but explicit for clarity)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Editor Behavior (matching VSCode setup)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true  -- Matching your VSCode setup

-- Indentation (2 spaces, matching your Elixir settings)
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.autoindent = true

-- Don't detect indentation from file (matching your VSCode)
vim.opt.filetype = "on"

-- Rulers (matching your VSCode rulers: [80, 120, 160])
vim.opt.colorcolumn = "80,120,160"

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Search Behavior
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

vim.opt.hlsearch = true    -- Highlight search results (matching VSCodeVim)
vim.opt.incsearch = true   -- Incremental search (matching VSCodeVim)
vim.opt.ignorecase = true  -- Case insensitive search
vim.opt.smartcase = true   -- Case sensitive if uppercase present

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- File Handling
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Auto-save on window change (matching your VSCode onWindowChange)
vim.opt.autowrite = true
vim.opt.autowriteall = true

-- File watching and updates
vim.opt.updatetime = 250  -- Faster completion and better UX
vim.opt.timeoutlen = 300  -- Time to wait for mapped sequence

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- UI/UX
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Font configuration (matching your VSCode Fira Code setup)
vim.opt.guifont = "FiraCode Nerd Font:h14"

-- Cursor line
vim.opt.cursorline = true

-- Show sign column always (for git signs and diagnostics)
vim.opt.signcolumn = "yes"

-- Better completion experience
vim.opt.completeopt = "menu,menuone,noselect"

-- Enable mouse support
vim.opt.mouse = "a"

-- Clipboard integration (use system clipboard)
vim.opt.clipboard = "unnamedplus"

-- Split behavior
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Line wrapping
vim.opt.wrap = false
vim.opt.linebreak = true

-- Scroll offset
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Performance
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Faster macro execution
vim.opt.lazyredraw = false  -- Don't redraw while executing macros

-- Undo and backup
vim.opt.undofile = true
vim.opt.undolevels = 10000
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Elixir/Phoenix Specific
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Format options
vim.opt.formatoptions = "jcroqlnt"

-- Spell checking for markdown and git commits
vim.opt.spell = false
vim.opt.spelllang = "en_us"

-- Concealment (off by default, enabled per-filetype in autocmds)
vim.opt.conceallevel = 0
vim.opt.concealcursor = "nc"
