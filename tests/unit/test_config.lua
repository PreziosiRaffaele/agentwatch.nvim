local config = require('agent-watch.config')
local expect = MiniTest.expect
local eq = expect.equality

local T = MiniTest.new_set()

T['build()'] = MiniTest.new_set()

T['build()']['returns defaults for an empty table'] = function()
    local opts = config.build({})
    eq(opts.default_agent, 'claude')
    eq(opts.available_agents, { 'codex', 'agent', 'claude' })
    eq(opts.terminal.layout, 'side')
    eq(opts.worktree_opener, 'nvim')
    eq(opts.watch_interval, 1000)
end

T['build()']['normalizes height and watch_interval'] = function()
    eq(config.build({ height = 0 }).height, 8)
    eq(config.build({ height = 12.7 }).height, 12)
    eq(config.build({ watch_interval = 'nope' }).watch_interval, 1000)
end

T['build()']['rejects an unknown agent in available_agents'] = function()
    local opts = config.build({ available_agents = { 'claude', 'bogus' } })
    eq(opts.available_agents, { 'codex', 'agent', 'claude' })
end

T['build()']['rejects an empty available_agents'] = function()
    local opts = config.build({ available_agents = {} })
    eq(opts.available_agents, { 'codex', 'agent', 'claude' })
end

T['build()']['falls back default_agent into available_agents'] = function()
    local opts = config.build({ available_agents = { 'codex' }, default_agent = 'claude' })
    eq(opts.available_agents, { 'codex' })
    eq(opts.default_agent, 'codex')
end

T['build()']['rejects an invalid terminal layout and side'] = function()
    local opts = config.build({ terminal = { layout = 'diagonal', side = 'up' } })
    eq(opts.terminal.layout, 'side')
    eq(opts.terminal.side, 'right')
end

T['build()']['clamps terminal fractions and width'] = function()
    local opts = config.build({ terminal = { width = -3, float_width = 2, float_height = 0 } })
    eq(opts.terminal.width, 80)
    eq(opts.terminal.float_width, 0.9)
    eq(opts.terminal.float_height, 0.85)
end

T['build()']['rejects an invalid worktree_opener'] = function()
    eq(config.build({ worktree_opener = 'emacs' }).worktree_opener, 'nvim')
    eq(config.build({ worktree_opener = 'tmux' }).worktree_opener, 'tmux')
end

T['available_agent_set()'] = MiniTest.new_set()

T['available_agent_set()']['builds a lookup of configured agents'] = function()
    local set = config.available_agent_set({ available_agents = { 'codex', 'claude' } })
    eq(set.codex, true)
    eq(set.claude, true)
    eq(set.agent, nil)
end

return T
