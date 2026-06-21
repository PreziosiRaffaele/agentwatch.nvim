# agent-watch.nvim

Track coding agents from Neovim while they work in parallel across separate Git
worktrees.

`agent-watch.nvim` is for reviewing and steering agent work from the editor you
already use for code. It launches agents, records which terminal buffer and
worktree each one belongs to, and shows the agents attached to the current
Neovim session in a live watch window.

This is most useful when you split work across multiple agents: one agent can fix
a bug in one worktree, another can explore a refactor in a second worktree, and a
third can write tests somewhere else. From Neovim, you can jump to any agent's
terminal, open the associated worktree, inspect the files, review the diff, and
keep each task labeled as it evolves.

## Installation

The Neovim plugin depends on the `agent-watch` command-line tool. It provides
the `aw` launcher used to start tracked agents and the local `agent-watchd`
daemon that stores their live state.

The command-line tool runs on [Bun](https://bun.sh/), a JavaScript runtime and
package manager. If you do not already have Bun installed, install it first:

```sh
curl -fsSL https://bun.sh/install | bash
```

On Windows, use PowerShell:

```powershell
powershell -c "irm bun.sh/install.ps1|iex"
```

Then restart your shell and verify that Bun is available:

```sh
bun --version
```

After Bun is installed, install the `agent-watch` CLI:

```sh
bun install -g @preziosiraffaele/agent-watch
```

### Neovim built-in package manager

With Neovim's built-in package manager, add the plugin in your `init.lua`:

```lua
vim.pack.add({
    { src = 'https://github.com/PreziosiRaffaele/agentwatch.nvim' },
})

require('agent-watch').setup()
```

Restart Neovim after adding the plugin.

### lazy.nvim

With lazy.nvim, add a plugin spec like this:

```lua
return {
    'PreziosiRaffaele/agentwatch.nvim',
    event = 'VeryLazy',
}
```

## Workflows

**Watch agents from Neovim**

Run `:AgentWatch` to open a bottom scratch buffer with the agents launched from
the current Neovim session, plus resumable `exited` agents from the same project.
Before the first refresh, the plugin runs `aw daemon ensure` so the local
daemon is available, then caches a successful ensure for the current Neovim
session. The view refreshes while it is visible and filters out agents from
other Neovim sessions, so the list stays focused on the workspace you are
editing.

**Launch an agent without leaving the editor**

Use `:AgentWatchLaunch <title> [agent]` or press `a` in the watch buffer. The
plugin opens a terminal using your configured layout and starts `aw <agent>`
inside it, passing a unique client reference that lets this session recognise
the agent's terminal in the daemon's rows.

**Keep parallel agent tasks separated with worktrees**

Use `:AgentWatchLaunchWorktree <title> [branch] [agent]` to create a Git
worktree and start an agent inside it. Use
`:AgentWatchAttachWorktree <path> [title] [agent]` when the worktree already
exists. This is the main flow for giving each agent an isolated checkout while
keeping all of them visible from one editor. When a linked worktree opens in a
Neovim tab, Agent Watch labels the tab as `[title] fileName` unless you already
use a custom tabline. The repository main working tree keeps normal tab labels.

**Jump back to agent terminals quickly**

Use `:AgentWatchToggleLatest` or the default `<C-\><C-\>` mapping to toggle the
latest agent terminal. From the watch buffer, press `<CR>` on any row to open
that agent's terminal directly.

**Resume agents from a previous Neovim session**

Closing Neovim does not lose your agents: resumable sessions stay tracked by
the daemon as `exited`. Reopen Neovim in the same project (the main repository
or any of its worktrees) and the watch buffer lists them again. Press `<CR>` on
an `exited` row to resume the agent in its original folder, attached to the
current session. Press `dd` on it to delete the record instead.

**Manage agent rows as tasks evolve**

Rename the selected agent with `r` or `:AgentWatchRename [title]`. Open the
selected row's worktree with `o`. Delete an agent with `dd` after confirmation,
or delete a linked Git worktree and its agent with `dw` after confirmation.

## Commands

- `:AgentWatch` opens or refreshes a bottom scratch buffer showing agents launched from the current Neovim session, plus resumable `exited` agents from the same project. The first explicit refresh/open runs `aw daemon ensure`; successful ensure is cached for the current Neovim session.
- `:AgentWatchToggle` toggles the Agent Watch window visibility. When opened, it ensures the daemon if needed, then refreshes while visible.
- `:AgentWatchToggleLatest` toggles the latest agent terminal. It closes the terminal when visible and reopens it when hidden.
- `:AgentWatchLaunch <title> [agent]` opens a terminal and starts `aw <agent>` directly inside it.
- `:AgentWatchLaunchWorktree <title> [branch] [agent]` creates a Git worktree and starts a tracked agent inside it. When `branch` is omitted, it is derived from `title` (lowercased and slugified).
- `:AgentWatchAttachWorktree <path> [title] [agent]` starts a tracked agent inside an existing Git worktree at `<path>`. When `title` is omitted, it is taken from the worktree's current branch name (falling back to the path basename if HEAD is detached).
- `:AgentWatchRename [title]` renames the selected agent row. Without a title, it prompts for one.

Titles with spaces must be quoted, for example `:AgentWatchLaunch "Fix parser" codex`
or `:AgentWatchLaunchWorktree "Fix parser" fix/parser codex`
or `:AgentWatchAttachWorktree .worktrees/fix-parser "Fix parser" codex`.

## Mappings

Inside the `AgentWatch` buffer:

- `<CR>` jumps to the selected agent terminal buffer. On an `exited` row it resumes the agent instead.
- `a` prompts for title/agent and launches a new tracked agent.
- `r` renames the selected agent.
- `o` opens the selected agent's worktree. The default opener labels linked worktree tabs as `[title] fileName`.
- `dd` deletes the selected agent after confirmation.
- `dw` deletes the selected agent's Git worktree and agent record after confirmation. It removes the worktree directory, not the branch.
- `q` closes the watch window.
- `?` toggles the floating help window for the complete watch-buffer keymap.

Global normal-mode mappings:

- `<leader>aw` toggles the Agent Watch window.
- `<C-\><C-\>` toggles the latest agent terminal.

Inside agent terminal buffers, in terminal and normal mode:

- `<C-\><C-\>` toggles the latest agent terminal.

## Configuration

```lua
require('agent-watch').setup({
    cli = 'aw',
    daemon_url = nil,
    default_agent = 'claude',
    available_agents = { 'codex', 'agent', 'claude', 'pi' },
    height = 8,
    fixed_height = true,
    watch_interval = 1000,
    worktree_opener = 'nvim',
    worktree_tab_label = true,
    keymaps = {
        toggle = '<leader>aw',
        toggle_latest = '<C-\\><C-\\>',
    },
    terminal = {
        layout = 'side', -- 'float', 'side', or 'tab'
        side = 'right',
        width = 80, -- side split width in columns
    },
})
```

`height` controls the bottom `:AgentWatch` window height in lines.
`fixed_height` controls whether the watch window keeps a fixed height (`winfixheight`).
`daemon_url` overrides the `agent-watchd` URL. When unset, the plugin reads `~/.agent-watch/daemon.json` and then falls back to `http://127.0.0.1:3847`.
`available_agents` controls which agents can be selected/launched in your space.
Allowed values are: `codex`, `agent`, `claude`, `pi`.
If `available_agents` or `default_agent` are misconfigured, the plugin surfaces an error and falls back to a safe value.
`terminal.layout` controls where launched and selected agent terminals open. Use `float`, `side`, or `tab`.
For `side`, `terminal.side` chooses `right` or `left`, and `terminal.width` controls the split width.
For `float`, `terminal.float_width` and `terminal.float_height` are editor-size fractions from `0` to `1`.
`worktree_opener` controls whether selected worktrees open in Neovim tabs or tmux windows.
`worktree_tab_label` installs the default `[title] fileName` tabline for linked Agent Watch worktree tabs when Neovim's `tabline` option is empty. Set it to `false` if your own tabline handles this.
