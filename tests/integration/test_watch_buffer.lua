local h = require('helpers.child')
local expect = MiniTest.expect
local eq = expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            h.restart(child)
            h.setup(child)
            -- A real buffer stamped with the row's client_ref so actions that
            -- open or delete terminal buffers can exercise the normal path.
            child.lua([[
                _G.agent_buf = vim.api.nvim_create_buf(false, true)
                vim.b[_G.agent_buf].agent_watch_ref = 'ref-live'
                local row = {
                    id = 1, title = 'fix login', state = 'working', agent = 'claude',
                    branch = 'fix-login', folder = '/tmp/x',
                    client_ref = 'ref-live',
                }
                local f = vim.fn.tempname()
                vim.fn.writefile({ vim.json.encode({ row }) }, f)
                vim.env.AW_DAEMON_AGENTS_FILE = f
                vim.env.AW_DAEMON_DELETE_LOG = vim.fn.tempname()
                vim.env.AW_DAEMON_ENSURE_LOG = vim.fn.tempname()
                _G.watch_has = function(pat)
                    for _, b in ipairs(vim.api.nvim_list_bufs()) do
                        if vim.bo[b].filetype == 'agent-watch' then
                            for _, l in ipairs(vim.api.nvim_buf_get_lines(b, 0, -1, false)) do
                                if l:find(pat, 1, true) then return true end
                            end
                        end
                    end
                    return false
                end
            ]])
        end,
        post_case = function()
            child.stop()
        end,
    },
})

T['AgentWatch ensures the daemon before rendering rows'] = function()
    child.cmd('AgentWatch')
    eq(h.wait_for(child, 'vim.fn.getfsize(vim.env.AW_DAEMON_ENSURE_LOG) > 0'), true)
    eq(h.wait_for(child, "_G.watch_has('fix login')"), true)

    local log = child.lua_get([[table.concat(vim.fn.readfile(vim.env.AW_DAEMON_ENSURE_LOG), '\n')]])
    eq(log, 'daemon ensure')

    child.lua([[
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agent-watch' then
                vim.api.nvim_set_current_win(w)
            end
        end
    ]])
    child.type_keys('q')
    eq(child.lua_get([[require('agent-watch.watch_window').visible()]]), false)

    child.cmd('AgentWatch')
    eq(h.wait_for(child, "_G.watch_has('fix login')"), true)
    eq(child.lua_get([[#vim.fn.readfile(vim.env.AW_DAEMON_ENSURE_LOG)]]), 1)
end

T['AgentWatch renders the filtered daemon rows'] = function()
    child.cmd('AgentWatch')
    eq(h.wait_for(child, "_G.watch_has('fix login')"), true)

    local lines = h.watch_lines(child)
    expect.equality(lines[1]:match('^TITLE') ~= nil, true)
    expect.equality(h.watch_lines(child)[2]:find('working', 1, true) ~= nil, true)
end

T['AgentWatch renders exited project rows whose terminal buffer is gone'] = function()
    child.lua([[
        local row = {
            id = 2, title = 'finished task', state = 'exited', agent = 'codex',
            branch = 'main', folder = '/tmp/x', client_ref = 'ref-gone',
            project_root = require('agent-watch.worktree').project_root(),
        }
        vim.fn.writefile({ vim.json.encode({ row }) }, vim.env.AW_DAEMON_AGENTS_FILE)
    ]])

    child.cmd('AgentWatch')
    eq(h.wait_for(child, "_G.watch_has('finished task')"), true)
    eq(h.wait_for(child, "_G.watch_has('exited')"), true)
end

T['AgentWatch highlights the STATE column'] = function()
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    local marks = child.lua_get([[(function()
        local ns = vim.api.nvim_get_namespaces()['agent-watch-state']
        if not ns then return 0 end
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[b].filetype == 'agent-watch' then
                return #vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, {})
            end
        end
        return 0
    end)()]])
    expect.equality(marks > 0, true)
end

T['AgentWatch surfaces a daemon failure'] = function()
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua('vim.env.AW_DAEMON_FAIL = "1"')
    child.lua('require("agent-watch").refresh()')
    eq(h.wait_for(child, "_G.watch_has('request failed')"), true)
end

T['AgentWatch surfaces a daemon ensure failure'] = function()
    child.lua('vim.env.AW_DAEMON_ENSURE_FAIL = "1"')
    child.cmd('AgentWatch')
    eq(h.wait_for(child, "_G.watch_has('aw daemon ensure failed')"), true)
    eq(h.wait_for(child, "_G.watch_has('simulated daemon ensure failure')"), true)
end

T['q closes the watch window and stops watching'] = function()
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua([[
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agent-watch' then
                vim.api.nvim_set_current_win(w)
            end
        end
    ]])
    child.type_keys('q')
    eq(child.lua_get([[require('agent-watch.watch_window').visible()]]), false)
end

T['dd cancels agent deletion without confirmation'] = function()
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua([[
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agent-watch' then
                vim.api.nvim_set_current_win(w)
            end
        end
    ]])
    child.type_keys('dd')
    child.type_keys('n<CR>')

    eq(child.lua_get('vim.fn.filereadable(vim.env.AW_DAEMON_DELETE_LOG)'), 0)
    eq(child.lua_get('vim.api.nvim_buf_is_valid(_G.agent_buf)'), true)
end

T['dd confirms and DELETEs the selected launch'] = function()
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua([[
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agent-watch' then
                vim.api.nvim_set_current_win(w)
            end
        end
    ]])
    child.type_keys('dd')
    child.type_keys('y<CR>')

    eq(h.wait_for(child, 'vim.fn.getfsize(vim.env.AW_DAEMON_DELETE_LOG) > 0'), true)
    local log = child.lua_get([[table.concat(vim.fn.readfile(vim.env.AW_DAEMON_DELETE_LOG), '\n')]])
    expect.equality(log:find('/launches/1', 1, true) ~= nil, true)
    eq(h.wait_for(child, 'not vim.api.nvim_buf_is_valid(_G.agent_buf)'), true)
end

return T
