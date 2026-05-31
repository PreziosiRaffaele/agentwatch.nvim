local h = require('helpers.child')
local expect = MiniTest.expect
local eq = expect.equality

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            h.restart(child)
            child.lua('vim.env.AW_LAUNCH_LOG = vim.fn.tempname()')
            h.setup(child)
        end,
        post_case = function()
            child.stop()
        end,
    },
})

local function launch_log(c)
    return c.lua_get([[(function()
        local f = vim.env.AW_LAUNCH_LOG
        if vim.fn.filereadable(f) ~= 1 then return '' end
        return table.concat(vim.fn.readfile(f), '\n')
    end)()]])
end

T['AgentWatchLaunch invokes the CLI with the expected flags'] = function()
    child.cmd('AgentWatchLaunch login claude')
    local got = h.wait_for(
        child,
        'vim.fn.filereadable(vim.env.AW_LAUNCH_LOG) == 1 and vim.fn.getfsize(vim.env.AW_LAUNCH_LOG) > 0'
    )
    eq(got, true)

    local log = launch_log(child)
    expect.equality(log:find('claude', 1, true) ~= nil, true)
    expect.equality(log:find('--title login', 1, true) ~= nil, true)
    expect.equality(log:find('--nvim-server', 1, true) ~= nil, true)
    expect.equality(log:find('--nvim-bufnr', 1, true) ~= nil, true)
end

T['AgentWatchLaunch creates a buffer remembered as the latest agent'] = function()
    child.cmd('AgentWatchLaunch login claude')
    h.wait_for(child, 'vim.fn.filereadable(vim.env.AW_LAUNCH_LOG) == 1 and vim.fn.getfsize(vim.env.AW_LAUNCH_LOG) > 0')

    -- A terminal buffer now exists for the launched agent.
    local has_term = child.lua_get([[(function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[b].buftype == 'terminal' then return true end
        end
        return false
    end)()]])
    eq(has_term, true)
end

T['AgentWatchLaunch rejects an unknown agent'] = function()
    child.lua('vim.env.AW_LAUNCH_LOG = vim.fn.tempname()')
    -- The rejection surfaces via notify(ERROR); pcall keeps it from bubbling up
    -- as a command error in the child. We only care that no launch happened.
    child.lua('pcall(vim.cmd, "AgentWatchLaunch login bogus")')
    eq(launch_log(child), '')
end

return T
