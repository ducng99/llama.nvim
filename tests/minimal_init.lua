-- Minimal init.lua for headless test runs
local cwd = vim.fn.getcwd()

-- Add plugin to runtimepath
vim.opt.rtp:prepend(cwd)
-- Add plenary.nvim to runtimepath
vim.opt.rtp:prepend(cwd .. '/.deps/plenary.nvim')

-- Load the plugin
require('llama').init()
