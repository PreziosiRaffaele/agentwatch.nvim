local M = {}

local function relative_time(ts)
    if not ts or ts == '' or ts == vim.NIL then
        return ''
    end

    local epoch
    if type(ts) == 'number' then
        epoch = ts
    else
        local s = tostring(ts)
        local year, month, day, hour, min, sec = s:match('^(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):(%d%d)')
        if not year then
            return s
        end
        -- os.time interprets the table as local time; if the daemon sends UTC
        -- timestamps (Z suffix), compute the local→UTC offset and correct.
        local naive = os.time({
            year = tonumber(year),
            month = tonumber(month),
            day = tonumber(day),
            hour = tonumber(hour),
            min = tonumber(min),
            sec = tonumber(sec),
            isdst = false,
        })
        if s:match('Z$') or s:match('[+-]%d%d:?%d%d$') then
            -- os.time() is UTC epoch; os.time(os.date('!*t')) treats the UTC
            -- time breakdown as local, giving (epoch - local_offset). The
            -- difference is the local UTC offset in seconds.
            local utc_d = os.date('!*t') --[[@as osdateparam]]
            local offset = os.difftime(os.time(), os.time(utc_d))
            epoch = naive + offset
        else
            epoch = naive
        end
    end

    local diff = os.difftime(os.time(), epoch)
    if diff < 60 then
        return 'just now'
    elseif diff < 120 then
        return '< 2m ago'
    elseif diff < 300 then
        return '< 5m ago'
    elseif diff < 600 then
        return '< 10m ago'
    elseif diff < 900 then
        return '< 15m ago'
    elseif diff < 1800 then
        return '< 30m ago'
    elseif diff < 2700 then
        return '< 45m ago'
    elseif diff < 3600 then
        return '< 1h ago'
    elseif diff < 5400 then
        return '< 1.5h ago'
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. 'h ago'
    else
        return math.floor(diff / 86400) .. 'd ago'
    end
end

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
        display_width('TITLE', 30),
        display_width('BRANCH', 40),
        display_width('UPDATED', 10),
    }, '  ')

    table.insert(lines, header)
    table.insert(lines, string.rep('-', vim.fn.strdisplaywidth(header)))

    for _, row in ipairs(rows) do
        local line = table.concat({
            display_width(M.id(row) or '', 5),
            display_width(M.field(row, { 'state', 'status' }), 16),
            display_width(M.field(row, { 'agent', 'agent_type', 'type' }), 10),
            display_width(M.field(row, { 'title', 'name', 'summary' }), 30),
            display_width(M.field(row, { 'branch', 'git_branch' }), 40),
            display_width(relative_time(M.field(row, { 'updated', 'updated_at', 'updatedAt' })), 10),
        }, '  ')

        table.insert(lines, line)
        rows_by_line[#lines] = row
    end

    return lines, rows_by_line
end

return M
