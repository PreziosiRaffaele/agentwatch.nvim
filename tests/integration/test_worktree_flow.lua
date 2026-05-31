local h = require('helpers.child')
local expect = MiniTest.expect
local eq = expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            h.restart(child)
            h.setup(child)
            child.lua([[
                _G.git = function(dir, args)
                    return vim.fn.system('git -C ' .. vim.fn.shellescape(dir) .. ' ' .. args)
                end
                _G.make_repo = function()
                    local dir = vim.fn.tempname()
                    vim.fn.mkdir(dir, 'p')
                    vim.fn.system('git init -q ' .. vim.fn.shellescape(dir))
                    _G.git(dir, 'config user.email t@example.com')
                    _G.git(dir, 'config user.name tester')
                    _G.git(dir, 'commit -q --allow-empty -m init')
                    return dir
                end
                _G.repo = _G.make_repo()
            ]])
        end,
        post_case = function()
            child.stop()
        end,
    },
})

T['add() creates a linked worktree that reports its branch'] = function()
    local res = child.lua_get([[(function()
        local wt = require('agent-watch.worktree')
        local path = _G.repo .. '/.worktrees/feature-x'
        local add_err = wt.add(_G.repo, 'feature-x', path)
        return {
            add_err = add_err,
            exists = vim.uv.fs_stat(path) ~= nil,
            attach_ok = wt.attachable_path(path) ~= nil,
            linked = wt.is_linked_path(path),
            main_linked = wt.is_linked_path(_G.repo),
            branch = wt.current_branch(path),
        }
    end)()]])

    eq(res.add_err, nil)
    eq(res.exists, true)
    eq(res.attach_ok, true)
    eq(res.linked, true)
    eq(res.main_linked, false)
    eq(res.branch, 'feature-x')
end

T['removable_path() refuses the main working tree'] = function()
    local res = child.lua_get([[(function()
        local wt = require('agent-watch.worktree')
        local path, err = wt.removable_path(_G.repo)
        return { path = path, err = err }
    end)()]])
    eq(res.path, nil)
    expect.equality(type(res.err) == 'string', true)
end

T['remove() deletes a linked worktree'] = function()
    local res = child.lua_get([[(function()
        local wt = require('agent-watch.worktree')
        local path = _G.repo .. '/.worktrees/to-remove'
        wt.add(_G.repo, 'to-remove', path)
        local before = vim.uv.fs_stat(path) ~= nil
        local removed = wt.remove(path)
        return { before = before, removed_ok = removed ~= nil, after = vim.uv.fs_stat(path) ~= nil }
    end)()]])
    eq(res.before, true)
    eq(res.removed_ok, true)
    eq(res.after, false)
end

T['AgentWatchLaunchWorktree creates a worktree and launches in it'] = function()
    child.lua([[
        vim.env.AW_LAUNCH_LOG = vim.fn.tempname()
        vim.fn.chdir(_G.repo)
    ]])
    child.cmd('AgentWatchLaunchWorktree login')
    eq(
        h.wait_for(
            child,
            'vim.fn.filereadable(vim.env.AW_LAUNCH_LOG) == 1 and vim.fn.getfsize(vim.env.AW_LAUNCH_LOG) > 0'
        ),
        true
    )

    local res = child.lua_get([[(function()
        local path = _G.repo .. '/.worktrees/login'
        return {
            exists = vim.uv.fs_stat(path) ~= nil,
            log = table.concat(vim.fn.readfile(vim.env.AW_LAUNCH_LOG), '\n'),
        }
    end)()]])
    eq(res.exists, true)
    expect.equality(res.log:find('--title login', 1, true) ~= nil, true)
end

return T
