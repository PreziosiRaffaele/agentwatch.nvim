local notify = require('agent-watch.notify').notify

local M = {}

M.defaults = {
    cli = 'aw',
    daemon_url = nil,
    height = 8,
    fixed_height = true,
    watch_interval = 1000,
    default_agent = 'codex',
    available_agents = { 'codex', 'agent', 'claude' },
    terminal = {
        layout = 'float',
        side = 'right',
        width = 80,
        float_width = 0.9,
        float_height = 0.85,
    },
    worktree_dir = '.worktrees',
    worktree_opener = 'nvim',
    keymaps = {
        toggle_latest = '<C-\\><C-\\>',
    },
}

local supported_agents = { 'codex', 'agent', 'claude' }
local supported_agent_set = {}
for _, agent in ipairs(supported_agents) do
    supported_agent_set[agent] = true
end

local supported_worktree_opener_set = {
    nvim = true,
    tmux = true,
}

local supported_terminal_layout_set = {
    float = true,
    side = true,
    tab = true,
}

local supported_terminal_side_set = {
    left = true,
    right = true,
}

local function validate_agent_config(opts)
    local configured_agents = opts.available_agents
    if configured_agents == nil then
        configured_agents = vim.deepcopy(M.defaults.available_agents)
    end

    if type(configured_agents) ~= 'table' or vim.tbl_isempty(configured_agents) then
        notify('Invalid available_agents config. Use a non-empty list of: codex, agent, claude.', vim.log.levels.ERROR)
        configured_agents = vim.deepcopy(M.defaults.available_agents)
    end

    for _, agent in ipairs(configured_agents) do
        if not supported_agent_set[agent] then
            notify(
                'Unknown available_agents value "' .. tostring(agent) .. '". Allowed: codex, agent, claude.',
                vim.log.levels.ERROR
            )
            configured_agents = vim.deepcopy(M.defaults.available_agents)
            break
        end
    end

    opts.available_agents = configured_agents
    if not vim.tbl_contains(configured_agents, opts.default_agent) then
        notify(
            'default_agent must be in available_agents. Falling back to "' .. configured_agents[1] .. '".',
            vim.log.levels.ERROR
        )
        opts.default_agent = configured_agents[1]
    end
end

local function normalize_height(height)
    height = tonumber(height) or M.defaults.height
    if height < 1 then
        return M.defaults.height
    end
    return math.floor(height)
end

local function normalize_positive_int(value, default)
    value = tonumber(value) or default
    if value < 1 then
        return default
    end
    return math.floor(value)
end

local function normalize_fraction(value, default)
    value = tonumber(value) or default
    if value <= 0 or value > 1 then
        return default
    end
    return value
end

local function validate_worktree_opener(opts)
    if not supported_worktree_opener_set[opts.worktree_opener] then
        notify('Invalid worktree_opener. Use one of: nvim, tmux. Falling back to "nvim".', vim.log.levels.ERROR)
        opts.worktree_opener = 'nvim'
    end
end

local function validate_terminal_config(opts)
    local terminal = opts.terminal
    if type(terminal) ~= 'table' then
        notify(
            'Invalid terminal config. Use a table with layout, side, width, float_width, and float_height.',
            vim.log.levels.ERROR
        )
        terminal = vim.deepcopy(M.defaults.terminal)
    end

    if not supported_terminal_layout_set[terminal.layout] then
        notify('Invalid terminal.layout. Use one of: float, side, tab.', vim.log.levels.ERROR)
        terminal.layout = M.defaults.terminal.layout
    end

    if not supported_terminal_side_set[terminal.side] then
        notify('Invalid terminal.side. Use one of: right, left.', vim.log.levels.ERROR)
        terminal.side = M.defaults.terminal.side
    end

    terminal.width = normalize_positive_int(terminal.width, M.defaults.terminal.width)
    terminal.float_width = normalize_fraction(terminal.float_width, M.defaults.terminal.float_width)
    terminal.float_height = normalize_fraction(terminal.float_height, M.defaults.terminal.float_height)
    opts.terminal = terminal
end

function M.build(opts)
    opts = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
    opts.cli = vim.fn.expand(opts.cli)
    opts.fixed_height = opts.fixed_height ~= false
    opts.height = normalize_height(opts.height)
    opts.watch_interval = tonumber(opts.watch_interval) or M.defaults.watch_interval
    validate_agent_config(opts)
    validate_terminal_config(opts)
    validate_worktree_opener(opts)
    return opts
end

function M.available_agent_set(opts)
    local set = {}
    for _, agent in ipairs(opts.available_agents) do
        set[agent] = true
    end
    return set
end

return M
