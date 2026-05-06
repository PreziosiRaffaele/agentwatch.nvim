local M = {}

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

return M
