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

local function set_buffer_name(bufnr)
    local title = vim.b[bufnr].agent_watch_title or ''
    local agent = vim.b[bufnr].agent_watch_agent or ''
    local name = agent ~= '' and ('[' .. agent .. '] ' .. title) or title
    pcall(vim.api.nvim_buf_set_name, bufnr, name)
end

local function set_close_keymap(bufnr, opts)
    local key = opts and opts.keymaps and opts.keymaps.toggle_latest
    if not key or key == '' then
        return
    end

    vim.keymap.set({ 'n', 't' }, key, function()
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

    set_close_keymap(bufnr, opts)
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
    set_close_keymap(bufnr, opts)
    start_insert(bufnr)
end

function M.open_tab(opts, bufnr)
    vim.cmd('tabnew')
    vim.api.nvim_set_current_buf(bufnr)
    set_close_keymap(bufnr, opts)
    start_insert(bufnr)
end

function M.refresh_bufname(bufnr)
    set_buffer_name(bufnr)
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

-- Opens a new terminal with the configured layout and starts the `aw` job
-- built by `build_parts(bufnr)` in it. Returns the buffer, or nil on failure.
local function open_terminal_job(opts, title, agent, cwd, build_parts)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.b[bufnr].agent_watch_title = title
    vim.b[bufnr].agent_watch_agent = agent

    vim.api.nvim_create_autocmd('TermOpen', {
        buffer = bufnr,
        once = true,
        callback = function()
            set_buffer_name(bufnr)
        end,
    })

    M.open(opts, bufnr)
    local jobstart_opts = { term = true }
    if cwd then
        jobstart_opts.cwd = cwd
    end
    local job_id = vim.fn.jobstart(build_parts(bufnr), jobstart_opts)

    if type(job_id) ~= 'number' or job_id <= 0 then
        notify('Could not start terminal for agent launch', vim.log.levels.ERROR)
        vim.api.nvim_win_close(0, false)
        return nil
    end

    vim.cmd('startinsert')
    return bufnr
end

function M.launch(opts, server, args, cwd)
    args = args or {}
    local title = args[1]
    local agent = args[2] or opts.default_agent
    local configured_agent_set = config.available_agent_set(opts)

    if not title or title == '' or #args > 2 then
        notify('Usage: AgentWatchLaunch <title> [agent]', vim.log.levels.ERROR)
        return
    end

    if not configured_agent_set[agent] then
        notify(
            'Unknown agent "' .. agent .. '". Use one of: ' .. table.concat(opts.available_agents, ', '),
            vim.log.levels.ERROR
        )
        return
    end

    return open_terminal_job(opts, title, agent, cwd, function(bufnr)
        return {
            opts.cli,
            agent,
            '--title',
            title,
            '--nvim-server',
            server,
            '--nvim-bufnr',
            bufnr,
        }
    end)
end

-- Relaunches an exited daemon record (`resume` = { id, title, agent, folder })
-- in its original folder and re-attaches it to this Neovim session.
function M.resume(opts, server, resume)
    return open_terminal_job(opts, resume.title, resume.agent, resume.folder, function(bufnr)
        return {
            opts.cli,
            'resume',
            resume.id,
            '--nvim-server',
            server,
            '--nvim-bufnr',
            bufnr,
        }
    end)
end

return M
