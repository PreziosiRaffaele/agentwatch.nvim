local M = {}

local state = {
    owns_tabline = false,
}

local tabline_expr = "%!v:lua.require'agent-watch.worktree_tabs'.render()"

local function escape_tabline(value)
    return tostring(value or ''):gsub('%%', '%%%%')
end

local function current_tab_buffer(tabnr)
    local buffers = vim.fn.tabpagebuflist(tabnr)
    local winnr = vim.fn.tabpagewinnr(tabnr)
    return buffers[winnr]
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

local function tab_modified(tabnr)
    for _, bufnr in ipairs(vim.fn.tabpagebuflist(tabnr)) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified then
            return true
        end
    end

    return false
end

local function tab_label(tabnr)
    local bufnr = current_tab_buffer(tabnr)
    local label = buffer_label(bufnr)
    local title = vim.t[tabnr].agent_watch_title

    if type(title) == 'string' and title ~= '' then
        label = '[' .. title .. '] ' .. label
    end

    if tab_modified(tabnr) then
        label = label .. ' +'
    end

    return label
end

function M.mark_current(row)
    vim.t.agent_watch_title = row.title
end

function M.render()
    local current = vim.fn.tabpagenr()
    local last = vim.fn.tabpagenr('$')
    local parts = {}

    for tabnr = 1, last do
        local highlight = tabnr == current and '%#TabLineSel#' or '%#TabLine#'
        table.insert(parts, '%' .. tabnr .. 'T' .. highlight .. ' ' .. escape_tabline(tab_label(tabnr)) .. ' ')
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
