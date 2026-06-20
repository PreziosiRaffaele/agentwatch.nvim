local M = {}

local state = {
    owns_tabline = false,
}

local tabline_expr = "%!v:lua.require'agent-watch.worktree_tabs'.render()"

local function escape_tabline(value)
    return tostring(value or ''):gsub('%%', '%%%%')
end

local function current_tab_buffer(tabpage)
    local win = vim.api.nvim_tabpage_get_win(tabpage)
    return vim.api.nvim_win_get_buf(win)
end

local function buffer_label(bufnr)
    if not bufnr then
        return '[No Name]'
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == '' then
        return '[No Name]'
    end

    return vim.fn.fnamemodify(name, ':t')
end

local function tab_modified(tabpage)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        local bufnr = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
            return true
        end
    end

    return false
end

local function tab_label(tabpage)
    local bufnr = current_tab_buffer(tabpage)
    local label = buffer_label(bufnr)
    local ok, title = pcall(vim.api.nvim_tabpage_get_var, tabpage, 'agent_watch_title')

    if ok and type(title) == 'string' and title ~= '' then
        label = '[' .. title .. '] ' .. label
    end

    if tab_modified(tabpage) then
        label = label .. ' +'
    end

    return label
end

function M.mark_current(row)
    vim.t.agent_watch_title = row.title
end

function M.render()
    local current = vim.api.nvim_get_current_tabpage()
    local parts = {}

    for tabnr, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        local highlight = tabpage == current and '%#TabLineSel#' or '%#TabLine#'
        table.insert(parts, '%' .. tabnr .. 'T' .. highlight .. ' ' .. escape_tabline(tab_label(tabpage)) .. ' ')
    end

    table.insert(parts, '%#TabLineFill#%T')
    return table.concat(parts)
end

function M.setup(opts)
    if opts.worktree_tab_label == false then
        if state.owns_tabline and vim.o.tabline == tabline_expr then
            vim.o.tabline = ''
        end
        state.owns_tabline = false
        return
    end

    if vim.o.tabline ~= '' and vim.o.tabline ~= tabline_expr and not state.owns_tabline then
        return
    end

    vim.o.tabline = tabline_expr
    state.owns_tabline = true
end

return M
