local highlights = require('agent-watch.highlights')

local M = {}

local namespace = vim.api.nvim_create_namespace('agent-watch-state')

local state = {
    opts = nil,
    buf = nil,
    win = nil,
    help_buf = nil,
    help_win = nil,
    rows_by_line = {},
    actions = {},
}

local statusline = 'Agent Watch  <CR> open  a add  r rename  ? help  q close'

local help_lines = {
    'Agent Watch',
    '',
    '<CR>  Open selected agent terminal (resume when exited)',
    'a     Launch agent',
    'r     Rename selected agent',
    'o     Open selected worktree',
    'dd    Delete selected agent (discard when exited)',
    'dw    Delete selected worktree and agent; discards an exited record',
    'q     Close Agent Watch',
    '?     Close this help',
}

local function valid_win(win)
    return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
    return buf and vim.api.nvim_buf_is_valid(buf)
end

local function visible_window()
    if not valid_buf(state.buf) then
        return nil
    end

    local wins = vim.fn.win_findbuf(state.buf)
    if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
        state.win = wins[1]
        return state.win
    end

    return nil
end

local function visible_help_window()
    if valid_win(state.help_win) then
        return state.help_win
    end

    state.help_win = nil
    return nil
end

local function close_help()
    local win = visible_help_window()
    local buf = state.help_buf

    if win then
        vim.api.nvim_win_close(win, false)
    end

    if valid_buf(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
    end

    state.help_win = nil
    state.help_buf = nil
end

local function padded_help_lines()
    local lines = { '' }
    for _, line in ipairs(help_lines) do
        table.insert(lines, '  ' .. line)
    end
    table.insert(lines, '')
    return lines
end

local function max_line_width(lines)
    local width = 1
    for _, line in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(line))
    end
    return width
end

local function help_window_config(lines)
    local columns = vim.o.columns
    local rows = vim.o.lines - vim.o.cmdheight
    local width = math.min(max_line_width(lines) + 2, math.max(columns - 4, 1))
    local height = math.min(#lines, math.max(rows - 4, 1))

    return {
        relative = 'editor',
        width = width,
        height = height,
        col = math.max(math.floor((columns - width) / 2), 0),
        row = math.max(math.floor((rows - height) / 2), 0),
        style = 'minimal',
        border = 'single',
    }
end

local function set_help_keymaps(buf)
    for _, lhs in ipairs({ '?', 'q', '<Esc>' }) do
        vim.keymap.set('n', lhs, close_help, { buffer = buf, silent = true, desc = 'Close Agent Watch help' })
    end
end

local function open_help()
    if visible_help_window() then
        return
    end

    local lines = padded_help_lines()
    local buf = vim.api.nvim_create_buf(false, true)
    state.help_buf = buf
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'agent-watch-help'
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    set_help_keymaps(buf)

    local config = help_window_config(lines)
    local ok, win = pcall(vim.api.nvim_open_win, buf, true, config)
    if not ok then
        config.border = nil
        win = vim.api.nvim_open_win(buf, true, config)
    end

    state.help_win = win
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = false
end

local function toggle_help()
    if visible_help_window() then
        close_help()
        return
    end

    open_help()
end

local function set_window_options(win)
    if valid_win(win) then
        vim.wo[win].statusline = statusline
        vim.wo[win].wrap = false
        vim.wo[win].winfixheight = state.opts.fixed_height
    end
end

local function create_buffer()
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = 'nofile'
    vim.bo[state.buf].bufhidden = 'hide'
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = 'agent-watch'
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].readonly = true

    vim.keymap.set(
        'n',
        '<CR>',
        state.actions.jump,
        { buffer = state.buf, silent = true, desc = 'Open or resume agent terminal' }
    )
    vim.keymap.set('n', 'a', state.actions.launch, { buffer = state.buf, silent = true, desc = 'Add agent' })
    vim.keymap.set('n', 'r', state.actions.rename, { buffer = state.buf, silent = true, desc = 'Rename agent' })
    vim.keymap.set('n', 'dd', state.actions.delete, { buffer = state.buf, silent = true, desc = 'Delete agent' })
    vim.keymap.set(
        'n',
        'dw',
        state.actions.delete_worktree,
        { buffer = state.buf, silent = true, desc = 'Delete agent worktree' }
    )
    vim.keymap.set(
        'n',
        'o',
        state.actions.open_worktree,
        { buffer = state.buf, silent = true, desc = 'Open selected worktree' }
    )
    vim.keymap.set('n', '?', toggle_help, { buffer = state.buf, silent = true, desc = 'Show Agent Watch help' })
    vim.keymap.set('n', 'q', state.actions.close, { buffer = state.buf, silent = true, desc = 'Close agent watch' })
end

function M.setup(opts, actions)
    state.opts = opts
    state.actions = actions
    close_help()
end

function M.visible()
    return visible_window() ~= nil
end

function M.open()
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        local existing = visible_window()
        if existing then
            vim.api.nvim_win_set_height(existing, state.opts.height)
            set_window_options(existing)
            return state.buf, state.win
        end
    else
        create_buffer()
    end

    vim.cmd('botright ' .. state.opts.height .. 'split')
    state.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.win, state.buf)
    vim.api.nvim_win_set_height(state.win, state.opts.height)
    set_window_options(state.win)
    return state.buf, state.win
end

function M.close()
    close_help()
    local win = visible_window()
    if win then
        vim.api.nvim_win_close(win, false)
    end
end

local function apply_state_ranges(buf, ranges)
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

    for _, range in ipairs(ranges or {}) do
        local group = highlights.state_group(range.state)
        if group then
            vim.api.nvim_buf_set_extmark(buf, namespace, range.line - 1, range.col, {
                end_col = range.end_col,
                hl_group = group,
            })
        end
    end
end

function M.set_lines(lines, rows_by_line, opts)
    opts = opts or {}

    local buf
    local win
    if opts.open == false then
        win = visible_window()
        if not win then
            return false
        end
        buf = state.buf
    else
        buf, win = M.open()
    end

    rows_by_line = rows_by_line or {}

    local cursor_line = 1
    local cursor_col = 0
    if valid_win(win) then
        local cursor = vim.api.nvim_win_get_cursor(win)
        cursor_line = cursor[1]
        cursor_col = cursor[2]
    end

    vim.bo[buf].modifiable = true
    vim.bo[buf].readonly = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    apply_state_ranges(buf, opts.state_ranges)

    if valid_win(win) then
        if not rows_by_line[cursor_line] then
            for line in pairs(rows_by_line) do
                if line < cursor_line or not rows_by_line[cursor_line] then
                    cursor_line = line
                end
            end
        end

        local target_line = math.min(cursor_line, #lines)
        local max_col = #(lines[target_line] or '')
        vim.api.nvim_win_set_cursor(win, { target_line, math.min(cursor_col, max_col) })
    end

    state.rows_by_line = rows_by_line
    return true
end

function M.selected_row()
    if vim.api.nvim_get_current_buf() ~= state.buf then
        return nil
    end

    local line = vim.api.nvim_win_get_cursor(0)[1]
    return state.rows_by_line[line]
end

return M
