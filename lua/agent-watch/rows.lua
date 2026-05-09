local M = {}

local title_width = 20
local state_width = 15
local agent_width = 6
local branch_width = 40
local updated_width = 9
local column_gap = 2
local column_separator = string.rep(' ', column_gap)

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
            year = tonumber(year) --[[@as integer]],
            month = tonumber(month) --[[@as integer]],
            day = tonumber(day) --[[@as integer]],
            hour = tonumber(hour) --[[@as integer]],
            min = tonumber(min) --[[@as integer]],
            sec = tonumber(sec) --[[@as integer]],
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
    elseif diff < 3600 then
        return math.floor(diff / 60) .. 'm ago'
    elseif diff < 86400 then
        local half_hours = math.floor(diff / 1800)
        if half_hours % 2 == 0 then
            return math.floor(half_hours / 2) .. 'h ago'
        end
        return math.floor(half_hours / 2) .. '.5h ago'
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
    local state_ranges = {}

    if #rows == 0 then
        table.insert(lines, 'No active agents for this Neovim server.')
        return lines, rows_by_line, state_ranges
    end

    local header = table.concat({
        display_width('TITLE', title_width),
        display_width('STATE', state_width),
        display_width('AGENT', agent_width),
        display_width('UPDATED', updated_width),
        display_width('BRANCH', branch_width),
    }, column_separator)

    table.insert(lines, header)

    for _, row in ipairs(rows) do
        local state_value = M.field(row, { 'state', 'status' })
        local title_cell = display_width(M.field(row, { 'title', 'name', 'summary' }), title_width)
        local state_cell = display_width(state_value, state_width)
        local line = table.concat({
            title_cell,
            state_cell,
            display_width(M.field(row, { 'agent', 'agent_type', 'type' }), agent_width),
            display_width(relative_time(M.field(row, { 'updated', 'updated_at', 'updatedAt' })), updated_width),
            display_width(M.field(row, { 'branch', 'git_branch' }), branch_width),
        }, column_separator)

        table.insert(lines, line)
        rows_by_line[#lines] = row
        if state_value ~= '' then
            local state_col = #title_cell + #column_separator
            table.insert(state_ranges, {
                line = #lines,
                col = state_col,
                end_col = state_col + #state_cell,
                state = state_value,
            })
        end
    end

    return lines, rows_by_line, state_ranges
end

return M
