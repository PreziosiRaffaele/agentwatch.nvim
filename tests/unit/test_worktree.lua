local worktree = require('agent-watch.worktree')
local expect = MiniTest.expect
local eq = expect.equality

local T = MiniTest.new_set()

T['branch_slug()'] = MiniTest.new_set()

T['branch_slug()']['replaces runs of unsafe characters with a single dash'] = function()
    eq(worktree.branch_slug('feature/new thing'), 'feature-new-thing')
    eq(worktree.branch_slug('a@@@b'), 'a-b')
    eq(worktree.branch_slug('keep.dot_underscore-1'), 'keep.dot_underscore-1')
end

T['title_to_branch()'] = MiniTest.new_set()

T['title_to_branch()']['lowercases and slugifies'] = function()
    eq(worktree.title_to_branch('Fix Login Bug'), 'fix-login-bug')
    eq(worktree.title_to_branch('Add OAuth!!!'), 'add-oauth')
end

T['title_to_branch()']['trims leading and trailing dashes'] = function()
    eq(worktree.title_to_branch('  ***hello***  '), 'hello')
    eq(worktree.title_to_branch('!!!'), '')
end

T['default_path()'] = MiniTest.new_set()

T['default_path()']['nests a relative worktree dir under the repo root'] = function()
    eq(worktree.default_path('/repo', 'fix-login', '.worktrees'), '/repo/.worktrees/fix-login')
    -- falls back to .worktrees when no dir is given
    eq(worktree.default_path('/repo', 'fix-login', nil), '/repo/.worktrees/fix-login')
end

T['default_path()']['uses the repo basename under an absolute worktree dir'] = function()
    eq(worktree.default_path('/home/me/repo', 'feature', '/tmp/worktrees'), '/tmp/worktrees/repo/feature')
end

return T
