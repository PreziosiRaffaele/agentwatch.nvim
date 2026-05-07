# agent-watch.nvim

Local Neovim integration for the sibling `agent-watch` CLI.

## Commands

- `:AgentWatch` opens or refreshes a bottom scratch buffer showing agents attached to the current Neovim server.
- `:AgentWatchToggle` toggles the Agent Watch window visibility. When opened, the view refreshes while it is visible.
- `:AgentWatchToggleLatest` toggles the latest agent terminal. It closes the terminal when visible and reopens it when hidden.
- `:AgentWatchLaunch <title> [agent]` opens a terminal and starts `aw <agent>` directly inside it.
- `:AgentWatchLaunchWorktree <title> <branch> [agent]` creates a Git worktree and starts a tracked agent inside it.
- `:AgentWatchAttachWorktree <title> <path> [agent]` starts a tracked agent inside an existing Git worktree at `<path>`.
- `:AgentWatchRename [title]` renames the selected agent row. Without a title, it prompts for one.

Titles with spaces must be quoted, for example `:AgentWatchLaunch "Fix parser" codex`
or `:AgentWatchLaunchWorktree "Fix parser" fix/parser codex`
or `:AgentWatchAttachWorktree "Fix parser" .worktrees/fix-parser codex`.

## Mappings

Inside the `AgentWatch` buffer:

- `<CR>` jumps to the selected agent terminal buffer.
- `a` prompts for title/agent and launches a new tracked agent.
- `w` prompts for title/branch and launches the default agent in a Git worktree.
- `r` renames the selected agent.
- `t` opens the selected agent's worktree. The current opener is tmux, using the agent title as the window name.
- `dd` force-deletes the selected agent terminal buffer.
- `dw` deletes the selected agent's Git worktree after confirmation. It removes the worktree directory, not the branch.
- `q` closes the watch window.
- `?` toggles the floating help window for the complete watch-buffer keymap.

Global normal-mode mappings:

- `<C-\><C-\>` toggles the latest agent terminal.

Inside agent terminal buffers, in terminal and normal mode:

- `<C-\><C-\>` toggles the latest agent terminal.

## Setup

```lua
return {
    dir = '~/code/agent-watch-nvim',
    cmd = { 'AgentWatch', 'AgentWatchToggle', 'AgentWatchToggleLatest', 'AgentWatchLaunch', 'AgentWatchLaunchWorktree', 'AgentWatchAttachWorktree', 'AgentWatchRename' },
    opts = {
        cli = 'aw',
        daemon_url = nil,
        default_agent = 'codex',
        available_agents = { 'codex', 'agent', 'claude' },
        height = 8,
        fixed_height = true,
        watch_interval = 1000,
        keymaps = {
            toggle_latest = '<C-\\><C-\\>',
        },
        terminal = {
            layout = 'float', -- 'float', 'side', or 'tab'
            side = 'right',
            width = 80,
            float_width = 0.9,
            float_height = 0.85,
        },
    },
}
```

`height` controls the bottom `:AgentWatch` window height in lines.
`fixed_height` controls whether the watch window keeps a fixed height (`winfixheight`).
`daemon_url` overrides the `agent-watchd` URL. When unset, the plugin reads `~/.agent-watch/daemon.json` and then falls back to `http://127.0.0.1:3847`.
`available_agents` controls which agents can be selected/launched in your space.
Allowed values are: `codex`, `agent`, `claude`.
If `available_agents` or `default_agent` are misconfigured, the plugin surfaces an error and falls back to a safe value.
`terminal.layout` controls where launched and selected agent terminals open. Use `float`, `side`, or `tab`.
For `side`, `terminal.side` chooses `right` or `left`, and `terminal.width` controls the split width.
For `float`, `terminal.float_width` and `terminal.float_height` are editor-size fractions from `0` to `1`.

## Code quality

Format Lua files with Stylua:

```sh
stylua .
```

Verify formatting (for CI/pre-commit):

```sh
stylua --check .
```
