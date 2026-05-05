local notify = require('agent-watch.notify').notify

local M = {}

function M.ensure()
    if vim.v.servername and vim.v.servername ~= '' then
        return vim.v.servername
    end

    local ok, server = pcall(vim.fn.serverstart)
    if not ok or not server or server == '' then
        notify('Could not start a Neovim server for agent-watch', vim.log.levels.ERROR)
        return nil
    end

    return server
end

return M
