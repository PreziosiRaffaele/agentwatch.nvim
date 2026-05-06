# Worktree Launch Spec

Launch a tracked agent inside a fresh Git worktree without leaving Neovim.

`docs/spec.md` remains the canonical product spec.

---

## Goal

One Neovim command creates a Git worktree and launches a tracked agent inside
it. The launched agent must behave like any other `agent-watch.nvim` launch: it
appears in the `AgentWatch` buffer, opens with the configured terminal layout,
toggles via `AgentWatchToggleLatest`, and registers through `aw <agent>`. The
daemon `folder` field is the worktree path — no daemon changes required.

---

## Command and Flow

```vim
:AgentWatchLaunchWorktree <title> <branch> [agent]
```

The command requires title and branch. The agent is optional; when omitted, the
configured `default_agent` is used. The watch buffer binds the same flow to `w`,
prompts for title and branch, and launches the default agent.

Interactive flow:

```text
1. command args: title and branch, or prompt from the `w` mapping
2. command arg: agent      (optional, defaults to default_agent)
3. derive worktree path from branch slug
4. git worktree add
5. launch tracked agent with cwd = worktree path
```

The terminal job runs:

```text
aw <agent> --title <title> --nvim-server <addr> --nvim-bufnr <bufnr>
```

with `cwd = <worktree_path>`, so `aw` registers `folder = process.cwd()`
naturally.

> Note: titles containing spaces must be quoted in the command, or entered
> through the `w` mapping prompt.

---

## Path Default

```text
<repo_parent>/<branch_slug>
```

Slug: trim, then replace any run of characters outside `[A-Za-z0-9._]` with `-`.

Example: repo `/Users/me/code/agent-watch`, branch `fix/parser` →
`/Users/me/code/fix-parser`.

---

## Git Behavior

Run from the resolved repo root (`git rev-parse --show-toplevel`).

```text
git worktree add -b <branch> <path>            # new branch
git worktree add    <path>   <branch>          # fallback if branch exists
```

Failures:

- Not in a Git repo → error, no terminal created.
- `git worktree add` fails (path exists, dirty index, etc.) → surface the Git
  error, do not launch the agent.
- Never delete partial directories from the plugin. Cleanup is the user's job.

---

## Inspecting Worktree Files

Each row in the watch buffer exposes the worktree path. The watch buffer binds:

| Key | Action |
| --- | --- |
| `t` | Open a new tmux window in the same session, `cwd` = worktree path. |

If `$TMUX` is unset, `t` notifies an error instead of running.

---

## Implementation Notes

- Add a small `lua/agent-watch/worktree.lua` for repo-root resolution, slug
  derivation, and `git worktree add`.
- Extend `terminal.launch` to accept an optional `cwd`. Worktree knowledge
  stays out of the terminal module.
- Configurable command name:

  ```lua
  commands = {
      launch_worktree = 'AgentWatchLaunchWorktree',
  }
  ```

---

## Non-Goals

- No automatic worktree or branch cleanup.
- No daemon schema changes.
- No separate worktree rows in the watch buffer.

---

## Verification

1. `:AgentWatchLaunchWorktree "Fix parser" fix/parser codex` from a Git repo → creates
   the worktree at the derived path, opens the agent terminal there.
2. `AgentWatch` shows the launch; `AgentWatchToggleLatest` toggles it.
3. Watch-buffer `t` opens a tmux window in the worktree path.
4. Running outside a Git repo errors and creates no terminal.
