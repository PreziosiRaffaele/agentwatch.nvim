-- Minimal init for the test suite. Used by both the runner Neovim (unit tests)
-- and every child Neovim spawned by mini.test (integration tests).

local function plugin_root()
    local this = debug.getinfo(1, 'S').source:sub(2)
    return vim.fn.fnamemodify(this, ':p:h:h')
end

local root = plugin_root()

vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. '/deps/mini.nvim')

-- Let tests require helper modules as `helpers.<name>` from tests/.
package.path = root .. '/tests/?.lua;' .. root .. '/tests/?/init.lua;' .. package.path

-- Keep the environment hermetic and quiet.
vim.o.swapfile = false
vim.o.shadafile = 'NONE'

require('mini.test').setup()
