# Worktree Delete Spec

Add an explicit watch-buffer action to delete the Git worktree directory
associated with the selected agent.

`docs/spec.md` remains the canonical product spec. This file describes the
feature modification before it is folded into the canonical spec.

---

## Problem

`dd` in the watch buffer force-deletes the selected agent terminal buffer. For
agents launched with `AgentWatchLaunchWorktree`, that removes the visible agent
from Neovim but leaves the Git worktree directory on disk.

This is correct for a buffer-only delete, but it makes worktree launches
accumulate directories under the repository parent. Users need an explicit way
to remove the worktree directory when the selected agent was launched from one.

---

## Behavior

Keep `dd` as buffer-only delete. Add a separate worktree cleanup action:

| Key | Action |
| --- | --- |
| `dw` | Delete the selected agent's Git worktree after confirmation. |

The action removes the Git worktree directory only. It does not delete the
branch.

---

## Flow

```text
1. read selected watch-buffer row
2. get row.folder
3. verify folder is non-empty and exists
4. verify folder is a registered Git worktree
5. verify folder is not the repository's main working tree
6. prompt for confirmation with the absolute worktree path
7. run: git -C <folder> worktree remove <folder>
8. on success, force-delete the selected agent terminal buffer if still valid
9. refresh the watch buffer
```

The confirmation prompt must include the absolute path, for example:

```text
Delete worktree /Users/me/code/fix-parser? [y/N]
```

Default answer is no. Cancelling the prompt removes nothing.

---

## Git Safety Rules

Use Git as the source of truth for removal:

```text
git -C <folder> rev-parse --show-toplevel
git -C <folder> worktree list --porcelain
git -C <folder> worktree remove <folder>
```

The plugin must not remove the directory when:

- `folder` is empty.
- `folder` does not exist.
- `folder` is not inside a Git worktree.
- `folder` is the repository's main working tree.
- `git worktree remove` fails because the worktree has modified, staged, or
  untracked files.

The failure message should include Git's stderr/stdout so the user can decide
whether to clean the worktree manually.

---

## Documentation Updates

Update `docs/spec.md`:

- Add `dw` to watch-buffer mappings.
- Add the worktree deletion data flow.
- Replace the `docs/worktree-launch.md` non-goal that says cleanup is entirely
  the user's job with a pointer to this supported cleanup flow.

Update `README.md`:

- Add the `dw` mapping.
- Keep the warning concise: cleanup removes the Git worktree directory, not the
  branch.

---

## Verification

1. Select a worktree-launched agent, run `dw`, confirm yes. The Git worktree is
   removed, the terminal buffer is deleted, and the watch buffer refreshes.
2. Select a worktree with modified or untracked files, run `dw`, confirm yes.
   Git refuses removal, the terminal buffer remains, and the worktree directory
   remains.
3. Select a normal `AgentWatchLaunch` agent from the main repository, run `dw`.
   The plugin refuses because the folder is not a removable linked worktree.
4. Select a row with a stale or missing folder, run `dw`. The plugin reports the
   problem and does not delete the terminal buffer.
5. Cancel the confirmation prompt. Nothing is removed and the watch buffer does
   not refresh.
