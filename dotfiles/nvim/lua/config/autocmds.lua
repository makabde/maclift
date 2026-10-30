-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here

local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Elixir/Phoenix Specific Autocmds
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local elixir_group = augroup("elixir_config", { clear = true })

-- Format on save for Elixir files (matching your VSCode setup)
autocmd("BufWritePre", {
  group = elixir_group,
  pattern = { "*.ex", "*.exs", "*.heex", "*.leex" },
  callback = function()
    vim.lsp.buf.format({ async = false })
  end,
  desc = "Format Elixir files on save",
})

-- Set proper indentation for Elixir files
autocmd("FileType", {
  group = elixir_group,
  pattern = { "elixir", "heex", "eex" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.expandtab = true
  end,
  desc = "Set Elixir indentation",
})

-- Enable Emmet for HEEx files
autocmd("FileType", {
  group = elixir_group,
  pattern = { "heex", "eex" },
  callback = function()
    vim.b.emmet_language = "html"
  end,
  desc = "Enable Emmet for HEEx",
})

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- General Editor Autocmds
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local general_group = augroup("general_config", { clear = true })

-- Highlight on yank
autocmd("TextYankPost", {
  group = general_group,
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({ higroup = "Visual", timeout = 200 })
  end,
  desc = "Highlight when yanking text",
})

-- Auto-save when leaving buffer or losing focus (matching VSCode onWindowChange)
autocmd({ "FocusLost", "BufLeave" }, {
  group = general_group,
  pattern = "*",
  callback = function()
    if vim.bo.modified and not vim.bo.readonly and vim.fn.expand("%") ~= "" and vim.bo.buftype == "" then
      vim.cmd("silent! write")
    end
  end,
  desc = "Auto-save on focus lost or buffer leave",
})

-- Remove trailing whitespace on save
autocmd("BufWritePre", {
  group = general_group,
  pattern = "*",
  callback = function()
    local save_cursor = vim.fn.getpos(".")
    vim.cmd([[%s/\s\+$//e]])
    vim.fn.setpos(".", save_cursor)
  end,
  desc = "Remove trailing whitespace on save",
})

-- Resize splits when window is resized
autocmd("VimResized", {
  group = general_group,
  pattern = "*",
  callback = function()
    vim.cmd("wincmd =")
  end,
  desc = "Resize splits on window resize",
})

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- File Type Specific Settings
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local filetype_group = augroup("filetype_config", { clear = true })

-- Python: 4 spaces (matching your VSCode setup)
autocmd("FileType", {
  group = filetype_group,
  pattern = "python",
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
    vim.opt_local.expandtab = true
  end,
  desc = "Set Python indentation to 4 spaces",
})

-- Markdown: Enable spell check and concealment
autocmd("FileType", {
  group = filetype_group,
  pattern = { "markdown", "gitcommit" },
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.wrap = true
    vim.opt_local.conceallevel = 2  -- Hide markup in markdown
  end,
  desc = "Enable spell check and concealment for markdown and git commits",
})

-- JSON: 2 spaces
autocmd("FileType", {
  group = filetype_group,
  pattern = { "json", "jsonc" },
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.expandtab = true
  end,
  desc = "Set JSON indentation to 2 spaces",
})

-- Close certain windows with q
autocmd("FileType", {
  group = filetype_group,
  pattern = { "help", "qf", "lspinfo", "checkhealth" },
  callback = function()
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = true, silent = true })
  end,
  desc = "Close special windows with q",
})
