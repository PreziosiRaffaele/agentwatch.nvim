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

T['bufnr()']['resolves a row to the buffer stamped with its client_ref'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].agent_watch_ref = 'ref-a'
    eq(rows.bufnr({ client_ref = 'ref-a' }), buf)
    vim.api.nvim_buf_delete(buf, { force = true })
end

T['bufnr()']['returns nil when the ref is missing or matches no buffer'] = function()
    eq(rows.bufnr({}), nil)
    eq(rows.bufnr({ client_ref = vim.NIL }), nil)
    eq(rows.bufnr({ client_ref = 'ref-from-another-session' }), nil)
end

T['id()'] = MiniTest.new_set()

T['id()']['prefers id, then launch_id, then agent_id'] = function()
    eq(rows.id({ id = 3, launch_id = 9 }), '3')
    eq(rows.id({ launch_id = 9 }), '9')
    eq(rows.id({ agent_id = 'x' }), 'x')
    eq(rows.id({}), nil)
end

T['filter()'] = MiniTest.new_set()

T['filter()']['keeps only rows whose client_ref matches a stamped buffer'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].agent_watch_ref = 'ref-mine'
    local input = {
        { id = 1, client_ref = 'ref-mine', title = 'keep' },
        { id = 2, client_ref = 'ref-other-session', title = 'foreign ref' },
        { id = 3, title = 'no ref' },
        'not a table',
    }
    local out = rows.filter(input)
    eq(#out, 1)
    eq(out[1].title, 'keep')
    vim.api.nvim_buf_delete(buf, { force = true })
end

T['filter()']['adopts exited project rows whose ref matches nothing here'] = function()
    local input = {
        { id = 3, state = 'exited', project_root = '/proj', client_ref = 'ref-dead-session' },
        { id = 4, state = 'exited', project_root = '/elsewhere', client_ref = 'ref-dead-session' },
        { id = 5, state = 'working', project_root = '/proj', client_ref = 'ref-dead-session' },
    }
    local out = rows.filter(input, '/proj')
    eq(#out, 1)
    eq(out[1].id, 3)
end

T['filter()']['keeps exited rows owned by this session without a project'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].agent_watch_ref = 'ref-mine'
    local input = {
        { id = 3, state = 'exited', project_root = '/proj', client_ref = 'ref-mine' },
    }
    local out = rows.filter(input)
    eq(#out, 1)
    eq(rows.bufnr(out[1]), buf)
    vim.api.nvim_buf_delete(buf, { force = true })
end

T['filter()']['ignores exited rows without a project root to match'] = function()
    local input = { { id = 3, state = 'exited', project_root = '/proj', client_ref = 'ref-dead-session' } }
    eq(#rows.filter(input), 0)
    eq(#rows.filter(input, ''), 0)
end

T['filter()']['sorts kept rows by launch id ascending'] = function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].agent_watch_ref = 'ref-mine'
    local input = {
        { id = 9, state = 'exited', project_root = '/proj', client_ref = 'ref-dead-session' },
        { id = 2, client_ref = 'ref-mine' },
        { id = 7, state = 'exited', project_root = '/proj', client_ref = 'ref-dead-session' },
    }
    local out = rows.filter(input, '/proj')
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
    eq(lines[1], 'No agents for this Neovim session or project.')
end

T['render()']['emits a header and a dash for missing fields'] = function()
    local lines, by_line, ranges = rows.render({
        { title = 'login', state = 'working', agent = 'claude' },
    })

    expect.equality(lines[1]:match('^TITLE') ~= nil, true)
    -- branch is missing -> rendered as an em dash somewhere on the data line.
    expect.equality(lines[2]:find('—', 1, true) ~= nil, true)
    -- the data row is mapped back to its source row and a state range exists.
    eq(by_line[2].title, 'login')
    eq(ranges[1].state, 'working')
end

T['render()']['truncates values wider than their column'] = function()
    local long = string.rep('x', 40)
    local lines = rows.render({ { title = long, state = 'idle' } })
    expect.equality(lines[2]:find('...', 1, true) ~= nil, true)
end

return T
