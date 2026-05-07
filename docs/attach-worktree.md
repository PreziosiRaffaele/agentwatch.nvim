# Spec: Attach to existing worktree

## Summary

Add a command that starts a tracked agent inside an **already-existing** Git worktree, complementing `AgentWatchLaunchWorktree` (which creates a worktree). The new command does no `git worktree add`; it only validates the path and launches the agent with that path as the terminal cwd.

## Motivation

Today, attaching to an existing worktree requires either calling `M.launch` from Lua or `:tcd`-ing first. Neither is discoverable from `:help`/`:command`. Worktrees are routinely created outside the editor (CLI, other tools, prior sessions), so this is the common path, not the edge case.

## Command

| Command | Description |
| --- | --- |
| `AgentWatchAttachWorktree <title> <path> [agent]` | Start a tracked agent inside an existing Git worktree at `<path>`. |

- `<title>` — required; same semantics as `AgentWatchLaunch`. Quote if it contains spaces.
- `<path>` — required; the worktree directory. Absolute, relative, or `~`-prefixed. Must resolve to a directory that is a registered linked or main Git worktree.
- `[agent]` — optional; falls back to `default_agent`. Must be in `available_agents`.

Examples:

```vim
:AgentWatchAttachWorktree "Fix parser" .worktrees/fix-parser codex
:AgentWatchAttachWorktree "Main repo" ~/code/agent-watch-nvim
```

## Validation

The command rejects, with a `notify(..., ERROR)`, any of:

1. Argument count not in `{2, 3}`, or `<title>`/`<path>` empty after trim.
2. `agent` not in `available_agents`.
3. `<path>` does not exist or is not a directory.
4. `<path>` is not a registered Git worktree (linked or main) according to `git -C <path> worktree list --porcelain`.

Unlike `worktree.removable_path`, the **main** working tree IS allowed — attaching an agent to the main repo is a legitimate use case (only deletion needs to refuse it).

## Data Flow

```text
AgentWatchAttachWorktree <title> <path> [agent]
  → expands ~ and resolves <path> to an absolute, real path
  → verifies the path exists and is a directory
  → runs: git -C <path> worktree list --porcelain
  → confirms <path> matches a registered worktree entry (linked or main)
  → uses the provided agent, or default_agent when omitted
  → ensures Neovim server is running
  → creates a hidden terminal buffer with cwd set to <path>
  → opens it with the configured terminal layout
  → starts terminal job: aw <agent> --title <title> --nvim-server <addr> --nvim-bufnr <bufnr>
```

No `git worktree add` is invoked. No branch creation, no directory creation.

## Tab Completion

- Position 2 (`<path>`): use Vim's `dir` completion (`getcompletion(arg_lead, 'dir')`).
- Position 3 (`[agent]`): same prefix filter against `available_agents` as `AgentWatchLaunchWorktree`.

## Module Boundaries

- `lua/agent-watch/worktree.lua` gains one exported function:
  - `M.attachable_path(folder) -> path | nil, err` — same shape as `removable_path`, but accepts the main worktree. Implementation factors out the shared "normalize → stat → registered?" steps; `removable_path` keeps its main-worktree refusal on top of the shared core.
- `lua/agent-watch/init.lua` gains:
  - `M.attach_worktree(args)` — parses args, calls `worktree.attachable_path`, then `M.launch({title, agent}, path)`.
  - User command registration `commands.attach_worktree`.
  - Completer for `<path>` + `[agent]`.

No new modules. No changes to `daemon.lua`, `terminal.lua`, `watcher.lua`, `watch_window.lua`.

## Configuration

Add to `commands`:

```lua
commands = {
    -- ...existing entries...
    attach_worktree = 'AgentWatchAttachWorktree',
}
```

No new top-level options. No changes to `available_agents`, `default_agent`, terminal layout, or keymaps.

## Watch-buffer Keymap

**Not added in v1.** A row-targeted variant would duplicate `<CR>` (which already opens the agent terminal of an already-tracked row) and the typical use case is attaching to a worktree the watch buffer doesn't yet know about. Revisit if usage shows otherwise.

## Errors and Notifications

All errors go through `notify(..., vim.log.levels.ERROR)`. Error messages are exact strings, matching the conventions of existing commands:

- `Usage: AgentWatchAttachWorktree <title> <path> [agent]`
- `Unknown agent "<agent>". Use one of: <list>`
- `Path does not exist: <path>`
- `Path is not a directory: <path>`
- `Path is not a registered Git worktree: <path>`
- `git worktree list failed: <stderr>` (when the git invocation itself errors)

On success, no notification — the new terminal opening is the feedback.

## Compatibility

Per `AGENTS.md`, this is a beta project with no backward-compat requirement. The change is purely additive: a new command, a new module function, and a new config key. Existing commands and behavior are unchanged.

## Out of Scope

- Auto-detect-then-create (one command that creates if missing, attaches if present). Keeping create vs. attach as separate verbs avoids surprising side effects.
- Branch validation against the worktree's checked-out HEAD. The agent doesn't care which branch is checked out; the user picked the path.
- Multi-instance prevention (refusing to launch a second agent in the same worktree). The CLI/daemon already permit this; the editor shouldn't second-guess.
- Watch-buffer mapping. See above.

## Test Plan

Manual, since the project has no test runner yet.

1. `:AgentWatchAttachWorktree "T1" .worktrees/attach-to-worktree codex` from the repo main worktree → terminal opens with cwd at the linked worktree.
2. Same command with `~/code/agent-watch-nvim` (main worktree) → succeeds.
3. Path that exists but isn't a worktree (e.g. `/tmp`) → error "Path is not a registered Git worktree".
4. Nonexistent path → error "Path does not exist".
5. Missing `<path>` arg → usage error.
6. Unknown agent → unknown-agent error.
7. Tab completion: `:AgentWatchAttachWorktree foo <Tab>` lists directories; `:AgentWatchAttachWorktree foo .worktrees/x <Tab>` lists configured agents.
