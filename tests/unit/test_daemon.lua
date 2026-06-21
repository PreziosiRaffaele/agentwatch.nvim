local daemon = require('agent-watch.daemon')
local expect = MiniTest.expect
local eq = expect.equality

local T = MiniTest.new_set()

T['resolve_url()'] = MiniTest.new_set()

T['resolve_url()']['prefers an explicit daemon_url and trims trailing slashes'] = function()
    eq(daemon.resolve_url({ daemon_url = 'http://host:1234' }), 'http://host:1234')
    eq(daemon.resolve_url({ daemon_url = 'http://host:1234//' }), 'http://host:1234')
    eq(daemon.resolve_url({ daemon_url = '  http://host:9/  ' }), 'http://host:9')
end

T['resolve_url()']['falls back to the default when nothing is configured'] = MiniTest.new_set({
    hooks = {
        -- Isolate HOME so a developer's real ~/.agent-watch/daemon.json cannot
        -- influence the default-resolution path.
        pre_case = function()
            _G._saved_home = vim.env.HOME
            vim.env.HOME = vim.fn.tempname()
        end,
        post_case = function()
            vim.env.HOME = _G._saved_home
            _G._saved_home = nil
        end,
    },
})

T['resolve_url()']['falls back to the default when nothing is configured']['uses localhost:3847'] = function()
    eq(daemon.resolve_url({}), 'http://127.0.0.1:3847')
end

local function ensure_with_result(code, stdout, stderr)
    local original = vim.system
    local captured = nil
    local captured_opts = nil
    vim.system = function(cmd, opts, cb)
        captured = cmd
        captured_opts = opts
        cb({ code = code or 0, stdout = stdout or '', stderr = stderr or '' })
        return { wait = function() end }
    end

    local result = { done = false }
    daemon.ensure({ cli = '/tmp/aw' }, function(err)
        result.err = err
        result.done = true
    end)
    vim.wait(1000, function()
        return result.done
    end, 10)

    vim.system = original
    result.cmd = captured
    result.opts = captured_opts
    return result
end

T['ensure()'] = MiniTest.new_set()

T['ensure()']['runs aw daemon ensure through the configured CLI'] = function()
    local result = ensure_with_result(0)
    eq(result.err, nil)
    eq(result.cmd, { '/tmp/aw', 'daemon', 'ensure' })
    eq(result.opts.timeout, 5000)
end

T['ensure()']['reports a command failure'] = function()
    local result = ensure_with_result(1, '', 'boom')
    eq(result.err, 'boom')
end

T['ensure()']['reports a timeout failure'] = function()
    local result = ensure_with_result(124, '', '')
    eq(result.err, 'aw daemon ensure timed out')
end

-- Drive list_agents with a stubbed vim.system so we exercise the real JSON
-- parsing without spawning curl.
local function list_with_stdout(stdout, code)
    local original = vim.system
    vim.system = function(_, _, cb)
        cb({ code = code or 0, stdout = stdout, stderr = '' })
        return { wait = function() end }
    end

    local result = { done = false }
    daemon.list_agents({ daemon_url = 'http://x' }, function(parsed_rows, err)
        result.rows = parsed_rows
        result.err = err
        result.done = true
    end)
    vim.wait(1000, function()
        return result.done
    end, 10)

    vim.system = original
    return result
end

T['list_agents()'] = MiniTest.new_set()

T['list_agents()']['parses a bare JSON array'] = function()
    local result = list_with_stdout('[{"id":1,"title":"a"},{"id":2}]')
    eq(result.err, nil)
    eq(#result.rows, 2)
    eq(result.rows[1].title, 'a')
end

T['list_agents()']['unwraps an agents/rows/items envelope'] = function()
    eq(#list_with_stdout('{"agents":[{"id":1}]}').rows, 1)
    eq(#list_with_stdout('{"rows":[{"id":1},{"id":2}]}').rows, 2)
    eq(#list_with_stdout('{"items":[{"id":1}]}').rows, 1)
end

T['list_agents()']['treats unknown shapes as empty'] = function()
    eq(list_with_stdout('{"unexpected":true}').rows, {})
    eq(list_with_stdout('').rows, {})
end

T['list_agents()']['reports a parse error for malformed JSON'] = function()
    local result = list_with_stdout('{not json')
    eq(result.rows, nil)
    expect.equality(type(result.err) == 'string', true)
end

T['list_agents()']['reports a request failure on non-zero exit'] = function()
    local result = list_with_stdout('', 7)
    eq(result.rows, nil)
    expect.equality(result.err ~= nil, true)
end

T['delete()'] = MiniTest.new_set()

T['delete()']['sends DELETE to the launch endpoint'] = function()
    local original = vim.system
    local captured = nil
    vim.system = function(cmd, _, cb)
        captured = cmd
        cb({ code = 0, stdout = '{}', stderr = '' })
        return { wait = function() end }
    end

    local result = { done = false }
    daemon.delete({ daemon_url = 'http://x' }, '42', function(err)
        result.err = err
        result.done = true
    end)
    vim.wait(1000, function()
        return result.done
    end, 10)

    vim.system = original
    eq(result.err, nil)
    eq(captured, { 'curl', '-fsS', '--max-time', '5', '-X', 'DELETE', 'http://x/launches/42' })
end

T['delete()']['reports a request failure on non-zero exit'] = function()
    local original = vim.system
    vim.system = function(_, _, cb)
        cb({ code = 22, stdout = '', stderr = 'boom' })
        return { wait = function() end }
    end

    local result = { done = false }
    daemon.delete({ daemon_url = 'http://x' }, '7', function(err)
        result.err = err
        result.done = true
    end)
    vim.wait(1000, function()
        return result.done
    end, 10)

    vim.system = original
    eq(result.err, 'boom')
end

return T
