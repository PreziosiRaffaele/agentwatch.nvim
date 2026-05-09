local M = {}

local groups = {
    AgentWatchStateRunning = 'DiagnosticInfo',
    AgentWatchStateWaiting = 'DiagnosticWarn',
    AgentWatchStateDone = 'DiagnosticOk',
    AgentWatchStateError = 'DiagnosticError',
    AgentWatchStateIdle = 'Comment',
    AgentWatchStateChanged = 'DiagnosticHint',
    AgentWatchStateUnknown = 'Comment',
}

local state_groups = {
    active = 'AgentWatchStateRunning',
    blocked = 'AgentWatchStateWaiting',
    busy = 'AgentWatchStateRunning',
    canceled = 'AgentWatchStateError',
    cancelled = 'AgentWatchStateError',
    complete = 'AgentWatchStateDone',
    completed = 'AgentWatchStateDone',
    done = 'AgentWatchStateDone',
    edited_file = 'AgentWatchStateChanged',
    error = 'AgentWatchStateError',
    exited = 'AgentWatchStateIdle',
    failed = 'AgentWatchStateError',
    failure = 'AgentWatchStateError',
    idle = 'AgentWatchStateIdle',
    needs_approval = 'AgentWatchStateWaiting',
    pending = 'AgentWatchStateWaiting',
    queued = 'AgentWatchStateWaiting',
    ready = 'AgentWatchStateIdle',
    running_shell = 'AgentWatchStateWaiting',
    running_tool = 'AgentWatchStateWaiting',
    running = 'AgentWatchStateRunning',
    session_started = 'AgentWatchStateRunning',
    stale = 'AgentWatchStateIdle',
    stopped = 'AgentWatchStateError',
    success = 'AgentWatchStateDone',
    succeeded = 'AgentWatchStateDone',
    waiting = 'AgentWatchStateWaiting',
    working = 'AgentWatchStateRunning',
}

local augroup = nil

function M.setup()
    for group, link in pairs(groups) do
        vim.api.nvim_set_hl(0, group, { link = link, default = true })
    end

    if not augroup then
        augroup = vim.api.nvim_create_augroup('AgentWatchHighlights', { clear = true })
        vim.api.nvim_create_autocmd('ColorScheme', {
            group = augroup,
            callback = M.setup,
        })
    end
end

function M.state_group(state)
    state = vim.trim(tostring(state or '')):lower()
    if state == '' then
        return nil
    end
    return state_groups[state] or 'AgentWatchStateUnknown'
end

return M
