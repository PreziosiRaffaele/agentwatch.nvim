local config = require('agent-watch.config')
local notify = require('agent-watch.notify').notify

local M = {}

local state = {
    toggle_latest = nil,
}

local function terminal_opts(opts)
    return opts.terminal or {}
end

local function start_insert(bufnr)
    if vim.bo[bufnr].buftype == 'terminal' then
        vim.cmd('startinsert')
    end
end

local function set_terminal_window_options(win, bufnr)
    if not vim.api.nvim_win_is_valid(win) then return end
    local title = vim.b[bufnr].agent_watch_title or ''
    local agent = vim.b[bufnr].agent_watch_agent or ''
    local statusline = ' ' .. title
    if agent ~= '' then
        statusline = statusline .. '  [' .. agent .. ']'
    end
    vim.wo[win].statusline = statusline
end

local function set_close_keymap(bufnr)
    vim.keymap.set({ 'n', 't' }, '<C-\\><C-\\>', function()
        if state.toggle_latest then
            state.toggle_latest()
            return
        end

        vim.api.nvim_win_close(0, false)
    end, { buffer = bufnr, silent = true, desc = 'Toggle latest agent terminal' })
end

function M.setup(opts)
    state.toggle_latest = opts and opts.toggle_latest or nil
end

function M.open_float(opts, bufnr)
    local terminal = terminal_opts(opts)
    local width = math.max(1, math.floor(vim.o.columns * terminal.float_width))
    local height = math.max(1, math.floor(vim.o.lines * terminal.float_height))
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    local title = vim.b[bufnr].agent_watch_title

    local win = vim.api.nvim_open_win(bufnr, true, {
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

    set_terminal_window_options(win, bufnr)
    set_close_keymap(bufnr)
    start_insert(bufnr)
end

function M.open_side(opts, bufnr)
    local terminal = terminal_opts(opts)
    local modifier = 'botright'
    if terminal.side == 'left' then
        modifier = 'topleft'
    end

    vim.cmd(modifier .. ' vertical ' .. terminal.width .. 'split')
    vim.api.nvim_set_current_buf(bufnr)
    vim.cmd('vertical resize ' .. terminal.width)
    set_terminal_window_options(vim.api.nvim_get_current_win(), bufnr)
    set_close_keymap(bufnr)
    start_insert(bufnr)
end

function M.open_tab(_, bufnr)
    vim.cmd('tabnew')
    vim.api.nvim_set_current_buf(bufnr)
    set_terminal_window_options(vim.api.nvim_get_current_win(), bufnr)
    set_close_keymap(bufnr)
    start_insert(bufnr)
end

function M.refresh_statusline(bufnr)
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        set_terminal_window_options(win, bufnr)
    end
end

function M.open(opts, bufnr)
    local layout = terminal_opts(opts).layout
    if layout == 'side' then
        M.open_side(opts, bufnr)
        return
    end

    if layout == 'tab' then
        M.open_tab(opts, bufnr)
        return
    end

    M.open_float(opts, bufnr)
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

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.b[bufnr].agent_watch_title = title
    vim.b[bufnr].agent_watch_agent = agent

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

    M.open(opts, bufnr)
    local job_id = vim.fn.jobstart(parts, { term = true })

    if type(job_id) ~= 'number' or job_id <= 0 then
        notify('Could not start terminal for agent launch', vim.log.levels.ERROR)
        vim.api.nvim_win_close(0, false)
        return nil
    end

    vim.cmd('startinsert')
    return bufnr
end

return M
