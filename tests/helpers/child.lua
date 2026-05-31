-- Child-Neovim helpers for integration tests. Loaded in the runner process;
-- exposes absolute paths and small routines for driving the plugin under test.
local M = {}

local helpers_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')

M.fake_bin = helpers_dir .. '/fake_bin'
M.fake_aw = M.fake_bin .. '/aw'
M.minimal_init = vim.fn.fnamemodify(helpers_dir, ':h') .. '/minimal_init.lua'

-- Start a fresh child with the test rtp and the fake-bin dir ahead on PATH so
-- `curl` resolves to the stub and the daemon is never really contacted.
function M.restart(child)
    child.restart({ '-u', M.minimal_init })
    child.lua('vim.env.PATH = (...) .. ":" .. vim.env.PATH', { M.fake_bin })
end

-- Configure the plugin with the fake CLI and a fixed daemon URL. `extra` is a
-- Lua table literal (string) merged into the setup options.
function M.setup(child, extra)
    local opts = string.format("{ cli = %q, daemon_url = 'http://127.0.0.1:9999', watch_interval = 60000", M.fake_aw)
    if extra and extra ~= '' then
        opts = opts .. ', ' .. extra
    end
    opts = opts .. ' }'
    child.lua('require("agent-watch").setup(' .. opts .. ')')
end

-- Lines currently shown in the agent-watch scratch buffer.
function M.watch_lines(child)
    return child.lua_get([[(function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.bo[b].filetype == 'agent-watch' then
                return vim.api.nvim_buf_get_lines(b, 0, -1, false)
            end
        end
        return {}
    end)()]])
end

-- Block in the child until `predicate` (a Lua expression string) is truthy.
-- lua_get prepends its own `return`, so the code here must not.
function M.wait_for(child, predicate, timeout)
    local code = string.format('vim.wait(%d, function() return %s end, 20)', timeout or 2000, predicate)
    return child.lua_get(code)
end

return M
