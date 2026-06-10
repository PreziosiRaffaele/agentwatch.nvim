local config = require('agent-watch.config')
local daemon = require('agent-watch.daemon')
local highlights = require('agent-watch.highlights')
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
    toggle_keymap = nil,
    toggle_latest_keymap = nil,
    worktree_tabs = nil,
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

local function remember_latest(bufnr)
    state.latest = { bufnr = bufnr }
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
    terminal.open(state.opts, latest.bufnr)
    remember_latest(latest.bufnr)
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
        open_latest({ bufnr = bufnr })
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

    terminal.open(state.opts, bufnr)
    remember_latest(bufnr)
end

function M.delete_agent()
    local row = window.selected_row()
    if not row then
        return
    end

    local id = rows.id(row)
    if not id then
        notify('Selected agent has no id to delete', vim.log.levels.WARN)
        return
    end

    local title = rows.field(row, { 'title', 'name', 'summary' })
    local label = title ~= '' and title or ('#' .. tostring(id))
    local answer = vim.fn.input('Delete agent ' .. label .. '? [y/N] ')
    answer = vim.trim(answer or ''):lower()
    if answer ~= 'y' and answer ~= 'yes' then
        return
    end

    local bufnr = rows.bufnr(row)
    daemon.delete(state.opts, id, function(err)
        if err then
            notify('agent-watchd delete failed: ' .. err, vim.log.levels.ERROR)
            return
        end

        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end

        notify('Deleted agent ' .. label)
        watcher.refresh({ loading = false })
    end)
end

function M.delete_agent_worktree()
    local worktree = require('agent-watch.worktree')
    local row = window.selected_row()
    if not row then
        return
    end

    local folder = rows.field(row, { 'folder' })
    local path, removable_err = worktree.removable_path(folder)
    if removable_err then
        notify(removable_err, vim.log.levels.WARN)
        return
    end

    local id = rows.id(row)
    if not id then
        notify('Selected agent has no id to delete', vim.log.levels.WARN)
        return
    end

    local title = rows.field(row, { 'title', 'name', 'summary' })
    local label = title ~= '' and title or ('#' .. tostring(id))
    local answer = vim.fn.input('Delete worktree ' .. path .. ' and agent ' .. label .. '? [y/N] ')
    answer = vim.trim(answer or ''):lower()
    if answer ~= 'y' and answer ~= 'yes' then
        return
    end

    local removed_path, remove_err = worktree.remove(path)
    if remove_err then
        notify('git worktree remove failed: ' .. remove_err, vim.log.levels.ERROR)
        return
    end

    local bufnr = rows.bufnr(row)
    daemon.delete(state.opts, id, function(err)
        if err then
            notify('agent-watchd delete failed: ' .. err, vim.log.levels.ERROR)
            return
        end

        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end

        notify('Deleted worktree ' .. removed_path .. ' and agent ' .. label)
        watcher.refresh({ loading = false })
    end)
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

            local bufnr = rows.bufnr(row)
            if bufnr then
                vim.b[bufnr].agent_watch_title = title
                terminal.refresh_bufname(bufnr)
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

function M.launch(args, cwd)
    local nvim_server = server.ensure()
    if not nvim_server then
        return
    end

    local bufnr = terminal.launch(state.opts, nvim_server, args, cwd)
    if bufnr then
        remember_latest(bufnr)
    end
end

function M.launch_worktree(args)
    local worktree = require('agent-watch.worktree')
    args = args or {}

    if #args < 1 or #args > 3 then
        notify('Usage: AgentWatchLaunchWorktree <title> [branch] [agent]', vim.log.levels.ERROR)
        return
    end

    local given_title = vim.trim(args[1] or '')
    if given_title == '' then
        notify('Usage: AgentWatchLaunchWorktree <title> [branch] [agent]', vim.log.levels.ERROR)
        return
    end

    local agent_set = config.available_agent_set(state.opts)
    local given_branch = nil
    local given_agent = nil

    if #args == 2 then
        local second = vim.trim(args[2] or '')
        if second ~= '' then
            if agent_set[second] then
                given_agent = second
            else
                given_branch = second
            end
        end
    elseif #args == 3 then
        local second = vim.trim(args[2] or '')
        local third = vim.trim(args[3] or '')
        given_branch = second ~= '' and second or nil
        given_agent = third ~= '' and third or nil
    end

    if not given_branch then
        given_branch = worktree.title_to_branch(given_title)
        if given_branch == '' then
            notify('Could not derive a branch name from title "' .. given_title .. '"', vim.log.levels.ERROR)
            return
        end
    end

    local repo_root = worktree.repo_root()
    if not repo_root then
        notify('Not in a Git repository', vim.log.levels.ERROR)
        return
    end

    local path = worktree.default_path(repo_root, given_branch, config.worktree_dir)
    local err = worktree.add(repo_root, given_branch, path)
    if err then
        notify('git worktree add failed: ' .. err, vim.log.levels.ERROR)
        return
    end
    M.launch({ given_title, given_agent }, path)
end

function M.attach_worktree(args)
    local worktree = require('agent-watch.worktree')
    args = args or {}

    if #args < 1 or #args > 3 then
        notify('Usage: AgentWatchAttachWorktree <path> [title] [agent]', vim.log.levels.ERROR)
        return
    end

    local given_path = vim.trim(args[1] or '')
    if given_path == '' then
        notify('Usage: AgentWatchAttachWorktree <path> [title] [agent]', vim.log.levels.ERROR)
        return
    end

    local agent_set = config.available_agent_set(state.opts)
    local given_title = nil
    local given_agent = nil

    if #args == 2 then
        local second = vim.trim(args[2] or '')
        if second ~= '' then
            if agent_set[second] then
                given_agent = second
            else
                given_title = second
            end
        end
    elseif #args == 3 then
        local second = vim.trim(args[2] or '')
        local third = vim.trim(args[3] or '')
        given_title = second ~= '' and second or nil
        given_agent = third ~= '' and third or nil
    end

    local agent = first_nonempty(given_agent, state.opts.default_agent, config.defaults.default_agent)
    if not agent_set[agent] then
        notify(
            'Unknown agent "' .. agent .. '". Use one of: ' .. table.concat(state.opts.available_agents, ', '),
            vim.log.levels.ERROR
        )
        return
    end

    local path, err = worktree.attachable_path(given_path)
    if err then
        notify(err, vim.log.levels.ERROR)
        return
    end

    if not given_title then
        given_title = worktree.current_branch(path) or vim.fn.fnamemodify(path, ':t')
        if not given_title or given_title == '' then
            notify('Could not derive a title from path "' .. path .. '"', vim.log.levels.ERROR)
            return
        end
    end

    M.launch({ given_title, agent }, path)
end

function M.prompt_launch_worktree()
    vim.ui.input({ prompt = 'Agent title: ' }, function(title)
        title = vim.trim(title or '')
        if title == '' then
            return
        end

        vim.ui.input({ prompt = 'Branch (optional, derived from title): ' }, function(branch)
            branch = vim.trim(branch or '')
            if branch == '' then
                M.launch_worktree({ title })
            else
                M.launch_worktree({ title, branch })
            end
        end)
    end)
end

function M.open_worktree()
    local row = window.selected_row()
    if not row then
        return
    end

    local folder = rows.field(row, { 'folder' })
    if folder == '' then
        notify('No worktree path for selected agent', vim.log.levels.WARN)
        return
    end

    if state.opts.worktree_opener == 'tmux' then
        if not vim.env.TMUX or vim.env.TMUX == '' then
            notify('Not in a tmux session ($TMUX is unset)', vim.log.levels.ERROR)
            return
        end

        local title = rows.field(row, { 'title', 'name', 'summary' })
        if title == '' then
            title = vim.fn.fnamemodify(folder, ':t')
        end

        vim.fn.jobstart({ 'tmux', 'new-window', '-n', title, '-c', folder }, { detach = true })
    else
        vim.cmd('tabnew')
        vim.cmd('tcd ' .. vim.fn.fnameescape(folder))
        local worktree = require('agent-watch.worktree')
        local is_linked = worktree.is_linked_path(folder)
        if is_linked == true and state.worktree_tabs then
            state.worktree_tabs.mark_current(row, folder)
        end
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

local function complete_worktree_agent(arg_lead, cmd_line)
    local args = vim.split(cmd_line, '%s+', { trimempty = true })
    if #args == 4 then
        return vim.tbl_filter(function(agent)
            return vim.startswith(agent, arg_lead)
        end, state.opts.available_agents)
    end
    return {}
end

local function complete_attach_worktree(arg_lead, cmd_line)
    local args = vim.split(cmd_line, '%s+', { trimempty = true })
    if #args == 2 then
        return vim.fn.getcompletion(arg_lead, 'dir')
    end
    if #args == 4 then
        return vim.tbl_filter(function(agent)
            return vim.startswith(agent, arg_lead)
        end, state.opts.available_agents)
    end
    return {}
end

local function setup_keymaps()
    if state.toggle_keymap then
        pcall(vim.keymap.del, 'n', state.toggle_keymap)
        state.toggle_keymap = nil
    end

    if state.toggle_latest_keymap then
        pcall(vim.keymap.del, 'n', state.toggle_latest_keymap)
        state.toggle_latest_keymap = nil
    end

    local toggle_keymap = state.opts.keymaps and state.opts.keymaps.toggle
    if type(toggle_keymap) == 'string' and toggle_keymap ~= '' then
        vim.keymap.set('n', toggle_keymap, M.toggle, {
            silent = true,
            desc = 'Toggle Agent Watch',
        })
        state.toggle_keymap = toggle_keymap
    end

    local toggle_latest_keymap = state.opts.keymaps and state.opts.keymaps.toggle_latest
    if type(toggle_latest_keymap) == 'string' and toggle_latest_keymap ~= '' then
        vim.keymap.set('n', toggle_latest_keymap, M.toggle_latest, {
            silent = true,
            desc = 'Toggle latest agent terminal',
        })
        state.toggle_latest_keymap = toggle_latest_keymap
    end
end

local function setup_worktree_tabs()
    if state.opts.worktree_tab_label then
        state.worktree_tabs = require('agent-watch.worktree_tabs')
        state.worktree_tabs.setup(state.opts)
        return
    end

    local loaded = package.loaded['agent-watch.worktree_tabs']
    if loaded then
        loaded.setup(state.opts)
    end
    state.worktree_tabs = nil
end

function M.setup(opts)
    state.opts = config.build(opts)
    highlights.setup()
    terminal.setup({ toggle_latest = M.toggle_latest })
    setup_worktree_tabs()
    setup_keymaps()
    watcher.setup(state.opts)
    window.setup(state.opts, {
        jump = M.jump_to_agent,
        launch = M.prompt_launch,
        launch_worktree = M.prompt_launch_worktree,
        rename = M.rename_agent,
        delete = M.delete_agent,
        delete_worktree = M.delete_agent_worktree,
        open_worktree = M.open_worktree,
        close = function()
            watcher.stop()
            window.close()
        end,
    })

    pcall(vim.api.nvim_del_user_command, 'AgentWatch')
    pcall(vim.api.nvim_del_user_command, 'AgentWatchToggle')
    pcall(vim.api.nvim_del_user_command, 'AgentWatchToggleLatest')
    pcall(vim.api.nvim_del_user_command, 'AgentWatchLaunch')
    pcall(vim.api.nvim_del_user_command, 'AgentWatchRename')
    pcall(vim.api.nvim_del_user_command, 'AgentWatchLaunchWorktree')
    pcall(vim.api.nvim_del_user_command, 'AgentWatchAttachWorktree')

    vim.api.nvim_create_user_command('AgentWatch', M.refresh, {
        desc = 'Open Agent Watch',
    })

    vim.api.nvim_create_user_command('AgentWatchToggle', M.toggle, {
        desc = 'Toggle Agent Watch',
    })

    vim.api.nvim_create_user_command('AgentWatchToggleLatest', M.toggle_latest, {
        desc = 'Toggle the latest Agent Watch terminal',
    })

    vim.api.nvim_create_user_command('AgentWatchLaunch', function(command)
        M.launch(command.fargs)
    end, {
        nargs = '*',
        complete = complete_agent,
        desc = 'Launch an agent tracked by Agent Watch',
    })

    vim.api.nvim_create_user_command('AgentWatchRename', function(command)
        M.rename_agent(command.fargs)
    end, {
        nargs = '*',
        desc = 'Rename the selected Agent Watch row',
    })

    vim.api.nvim_create_user_command('AgentWatchLaunchWorktree', function(command)
        M.launch_worktree(command.fargs)
    end, {
        nargs = '+',
        complete = complete_worktree_agent,
        desc = 'Launch an agent in a new Git worktree',
    })

    vim.api.nvim_create_user_command('AgentWatchAttachWorktree', function(command)
        M.attach_worktree(command.fargs)
    end, {
        nargs = '+',
        complete = complete_attach_worktree,
        desc = 'Launch an agent in an existing Git worktree',
    })
end

return M
