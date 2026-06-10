local rows = require('agent-watch.rows')
local expect = MiniTest.expect
local eq = expect.equality

local T = MiniTest.new_set()

T['field()'] = MiniTest.new_set()

T['field()']['returns the first non-empty candidate'] = function()
    eq(rows.field({ title = 'a', name = 'b' }, { 'title', 'name' }), 'a')
    eq(rows.field({ name = 'b' }, { 'title', 'name' }), 'b')
end

T['field()']['skips empty, nil, and vim.NIL values'] = function()
    eq(rows.field({ title = '', name = 'b' }, { 'title', 'name' }), 'b')
    eq(rows.field({ title = vim.NIL, summary = 's' }, { 'title', 'summary' }), 's')
    eq(rows.field({}, { 'title' }), '')
end

T['bufnr()'] = MiniTest.new_set()

T['bufnr()']['coerces strings to numbers'] = function()
    eq(rows.bufnr({ nvim_terminal_bufnr = '7' }), 7)
    eq(rows.bufnr({ nvim_terminal_bufnr = 7 }), 7)
end

T['bufnr()']['returns nil when missing or non-numeric'] = function()
    eq(rows.bufnr({}), nil)
    eq(rows.bufnr({ nvim_terminal_bufnr = 'abc' }), nil)
end

T['id()'] = MiniTest.new_set()

T['id()']['prefers id, then launch_id, then agent_id'] = function()
    eq(rows.id({ id = 3, launch_id = 9 }), '3')
    eq(rows.id({ launch_id = 9 }), '9')
    eq(rows.id({ agent_id = 'x' }), 'x')
    eq(rows.id({}), nil)
end

T['filter()'] = MiniTest.new_set()

T['filter()']['keeps matching server rows even without a valid buffer'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    local input = {
        { nvim_server = 'srv', nvim_terminal_bufnr = buf, title = 'keep' },
        { nvim_server = 'other', nvim_terminal_bufnr = buf, title = 'wrong server' },
        { nvim_server = 'srv', nvim_terminal_bufnr = 999999, title = 'dead buffer' },
        { nvim_server = 'srv', title = 'missing buffer' },
        'not a table',
    }
    local out = rows.filter(input, 'srv')
    eq(#out, 3)
    eq(out[1].title, 'keep')
    eq(out[2].title, 'dead buffer')
    eq(out[3].title, 'missing buffer')
    vim.api.nvim_buf_delete(buf, { force = true })
end

T['filter()']['adopts exited project rows regardless of server and buffer'] = function()
    local input = {
        { id = 3, state = 'exited', project_root = '/proj', nvim_server = 'dead', nvim_terminal_bufnr = 999999 },
        { id = 4, state = 'exited', project_root = '/elsewhere', nvim_server = 'dead' },
        { id = 5, state = 'working', project_root = '/proj', nvim_server = 'dead', nvim_terminal_bufnr = 999999 },
    }
    local out = rows.filter(input, 'srv', '/proj')
    eq(#out, 1)
    eq(out[1].id, 3)
end

T['filter()']['ignores exited rows without a project root to match'] = function()
    local input = { { id = 3, state = 'exited', project_root = '/proj', nvim_server = 'dead' } }
    eq(#rows.filter(input, 'srv'), 0)
    eq(#rows.filter(input, 'srv', ''), 0)
end

T['filter()']['sorts kept rows by launch id ascending'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    local input = {
        { id = 9, state = 'exited', project_root = '/proj', nvim_server = 'dead' },
        { id = 2, nvim_server = 'srv', nvim_terminal_bufnr = buf },
        { id = 7, state = 'exited', project_root = '/proj', nvim_server = 'dead' },
    }
    local out = rows.filter(input, 'srv', '/proj')
    eq({ out[1].id, out[2].id, out[3].id }, { 2, 7, 9 })
    vim.api.nvim_buf_delete(buf, { force = true })
end

T['is_exited()'] = MiniTest.new_set()

T['is_exited()']['matches only the exited state'] = function()
    eq(rows.is_exited({ state = 'exited' }), true)
    eq(rows.is_exited({ status = 'exited' }), true)
    eq(rows.is_exited({ state = 'working' }), false)
    eq(rows.is_exited({}), false)
    eq(rows.is_exited('not a table'), false)
end

T['render()'] = MiniTest.new_set()

T['render()']['shows a placeholder when there are no rows'] = function()
    local lines = rows.render({})
    eq(#lines, 1)
    eq(lines[1], 'No agents for this Neovim server or project.')
end

T['render()']['emits a header and a dash for missing fields'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    local lines, by_line, ranges = rows.render({
        { nvim_terminal_bufnr = buf, title = 'login', state = 'working', agent = 'claude' },
    })

    expect.equality(lines[1]:match('^TITLE') ~= nil, true)
    -- branch is missing -> rendered as an em dash somewhere on the data line.
    expect.equality(lines[2]:find('—', 1, true) ~= nil, true)
    -- the data row is mapped back to its source row and a state range exists.
    eq(by_line[2].title, 'login')
    eq(ranges[1].state, 'working')
    vim.api.nvim_buf_delete(buf, { force = true })
end

T['render()']['truncates values wider than their column'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    local long = string.rep('x', 40)
    local lines = rows.render({ { nvim_terminal_bufnr = buf, title = long, state = 'idle' } })
    expect.equality(lines[2]:find('...', 1, true) ~= nil, true)
    vim.api.nvim_buf_delete(buf, { force = true })
end

return T
