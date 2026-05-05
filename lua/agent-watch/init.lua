local config = require('agent-watch.config')
local daemon = require('agent-watch.daemon')
local notify = require('agent-watch.notify').notify
local rows = require('agent-watch.rows')
local server = require('agent-watch.nvim_server')
local terminal = require('agent-watch.terminal')
local watcher = require('agent-watch.watcher')
local window = require('agent-watch.watch_window')

local M = {}

local state = {
    opts = config.build(),
    latest = nil,
    toggle_latest_keymap = nil,
}

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

function M.refresh(opts)
    watcher.refresh(opts)
end

function M.toggle()
    if window.visible() then
        watcher.stop()
        window.close()
        return
    end

    watcher.refresh()
end

local function remember_latest(bufnr, title)
    state.latest = {
        bufnr = bufnr,
        title = title,
    }
end

local function valid_latest()
    if not state.latest then
        return nil
    end

    local bufnr = state.latest.bufnr
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
        return state.latest
    end

    state.latest = nil
    return nil
end

local function close_visible_terminal(bufnr)
    local closed = false
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        if vim.api.nvim_win_is_valid(win) then
            closed = pcall(vim.api.nvim_win_close, win, false) or closed
        end
    end
    return closed
end

local function row_id(row)
    return tonumber(rows.id(row))
end

local function latest_daemon_row(agent_rows, nvim_server)
    local latest_row = nil
    local latest_id = nil

    for _, row in ipairs(rows.filter(agent_rows, nvim_server)) do
        local bufnr = rows.bufnr(row)
        local id = row_id(row)
        if bufnr and id and vim.api.nvim_buf_is_loaded(bufnr) and (not latest_id or id > latest_id) then
            latest_row = row
            latest_id = id
        end
    end

    return latest_row
end

local function open_latest(latest)
    terminal.open(state.opts, latest.bufnr, latest.title)
    remember_latest(latest.bufnr, latest.title)
end

local function open_daemon_latest()
    local nvim_server = server.ensure()
    if not nvim_server then
        return
    end

    daemon.list_agents(state.opts, nvim_server, function(agent_rows, err)
        if err then
            notify('agent-watchd request failed: ' .. err, vim.log.levels.ERROR)
            return
        end

        local row = latest_daemon_row(agent_rows, nvim_server)
        if not row then
            notify('No latest agent terminal found', vim.log.levels.WARN)
            return
        end

        local bufnr = rows.bufnr(row)
        local title = rows.field(row, { 'title', 'name', 'summary' })
        open_latest({ bufnr = bufnr, title = title })
    end)
end

function M.toggle_latest()
    local latest = valid_latest()
    if latest then
        if close_visible_terminal(latest.bufnr) then
            return
        end

        open_latest(latest)
        return
    end

    open_daemon_latest()
end

function M.jump_to_agent()
    local row = window.selected_row()
    if not row then
        return
    end

    local bufnr = rows.bufnr(row)
    if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
        notify('Agent terminal buffer is not loaded', vim.log.levels.WARN)
        return
    end

    local title = rows.field(row, { 'title', 'name', 'summary' })
    terminal.open(state.opts, bufnr, title)
    remember_latest(bufnr, title)
end

function M.delete_agent()
    local row = window.selected_row()
    if not row then
        return
    end

    local bufnr = rows.bufnr(row)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        notify('Agent terminal buffer is not valid', vim.log.levels.WARN)
        return
    end

    vim.api.nvim_buf_delete(bufnr, { force = true })
    watcher.refresh({ loading = false })
end

function M.rename_agent(args)
    local row = window.selected_row()
    if not row then
        notify('Select an agent row to rename', vim.log.levels.WARN)
        return
    end

    local id = rows.id(row)
    if not id then
        notify('Selected agent has no id to rename', vim.log.levels.WARN)
        return
    end

    local function rename_to(title)
        title = vim.trim(title or '')
        if title == '' then
            return
        end

        daemon.rename(state.opts, id, title, function(err)
            if err then
                notify('agent-watchd rename failed: ' .. err, vim.log.levels.ERROR)
                return
            end

            notify('Renamed agent to "' .. title .. '"')
            watcher.refresh({ loading = false })
        end)
    end

    if args and args[1] then
        rename_to(table.concat(args, ' '))
        return
    end

    vim.ui.input({
        prompt = 'Agent title: ',
        default = rows.field(row, { 'title', 'name', 'summary' }),
    }, rename_to)
end

function M.prompt_launch()
    vim.ui.input({ prompt = 'Agent title: ' }, function(title)
        title = vim.trim(title or '')
        if title == '' then
            return
        end

        vim.ui.select(state.opts.available_agents, {
            prompt = 'Agent type:',
            format_item = function(agent)
                if agent == state.opts.default_agent then
                    return agent .. ' (default)'
                end
                return agent
            end,
        }, function(choice)
            local agent = first_nonempty(choice, state.opts.default_agent, config.defaults.default_agent)
            M.launch({ title, agent })
        end)
    end)
end

function M.launch(args)
    local nvim_server = server.ensure()
    if not nvim_server then
        return
    end

    local bufnr = terminal.launch(state.opts, nvim_server, args)
    if bufnr then
        remember_latest(bufnr, args and args[1] or nil)
    end
end

local function complete_agent(arg_lead, cmd_line)
    local args = vim.split(cmd_line, '%s+', { trimempty = true })
    if #args == 3 then
        return vim.tbl_filter(function(agent)
            return vim.startswith(agent, arg_lead)
        end, state.opts.available_agents)
    end
    return {}
end

local function setup_keymaps()
    if state.toggle_latest_keymap then
        pcall(vim.keymap.del, 'n', state.toggle_latest_keymap)
        state.toggle_latest_keymap = nil
    end

    local keymap = state.opts.keymaps and state.opts.keymaps.toggle_latest
    if type(keymap) ~= 'string' or keymap == '' then
        return
    end

    vim.keymap.set('n', keymap, M.toggle_latest, {
        silent = true,
        desc = 'Toggle latest agent terminal',
    })
    state.toggle_latest_keymap = keymap
end

function M.setup(opts)
    state.opts = config.build(opts)
    terminal.setup({ toggle_latest = M.toggle_latest })
    setup_keymaps()
    watcher.setup(state.opts)
    window.setup(state.opts, {
        jump = M.jump_to_agent,
        launch = M.prompt_launch,
        rename = M.rename_agent,
        delete = M.delete_agent,
        close = function()
            watcher.stop()
            window.close()
        end,
    })

    pcall(vim.api.nvim_del_user_command, state.opts.commands.watch)
    pcall(vim.api.nvim_del_user_command, state.opts.commands.toggle)
    pcall(vim.api.nvim_del_user_command, state.opts.commands.toggle_latest)
    pcall(vim.api.nvim_del_user_command, state.opts.commands.launch)
    pcall(vim.api.nvim_del_user_command, state.opts.commands.rename)

    vim.api.nvim_create_user_command(state.opts.commands.watch, M.refresh, {
        desc = 'Open Agent Watch',
    })

    vim.api.nvim_create_user_command(state.opts.commands.toggle, M.toggle, {
        desc = 'Toggle Agent Watch',
    })

    vim.api.nvim_create_user_command(state.opts.commands.toggle_latest, M.toggle_latest, {
        desc = 'Toggle the latest Agent Watch terminal',
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
