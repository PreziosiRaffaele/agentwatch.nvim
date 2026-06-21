local daemon = require('agent-watch.daemon')
local rows = require('agent-watch.rows')
local window = require('agent-watch.watch_window')

local M = {}

local state = {
    opts = nil,
    timer = nil,
    request_running = false,
    project_root = nil,
    daemon_ensured = false,
}

local function stop_timer()
    if not state.timer then
        return
    end

    state.timer:stop()
    state.timer:close()
    state.timer = nil
end

function M.setup(opts)
    state.opts = opts
    state.daemon_ensured = false
    M.stop()
end

function M.stop()
    stop_timer()
    state.request_running = false
    state.project_root = nil
end

local function render_list(open, loading)
    if state.request_running then
        return
    end

    state.project_root = state.project_root or require('agent-watch.worktree').project_root()

    state.request_running = true
    if loading ~= false then
        window.set_lines({ 'Loading agents...' }, {}, { open = open })
    end

    daemon.list_agents(state.opts, function(agent_rows, err)
        state.request_running = false

        if not open and not window.visible() then
            M.stop()
            return
        end

        if err then
            state.daemon_ensured = false
            window.set_lines({ 'agent-watchd request failed:', err }, {}, { open = open })
            return
        end

        local lines, rows_by_line, state_ranges = rows.render(rows.filter(agent_rows, state.project_root))
        window.set_lines(lines, rows_by_line, { open = open, state_ranges = state_ranges })
    end)
end

local function ensure_then_render(open, loading)
    if state.request_running then
        return
    end

    state.request_running = true
    if loading ~= false then
        window.set_lines({ 'Starting agent-watchd...' }, {}, { open = open })
    end

    daemon.ensure(state.opts, function(err)
        state.request_running = false

        if not window.visible() then
            M.stop()
            return
        end

        if err then
            state.daemon_ensured = false
            M.stop()
            window.set_lines({ 'aw daemon ensure failed:', err }, {}, { open = open })
            return
        end

        state.daemon_ensured = true
        render_list(open, loading)
    end)
end

function M.refresh(opts)
    opts = opts or {}
    local open = opts.open ~= false

    if open then
        window.open()
    elseif not window.visible() then
        M.stop()
        return
    end

    if open and not state.daemon_ensured then
        ensure_then_render(open, opts.loading)
    else
        render_list(open, opts.loading)
    end

    if opts.watch == false then
        return
    end

    if state.timer then
        return
    end

    state.timer = vim.uv.new_timer()
    state.timer:start(state.opts.watch_interval, state.opts.watch_interval, function()
        vim.schedule(function()
            if not window.visible() then
                M.stop()
                return
            end

            render_list(false, false)
        end)
    end)
end

return M
