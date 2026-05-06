local M = {}

local state = {
    opts = nil,
    buf = nil,
    win = nil,
    rows_by_line = {},
    actions = {},
}

local statusline = 'Agent Watch  <CR>: open  a: add  w: worktree  r: rename  t: open worktree  dd: delete'

local function valid_win(win)
    return win and vim.api.nvim_win_is_valid(win)
end

local function visible_window()
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        return nil
    end

    local wins = vim.fn.win_findbuf(state.buf)
    if #wins > 0 and vim.api.nvim_win_is_valid(wins[1]) then
        state.win = wins[1]
        return state.win
    end

    return nil
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
        { buffer = state.buf, silent = true, desc = 'Jump to agent terminal' }
    )
    vim.keymap.set('n', 'a', state.actions.launch, { buffer = state.buf, silent = true, desc = 'Add agent' })
    vim.keymap.set(
        'n',
        'w',
        state.actions.launch_worktree,
        { buffer = state.buf, silent = true, desc = 'Launch worktree agent' }
    )
    vim.keymap.set('n', 'r', state.actions.rename, { buffer = state.buf, silent = true, desc = 'Rename agent' })
    vim.keymap.set(
        'n',
        'dd',
        state.actions.delete,
        { buffer = state.buf, silent = true, desc = 'Delete agent terminal' }
    )
    vim.keymap.set(
        'n',
        't',
        state.actions.open_worktree,
        { buffer = state.buf, silent = true, desc = 'Open selected worktree' }
    )
    vim.keymap.set('n', 'q', state.actions.close, { buffer = state.buf, silent = true, desc = 'Close agent watch' })
end

function M.setup(opts, actions)
    state.opts = opts
    state.actions = actions
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
    local win = visible_window()
    if win then
        vim.api.nvim_win_close(win, false)
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
