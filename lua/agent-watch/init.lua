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

    terminal.open_float(bufnr, rows.field(row, { 'title', 'name', 'summary' }))
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

    terminal.launch(state.opts, nvim_server, args)
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

function M.setup(opts)
    state.opts = config.build(opts)
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
