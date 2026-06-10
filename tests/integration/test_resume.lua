local h = require('helpers.child')
local expect = MiniTest.expect
local eq = expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            h.restart(child)
            h.setup(child)
            -- A real repo the child cds into, plus one exited daemon row from a
            -- dead Neovim session in the same project. The row's project_root is
            -- resolved with the same routine the watcher uses.
            child.lua([[
                _G.git = function(dir, args)
                    return vim.fn.system('git -C ' .. vim.fn.shellescape(dir) .. ' ' .. args)
                end
                _G.repo = (function()
                    local dir = vim.fn.tempname()
                    vim.fn.mkdir(dir, 'p')
                    vim.fn.system('git init -q ' .. vim.fn.shellescape(dir))
                    _G.git(dir, 'config user.email t@example.com')
                    _G.git(dir, 'config user.name tester')
                    _G.git(dir, 'commit -q --allow-empty -m init')
                    return dir
                end)()
                vim.fn.chdir(_G.repo)
                _G.project_root = require('agent-watch.worktree').project_root()

                _G.write_agents = function(row)
                    local f = vim.env.AW_DAEMON_AGENTS_FILE or vim.fn.tempname()
                    vim.fn.writefile({ vim.json.encode({ row }) }, f)
                    vim.env.AW_DAEMON_AGENTS_FILE = f
                end
                _G.exited_row = {
                    id = 7, title = 'fix login', state = 'exited', agent = 'claude',
                    branch = 'fix-login', folder = _G.repo, project_root = _G.project_root,
                    nvim_server = '/tmp/dead-server', nvim_terminal_bufnr = 999999,
                }
                _G.write_agents(_G.exited_row)

                _G.notes = {}
                vim.notify = function(msg)
                    table.insert(_G.notes, msg)
                end

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
                _G.select_row = function(line)
                    for _, w in ipairs(vim.api.nvim_list_wins()) do
                        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agent-watch' then
                            vim.api.nvim_set_current_win(w)
                            vim.api.nvim_win_set_cursor(w, { line or 2, 0 })
                        end
                    end
                end
            ]])
        end,
        post_case = function()
            child.stop()
        end,
    },
})

T['project_root() groups the main repo with its linked worktrees'] = function()
    local res = child.lua_get([[(function()
        local wt = require('agent-watch.worktree')
        local path = _G.repo .. '/.worktrees/feature-x'
        wt.add(_G.repo, 'feature-x', path)
        vim.fn.chdir(path)
        local from_worktree = wt.project_root()
        local plain = vim.fn.tempname()
        vim.fn.mkdir(plain, 'p')
        vim.fn.chdir(plain)
        local from_plain = wt.project_root()
        return { main = _G.project_root, worktree = from_worktree, plain = from_plain, cwd = vim.uv.cwd() }
    end)()]])

    eq(res.worktree, res.main)
    eq(res.plain == res.main, false)
    eq(res.plain, res.cwd)
end

T['the watch buffer shows exited rows from a dead session in this project'] = function()
    child.cmd('AgentWatch')
    eq(h.wait_for(child, "_G.watch_has('fix login')"), true)
    eq(child.lua_get("_G.watch_has('exited')"), true)
end

T['<CR> on an exited row resumes it attached to this session'] = function()
    child.lua('vim.env.AW_LAUNCH_LOG = vim.fn.tempname()')
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua('_G.select_row(2)')
    child.type_keys('<CR>')
    eq(
        h.wait_for(
            child,
            'vim.fn.filereadable(vim.env.AW_LAUNCH_LOG) == 1 and vim.fn.getfsize(vim.env.AW_LAUNCH_LOG) > 0'
        ),
        true
    )

    local log = child.lua_get("table.concat(vim.fn.readfile(vim.env.AW_LAUNCH_LOG), '\\n')")
    expect.equality(log:find('resume 7 --nvim-server ', 1, true) == 1, true)
    expect.equality(log:find('--nvim-bufnr', 1, true) ~= nil, true)
end

T['<CR> refuses to resume when the agent folder is gone'] = function()
    child.lua([[
        vim.env.AW_LAUNCH_LOG = vim.fn.tempname()
        _G.exited_row.folder = _G.repo .. '/gone'
        _G.write_agents(_G.exited_row)
    ]])
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua('_G.select_row(2)')
    child.type_keys('<CR>')
    eq(
        h.wait_for(
            child,
            [[(function()
        for _, n in ipairs(_G.notes) do
            if n:find('no longer exists', 1, true) then return true end
        end
        return false
    end)()]]
        ),
        true
    )
    eq(child.lua_get('vim.fn.getfsize(vim.env.AW_LAUNCH_LOG) > 0'), false)
end

T['dd on an exited row deletes the daemon record after confirmation'] = function()
    child.lua([[
        vim.env.AW_DAEMON_DELETE_LOG = vim.fn.tempname()
        vim.fn.input = function() return 'y' end
    ]])
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua('_G.select_row(2)')
    child.type_keys('dd')
    eq(
        h.wait_for(
            child,
            'vim.fn.filereadable(vim.env.AW_DAEMON_DELETE_LOG) == 1'
                .. ' and vim.fn.getfsize(vim.env.AW_DAEMON_DELETE_LOG) > 0'
        ),
        true
    )

    local log = child.lua_get("table.concat(vim.fn.readfile(vim.env.AW_DAEMON_DELETE_LOG), '\\n')")
    expect.equality(log:find('/launches/7', 1, true) ~= nil, true)
end

return T
