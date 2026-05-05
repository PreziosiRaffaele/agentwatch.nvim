local config = require('agent-watch.config')
local notify = require('agent-watch.notify').notify

local M = {}

function M.open_float(bufnr, title)
    local width = math.floor(vim.o.columns * 0.9)
    local height = math.floor(vim.o.lines * 0.85)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    vim.api.nvim_open_win(bufnr, true, {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        border = 'rounded',
        style = 'minimal',
        title = title and (' ' .. title .. ' ') or nil,
        title_pos = 'center',
    })

    vim.keymap.set('t', '<C-w>q', function()
        vim.api.nvim_win_close(0, false)
    end, { buffer = bufnr, silent = true, desc = 'Close agent float' })

    if vim.bo[bufnr].buftype == 'terminal' then
        vim.cmd('startinsert')
    end
end

function M.launch(opts, server, args)
    args = args or {}
    local title = args[1]
    local agent = args[2] or opts.default_agent
    local configured_agent_set = config.available_agent_set(opts)
    local extra_args = {}

    if not title or title == '' then
        notify('Usage: AgentWatchLaunch <title> [agent] [args...]', vim.log.levels.ERROR)
        return
    end

    if not configured_agent_set[agent] then
        notify(
            'Unknown agent "' .. agent .. '". Use one of: ' .. table.concat(opts.available_agents, ', '),
            vim.log.levels.ERROR
        )
        return
    end

    for index = args[2] and 3 or 2, #args do
        table.insert(extra_args, args[index])
    end

    local parts = {
        opts.cli,
        agent,
        '--title',
        title,
        '--nvim-server',
        server,
        '--nvim-bufnr',
        bufnr,
    }

    vim.list_extend(parts, extra_args)

    local bufnr = vim.api.nvim_create_buf(false, true)
    M.open_float(bufnr, title)
    local job_id = vim.fn.jobstart(parts, { term = true })

    if type(job_id) ~= 'number' or job_id <= 0 then
        notify('Could not start terminal for agent launch', vim.log.levels.ERROR)
        vim.api.nvim_win_close(0, false)
        return
    end

    vim.cmd('startinsert')
end

return M
