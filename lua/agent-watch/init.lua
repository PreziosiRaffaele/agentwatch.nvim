local M = {}

local defaults = {
    cli = 'agent-watch',
    height = 10,
    fixed_height = true,
    watch_interval = 1000,
    refresh_interval = nil,
    default_agent = 'codex',
    commands = {
        watch = 'AgentWatch',
        toggle = 'AgentWatchToggle',
        launch = 'AgentWatchLaunch',
        rename = 'AgentWatchRename',
    },
}

local state = {
    opts = vim.deepcopy(defaults),
    buf = nil,
    win = nil,
    rows_by_line = {},
    watch_process = nil,
    watch_server = nil,
    watch_stdout = '',
    refresh_running = false,
}

local stop_watch
local watch_statusline = 'Agent Watch  <CR>: open  a: add  r: rename  dd: delete'
local supported_agents = { 'codex', 'cursor', 'agent', 'claude' }
local supported_agent_set = {}
for _, agent in ipairs(supported_agents) do
    supported_agent_set[agent] = true
end

local function first_nonempty(...)
    for index = 1, select('#', ...) do
        local value = select(index, ...)
        if type(value) == 'string' then
            local trimmed = vim.trim(value)
            if trimmed ~= '' then
                return trimmed
            end
        end
    end
    return ''
end

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = 'agent-watch.nvim' })
end

local function ensure_server()
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

local function display_width(value, width)
    value = tostring(value or '')
    local visible = vim.fn.strdisplaywidth(value)
    if visible > width then
        return vim.fn.strcharpart(value, 0, math.max(width - 3, 0)) .. '...'
    end
    return value .. string.rep(' ', width - visible)
end

local function get_field(row, names)
    for _, name in ipairs(names) do
        local value = row[name]
        if value ~= nil and value ~= vim.NIL and value ~= '' then
            return value
        end
    end
    return ''
end

local function row_bufnr(row)
    local bufnr = tonumber(row.nvim_terminal_bufnr)
    if not bufnr then
        return nil
    end
    return bufnr
end

local function row_id(row)
    local id = get_field(row, { 'launch_id', 'id', 'agent_id' })
    if id == '' then
        return nil
    end
    return tostring(id)
end

local function is_target_window(win)
    return win and vim.api.nvim_win_is_valid(win)
end

local function visible_watch_window()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        return nil
    end

    local wins = vim.fn.win_findbuf(state.buf)
    if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
        state.win = wins[1]
        return state.win
    end

    return nil
end

local function set_watch_statusline(win)
    if is_target_window(win) then
        vim.wo[win].statusline = watch_statusline
        vim.wo[win].wrap = false
        vim.wo[win].winfixheight = state.opts.fixed_height
    end
end

local function watch_height()
    local height = tonumber(state.opts.height) or defaults.height
    if height < 1 then
        return defaults.height
    end
    return math.floor(height)
end

local function ensure_watch_window()
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        local win = visible_watch_window()
        if win then
            vim.api.nvim_win_set_height(win, watch_height())
            set_watch_statusline(win)
            return state.buf, state.win
        end

        vim.cmd('botright ' .. watch_height() .. 'split')
        state.win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(state.win, state.buf)
        vim.api.nvim_win_set_height(state.win, watch_height())
        set_watch_statusline(state.win)
        return state.buf, state.win
    end

    vim.cmd('botright ' .. watch_height() .. 'split')
    state.win = vim.api.nvim_get_current_win()
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(state.win, state.buf)
    vim.api.nvim_win_set_height(state.win, watch_height())
    set_watch_statusline(state.win)

    vim.bo[state.buf].buftype = 'nofile'
    vim.bo[state.buf].bufhidden = 'hide'
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = 'agent-watch'
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].readonly = true

    vim.keymap.set('n', '<CR>', M.jump_to_agent, { buffer = state.buf, silent = true, desc = 'Jump to agent terminal' })
    vim.keymap.set('n', 'a', M.prompt_launch, { buffer = state.buf, silent = true, desc = 'Add agent' })
    vim.keymap.set('n', 'r', M.rename_agent, { buffer = state.buf, silent = true, desc = 'Rename agent' })
    vim.keymap.set('n', 'dd', M.delete_agent, { buffer = state.buf, silent = true, desc = 'Delete agent terminal' })
    vim.keymap.set('n', 'q', function()
        stop_watch()
        vim.cmd('close')
    end, { buffer = state.buf, silent = true, desc = 'Close agent watch' })

    return state.buf, state.win
end

local function set_watch_lines(lines, rows_by_line, opts)
    opts = opts or {}

    local buf
    local win
    if opts.open == false then
        win = visible_watch_window()
        if not win then
            return false
        end
        buf = state.buf
    else
        buf, win = ensure_watch_window()
    end

    rows_by_line = rows_by_line or {}

    local cursor_line = 1
    local cursor_col = 0
    if is_target_window(win) then
        local cursor = vim.api.nvim_win_get_cursor(win)
        cursor_line = cursor[1]
        cursor_col = cursor[2]
    end

    vim.bo[buf].modifiable = true
    vim.bo[buf].readonly = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true

    if is_target_window(win) then
        if not rows_by_line[cursor_line] then
            for line in pairs(rows_by_line) do
                if line < cursor_line or not rows_by_line[cursor_line] then
                    cursor_line = line
                end
            end
        end

        local target_line = math.min(cursor_line, #lines)
        local max_col = #(lines[target_line] or '')
        vim.api.nvim_win_set_cursor(win, { target_line, math.min(cursor_col, max_col) })
    end

    state.rows_by_line = rows_by_line

    return true
end

local function render_rows(rows)
    local lines = {}
    local rows_by_line = {}

    if #rows == 0 then
        table.insert(lines, 'No active agents for this Neovim server.')
        return lines, rows_by_line
    end

    local header = table.concat({
        display_width('ID', 5),
        display_width('STATE', 16),
        display_width('AGENT', 10),
        display_width('TITLE', 32),
        display_width('REPO', 24),
        display_width('BRANCH', 18),
        display_width('UPDATED', 24),
    }, '  ')

    table.insert(lines, header)
    table.insert(lines, string.rep('-', vim.fn.strdisplaywidth(header)))

    for _, row in ipairs(rows) do
        local line = table.concat({
            display_width(row_id(row) or '', 5),
            display_width(get_field(row, { 'state', 'status' }), 16),
            display_width(get_field(row, { 'agent', 'agent_type', 'type' }), 10),
            display_width(get_field(row, { 'title', 'name', 'summary' }), 32),
            display_width(get_field(row, { 'repo', 'repository', 'cwd' }), 24),
            display_width(get_field(row, { 'branch', 'git_branch' }), 18),
            display_width(get_field(row, { 'updated', 'updated_at', 'updatedAt' }), 24),
        }, '  ')

        table.insert(lines, line)
        rows_by_line[#lines] = row
    end

    return lines, rows_by_line
end

stop_watch = function()
    if state.watch_process then
        pcall(function()
            state.watch_process:kill(15)
        end)
        state.watch_process = nil
    end
    state.watch_server = nil
    state.watch_stdout = ''
end

local function list_args(server, watch)
    local args = {
        state.opts.cli,
        'list',
        '--json',
        '--filter',
        'nvim_server=' .. server,
    }

    if watch then
        vim.list_extend(args, { '--watch', '--interval', tostring(state.opts.watch_interval) })
    end

    return args
end

local function filter_rows(rows, server)
    local filtered = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and row.nvim_server == server then
            local bufnr = row_bufnr(row)
            if not bufnr or vim.api.nvim_buf_is_valid(bufnr) then
                table.insert(filtered, row)
            end
        end
    end

    return filtered
end

local function parse_agent_rows(stdout)
    if stdout == nil or stdout == '' then
        return {}
    end

    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok then
        error('Could not parse agent-watch JSON: ' .. tostring(decoded))
    end

    if vim.islist(decoded) then
        return decoded
    end

    if type(decoded) == 'table' then
        for _, key in ipairs({ 'agents', 'rows', 'items' }) do
            if type(decoded[key]) == 'table' then
                return decoded[key]
            end
        end
    end

    return {}
end

local function render_stdout(stdout, server, open)
    local ok, rows_or_error = pcall(parse_agent_rows, stdout)
    if not ok then
        set_watch_lines({ rows_or_error }, {}, { open = open })
        return
    end

    local lines, rows_by_line = render_rows(filter_rows(rows_or_error, server))
    set_watch_lines(lines, rows_by_line, { open = open })
end

function M.refresh(opts)
    opts = opts or {}
    local server = ensure_server()
    if not server then
        return
    end

    if state.refresh_running then
        return
    end
    state.refresh_running = true

    local open = opts.open ~= false
    if opts.loading ~= false then
        set_watch_lines({ 'Loading agents...' }, {}, { open = open })
    end

    if opts.watch == false then
        vim.system(list_args(server, false), { text = true }, function(result)
            vim.schedule(function()
                state.refresh_running = false

                if not open and not visible_watch_window() then
                    return
                end

                if result.code ~= 0 then
                    set_watch_lines({
                        'agent-watch list failed:',
                        vim.trim(result.stderr or result.stdout or ''),
                    }, {}, { open = open })
                    return
                end

                render_stdout(result.stdout, server, open)
            end)
        end)
        return
    end

    if state.watch_process and state.watch_server == server then
        state.refresh_running = false
        return
    end

    stop_watch()
    state.watch_server = server

    local process
    process = vim.system(list_args(server, true), {
        text = true,
        stdout = function(_, data)
            if not data or data == '' then
                return
            end

            vim.schedule(function()
                if state.watch_process ~= process then
                    return
                end

                if not visible_watch_window() then
                    stop_watch()
                    return
                end

                state.watch_stdout = state.watch_stdout .. data
                while true do
                    local newline = state.watch_stdout:find('\n', 1, true)
                    if not newline then
                        break
                    end

                    local line = vim.trim(state.watch_stdout:sub(1, newline - 1))
                    state.watch_stdout = state.watch_stdout:sub(newline + 1)

                    if line ~= '' then
                        render_stdout(line, server, false)
                    end
                end
            end)
        end,
    }, function(result)
        vim.schedule(function()
            if state.watch_process ~= process then
                return
            end

            state.refresh_running = false
            state.watch_process = nil
            state.watch_server = nil
            state.watch_stdout = ''

            if not open and not visible_watch_window() then
                return
            end

            if result.code ~= 0 then
                set_watch_lines({
                    'agent-watch watch failed:',
                    vim.trim(result.stderr or result.stdout or ''),
                }, {}, { open = open })
            end
        end)
    end)
    state.watch_process = process
    state.refresh_running = false
end

function M.toggle()
    local win = visible_watch_window()
    if win then
        stop_watch()
        vim.api.nvim_win_close(win, false)
        return
    end

    M.refresh()
end

local function selected_row()
    if vim.api.nvim_get_current_buf() ~= state.buf then
        return nil
    end

    local line = vim.api.nvim_win_get_cursor(0)[1]
    return state.rows_by_line[line]
end

local function open_float(bufnr, title)
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

function M.jump_to_agent()
    local row = selected_row()
    if not row then
        return
    end

    local bufnr = row_bufnr(row)
    if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
        notify('Agent terminal buffer is not loaded', vim.log.levels.WARN)
        return
    end

    open_float(bufnr, row.title)
end

function M.delete_agent()
    local row = selected_row()
    if not row then
        return
    end

    local bufnr = row_bufnr(row)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        notify('Agent terminal buffer is not valid', vim.log.levels.WARN)
        return
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
    stop_watch()
    M.refresh()
end

function M.rename_agent(args)
    local row = selected_row()
    if not row then
        notify('Select an agent row to rename', vim.log.levels.WARN)
        return
    end

    local id = row_id(row)
    if not id then
        notify('Selected agent has no id to rename', vim.log.levels.WARN)
        return
    end

    local function rename_to(title)
        title = vim.trim(title or '')
        if title == '' then
            return
        end

        vim.system({ state.opts.cli, 'rename', id, title }, { text = true }, function(result)
            vim.schedule(function()
                if result.code ~= 0 then
                    notify(
                        'agent-watch rename failed: ' .. vim.trim(result.stderr or result.stdout or ''),
                        vim.log.levels.ERROR
                    )
                    return
                end

                notify('Renamed agent to "' .. title .. '"')
                stop_watch()
                M.refresh({ loading = false })
            end)
        end)
    end

    if args and args[1] then
        rename_to(table.concat(args, ' '))
        return
    end

    vim.ui.input({
        prompt = 'Agent title: ',
        default = get_field(row, { 'title', 'name', 'summary' }),
    }, rename_to)
end

local function terminal_command(parts)
    local escaped = {}
    for _, part in ipairs(parts) do
        table.insert(escaped, vim.fn.shellescape(tostring(part)))
    end
    return table.concat(escaped, ' ')
end

function M.prompt_launch()
    vim.ui.input({ prompt = 'Agent title: ' }, function(title)
        title = vim.trim(title or '')
        if title == '' then
            return
        end

        vim.ui.select(supported_agents, {
            prompt = 'Agent type:',
            format_item = function(agent)
                if agent == state.opts.default_agent then
                    return agent .. ' (default)'
                end
                return agent
            end,
        }, function(choice)
            local agent = first_nonempty(choice, state.opts.default_agent, defaults.default_agent)
            M.launch({ title, agent })
        end)
    end)
end

function M.launch(args)
    local server = ensure_server()
    if not server then
        return
    end

    args = args or {}
    local title = args[1]
    local agent = args[2] or state.opts.default_agent
    local extra_args = {}

    if not title or title == '' then
        notify('Usage: AgentWatchLaunch <title> [codex|cursor|agent|claude] [args...]', vim.log.levels.ERROR)
        return
    end

    if not supported_agent_set[agent] then
        notify('Unknown agent "' .. agent .. '". Use codex, cursor, agent, or claude.', vim.log.levels.ERROR)
        return
    end

    for index = args[2] and 3 or 2, #args do
        table.insert(extra_args, args[index])
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    open_float(bufnr, title)
    local job_id = vim.fn.jobstart(vim.o.shell, { term = true })

    if type(job_id) ~= 'number' or job_id <= 0 then
        notify('Could not start terminal for agent launch', vim.log.levels.ERROR)
        vim.api.nvim_win_close(0, false)
        return
    end

    local parts = {
        state.opts.cli,
        'launch',
        '--title',
        title,
        '--nvim-server',
        server,
        '--nvim-terminal-bufnr',
        bufnr,
        agent,
    }

    vim.list_extend(parts, extra_args)
    vim.fn.chansend(job_id, terminal_command(parts) .. '\n')
    vim.cmd('startinsert')
end

local function complete_agent(arg_lead, cmd_line)
    local args = vim.split(cmd_line, '%s+', { trimempty = true })
    if #args == 3 then
        return vim.tbl_filter(function(agent)
            return vim.startswith(agent, arg_lead)
        end, supported_agents)
    end
    return {}
end

function M.setup(opts)
    state.opts = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
    if state.opts.high ~= nil and state.opts.height == defaults.height then
        state.opts.height = state.opts.high
    end
    state.opts.cli = vim.fn.expand(state.opts.cli)
    if not supported_agent_set[state.opts.default_agent] then
        state.opts.default_agent = defaults.default_agent
    end
    state.opts.fixed_height = state.opts.fixed_height ~= false
    state.opts.height = watch_height()
    local interval = state.opts.watch_interval or state.opts.refresh_interval
    state.opts.watch_interval = tonumber(interval) or defaults.watch_interval

    pcall(vim.api.nvim_del_user_command, state.opts.commands.watch)
    pcall(vim.api.nvim_del_user_command, state.opts.commands.toggle)
    pcall(vim.api.nvim_del_user_command, state.opts.commands.launch)
    pcall(vim.api.nvim_del_user_command, state.opts.commands.rename)

    vim.api.nvim_create_user_command(state.opts.commands.watch, M.refresh, {
        desc = 'Open Agent Watch',
    })

    vim.api.nvim_create_user_command(state.opts.commands.toggle, M.toggle, {
        desc = 'Toggle Agent Watch',
    })

    vim.api.nvim_create_user_command(state.opts.commands.launch, function(command)
        M.launch(command.fargs)
    end, {
        nargs = '*',
        complete = complete_agent,
        desc = 'Launch an agent tracked by Agent Watch',
    })

    vim.api.nvim_create_user_command(state.opts.commands.rename, function(command)
        M.rename_agent(command.fargs)
    end, {
        nargs = '*',
        desc = 'Rename the selected Agent Watch row',
    })
end

return M
