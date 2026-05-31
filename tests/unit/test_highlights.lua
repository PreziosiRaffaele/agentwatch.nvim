local highlights = require('agent-watch.highlights')
local expect = MiniTest.expect
local eq = expect.equality

local T = MiniTest.new_set()

T['state_group()'] = MiniTest.new_set()

T['state_group()']['maps known states to their group'] = function()
    eq(highlights.state_group('working'), 'AgentWatchStateRunning')
    eq(highlights.state_group('session_started'), 'AgentWatchStateRunning')
    eq(highlights.state_group('needs_approval'), 'AgentWatchStateWaiting')
    eq(highlights.state_group('queued'), 'AgentWatchStateWaiting')
    eq(highlights.state_group('completed'), 'AgentWatchStateDone')
    eq(highlights.state_group('failed'), 'AgentWatchStateError')
    eq(highlights.state_group('idle'), 'AgentWatchStateIdle')
    eq(highlights.state_group('edited_file'), 'AgentWatchStateChanged')
end

T['state_group()']['is case- and whitespace-insensitive'] = function()
    eq(highlights.state_group('  WORKING '), 'AgentWatchStateRunning')
    eq(highlights.state_group('Done'), 'AgentWatchStateDone')
end

T['state_group()']['returns nil for empty input'] = function()
    eq(highlights.state_group(''), nil)
    eq(highlights.state_group('   '), nil)
    eq(highlights.state_group(nil), nil)
end

T['state_group()']['falls back to Unknown for unmapped states'] = function()
    eq(highlights.state_group('something-else'), 'AgentWatchStateUnknown')
end

return T
