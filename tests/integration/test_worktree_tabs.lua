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
                local repo = vim.fn.tempname()
                vim.fn.mkdir(repo, 'p')
                local function git(args)
                    return vim.fn.system('git -C ' .. vim.fn.shellescape(repo) .. ' ' .. args)
                end
                vim.fn.system('git init -q ' .. vim.fn.shellescape(repo))
                git('config user.email t@example.com')
                git('config user.name tester')
                git('commit -q --allow-empty -m init')

                _G.worktree_path = repo .. '/.worktrees/feature-x'
                require('agent-watch.worktree').add(repo, 'feature-x', _G.worktree_path)

                _G.agent_buf = vim.api.nvim_create_buf(false, true)
                local row = {
                    id = 1, title = 'fix login', state = 'idle', agent = 'claude',
                    branch = 'feature-x', folder = _G.worktree_path,
                    nvim_server = vim.v.servername,
                    nvim_terminal_bufnr = _G.agent_buf,
                }
                local f = vim.fn.tempname()
                vim.fn.writefile({ vim.json.encode({ row }) }, f)
                vim.env.AW_DAEMON_AGENTS_FILE = f
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

T['o opens the worktree in a tab and labels it [branch] fileName'] = function()
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('fix login')")

    child.lua([[
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agent-watch' then
                vim.api.nvim_set_current_win(w)
            end
        end
    ]])
    child.type_keys('o')

    -- The new tab carries Agent Watch metadata and the tabline labels it.
    eq(child.lua_get('vim.t.agent_watch_branch'), 'feature-x')
    eq(child.lua_get('vim.t.agent_watch_worktree'), child.lua_get('_G.worktree_path'))

    local tabline = child.lua_get([[require('agent-watch.worktree_tabs').render()]])
    expect.equality(tabline:find('[feature-x]', 1, true) ~= nil, true)
end

return T
