local daemon = require('agent-watch.daemon')
local rows = require('agent-watch.rows')
local server = require('agent-watch.nvim_server')
local window = require('agent-watch.watch_window')

local M = {}

local state = {
    opts = nil,
    timer = nil,
    request_running = false,
    server = nil,
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
    M.stop()
end

function M.stop()
    stop_timer()
    state.request_running = false
    state.server = nil
end

local function render_list(open, loading)
    state.server = state.server or server.ensure()
    if not state.server or state.request_running then
        return
    end

    state.request_running = true
    if loading ~= false then
        window.set_lines({ 'Loading agents...' }, {}, { open = open })
    end

    daemon.list_agents(state.opts, state.server, function(agent_rows, err)
        state.request_running = false

        if not open and not window.visible() then
            M.stop()
            return
        end

        if err then
            window.set_lines({ 'agent-watchd request failed:', err }, {}, { open = open })
            return
        end

        local lines, rows_by_line = rows.render(rows.filter(agent_rows, state.server))
        window.set_lines(lines, rows_by_line, { open = open })
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

    render_list(open, opts.loading)

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
