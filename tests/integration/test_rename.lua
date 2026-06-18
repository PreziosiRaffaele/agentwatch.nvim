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
                _G.agent_buf = vim.api.nvim_create_buf(false, true)
                vim.b[_G.agent_buf].agent_watch_ref = 'ref-live'
                local row = {
                    id = 42, title = 'old title', state = 'working', agent = 'claude',
                    branch = 'fix-login', client_ref = 'ref-live',
                }
                local f = vim.fn.tempname()
                vim.fn.writefile({ vim.json.encode({ row }) }, f)
                vim.env.AW_DAEMON_AGENTS_FILE = f
                vim.env.AW_DAEMON_PATCH_LOG = vim.fn.tempname()
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

T['AgentWatchRename PATCHes the selected launch'] = function()
    child.cmd('AgentWatch')
    h.wait_for(child, "_G.watch_has('old title')")

    -- Focus the watch window so the selected row resolves.
    child.lua([[
        for _, w in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == 'agent-watch' then
                vim.api.nvim_set_current_win(w)
            end
        end
    ]])

    child.cmd('AgentWatchRename brand new title')
    local recorded = h.wait_for(child, 'vim.fn.getfsize(vim.env.AW_DAEMON_PATCH_LOG) > 0')
    eq(recorded, true)

    local log = child.lua_get([[table.concat(vim.fn.readfile(vim.env.AW_DAEMON_PATCH_LOG), '\n')]])
    -- PATCH hit /launches/<id> with the new title in the body.
    expect.equality(log:find('/launches/42', 1, true) ~= nil, true)
    expect.equality(log:find('"title":"brand new title"', 1, true) ~= nil, true)
end

return T
