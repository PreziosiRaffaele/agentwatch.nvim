local M = {}

local function normalize_path(path)
    if type(path) ~= 'string' or vim.trim(path) == '' then
        return nil
    end

    local normalized = vim.fn.fnamemodify(path, ':p')
    if normalized ~= '/' then
        normalized = normalized:gsub('/+$', '')
    end
    normalized = vim.uv.fs_realpath(normalized) or normalized
    return normalized
end

local function git_output(folder, args)
    local parts = { 'git', '-C', folder }
    vim.list_extend(parts, args)

    local escaped = vim.tbl_map(vim.fn.shellescape, parts)
    local result = vim.fn.system(table.concat(escaped, ' ') .. ' 2>&1')
    if vim.v.shell_error ~= 0 then
        return nil, vim.trim(result)
    end
    return result, nil
end

function M.repo_root()
    local result = vim.fn.systemlist('git rev-parse --show-toplevel')
    if vim.v.shell_error ~= 0 or not result[1] then
        return nil
    end
    return vim.trim(result[1])
end

function M.branch_slug(branch)
    return vim.trim(branch):gsub('[^A-Za-z0-9._]+', '-')
end

function M.default_path(repo_root, branch, worktree_dir)
    local dir = (worktree_dir and worktree_dir ~= '') and worktree_dir or '.worktrees'
    local base
    if dir:sub(1, 1) == '/' or dir:sub(1, 1) == '~' then
        local name = vim.fn.fnamemodify(repo_root, ':t')
        base = vim.fn.expand(dir) .. '/' .. name
    else
        base = repo_root .. '/' .. dir
    end
    return base .. '/' .. M.branch_slug(branch)
end

function M.add(repo_root, branch, path)
    local check =
        vim.fn.system('git -C ' .. vim.fn.shellescape(repo_root) .. ' branch --list ' .. vim.fn.shellescape(branch))
    local branch_exists = vim.trim(check) ~= ''

    local cmd
    if branch_exists then
        cmd = 'git -C '
            .. vim.fn.shellescape(repo_root)
            .. ' worktree add '
            .. vim.fn.shellescape(path)
            .. ' '
            .. vim.fn.shellescape(branch)
            .. ' 2>&1'
    else
        cmd = 'git -C '
            .. vim.fn.shellescape(repo_root)
            .. ' worktree add -b '
            .. vim.fn.shellescape(branch)
            .. ' '
            .. vim.fn.shellescape(path)
            .. ' 2>&1'
    end

    local result = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
        return vim.trim(result)
    end
    return nil
end

local function registered_worktree_path(folder)
    local path = normalize_path(folder)
    if not path then
        return nil, 'Selected agent has no worktree path'
    end

    local stat = vim.uv.fs_stat(path)
    if not stat then
        return nil, 'Path does not exist: ' .. path
    end
    if stat.type ~= 'directory' then
        return nil, 'Path is not a directory: ' .. path
    end

    local list_output, list_err = git_output(path, { 'worktree', 'list', '--porcelain' })
    if list_err or not list_output then
        return nil, 'git worktree list failed: ' .. (list_err or 'unknown error')
    end

    local main_worktree = nil
    local registered = false
    for line in
        (list_output --[[@as string]]):gmatch('[^\r\n]+')
    do
        local entry = normalize_path(line:match('^worktree (.+)$') or '')
        if entry then
            main_worktree = main_worktree or entry
            if entry == path then
                registered = true
            end
        end
    end

    if not registered then
        return nil, 'Path is not a registered Git worktree: ' .. path
    end

    return path, nil, main_worktree
end

function M.attachable_path(folder)
    return registered_worktree_path(folder)
end

function M.removable_path(folder)
    local path, err, main_worktree = registered_worktree_path(folder)
    if err then
        return nil, err
    end

    if path == main_worktree then
        return nil, 'Refusing to delete the repository main working tree: ' .. path
    end

    return path, nil, main_worktree
end

function M.remove(folder)
    local path, removable_err, main_worktree = M.removable_path(folder)
    if removable_err or not path then
        return nil, removable_err
    end

    local _, remove_err = git_output(path, { 'worktree', 'remove', path })

    if remove_err then
        if main_worktree and not vim.uv.fs_stat(path) then
            -- Git can delete the directory before failing to remove admin files.
            local _, prune_err = git_output(main_worktree, { 'worktree', 'prune' })
            if not prune_err then
                return path, nil
            end

            return nil, remove_err .. '; git worktree prune failed: ' .. prune_err
        end

        return nil, remove_err
    end

    return path, nil
end

return M
