local M = {}

local function display_width(value, width)
    value = tostring(value or '')
    local visible = vim.fn.strdisplaywidth(value)
    if visible > width then
        return vim.fn.strcharpart(value, 0, math.max(width - 3, 0)) .. '...'
    end
    return value .. string.rep(' ', width - visible)
end

function M.field(row, names)
    for _, name in ipairs(names) do
        local value = row[name]
        if value ~= nil and value ~= vim.NIL and value ~= '' then
            return value
        end
    end
    return ''
end

function M.bufnr(row)
    local bufnr = tonumber(row.nvim_terminal_bufnr)
    if not bufnr then
        return nil
    end
    return bufnr
end

function M.id(row)
    local id = M.field(row, { 'id', 'launch_id', 'agent_id' })
    if id == '' then
        return nil
    end
    return tostring(id)
end

function M.filter(rows, server)
    local filtered = {}
    for _, row in ipairs(rows) do
        if type(row) == 'table' and row.nvim_server == server then
            local bufnr = M.bufnr(row)
            if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
                table.insert(filtered, row)
            end
        end
    end
    return filtered
end

function M.render(rows)
    local lines = {}
    local rows_by_line = {}

    if #rows == 0 then
        table.insert(lines, 'No active agents for this Neovim server.')
        return lines, rows_by_line
    end

    local header = table.concat({
        display_width('ID', 5),
        display_width('STATE', 16),
        display_width('AGENT', 10),
        display_width('TITLE', 32),
        display_width('REPO', 24),
        display_width('BRANCH', 18),
        display_width('UPDATED', 24),
    }, '  ')

    table.insert(lines, header)
    table.insert(lines, string.rep('-', vim.fn.strdisplaywidth(header)))

    for _, row in ipairs(rows) do
        local line = table.concat({
            display_width(M.id(row) or '', 5),
            display_width(M.field(row, { 'state', 'status' }), 16),
            display_width(M.field(row, { 'agent', 'agent_type', 'type' }), 10),
            display_width(M.field(row, { 'title', 'name', 'summary' }), 32),
            display_width(M.field(row, { 'repo', 'repository', 'cwd' }), 24),
            display_width(M.field(row, { 'branch', 'git_branch' }), 18),
            display_width(M.field(row, { 'updated', 'updated_at', 'updatedAt' }), 24),
        }, '  ')

        table.insert(lines, line)
        rows_by_line[#lines] = row
    end

    return lines, rows_by_line
end

return M
