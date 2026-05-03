# agent-watch.nvim

Local Neovim integration for the sibling `agent-watch` CLI.

## Commands

- `:AgentWatch` opens or refreshes a bottom scratch buffer showing agents attached to the current Neovim server.
- `:AgentWatchToggle` toggles the Agent Watch window visibility. When opened, the view refreshes while it is visible.
- `:AgentWatchLaunch <title> [codex|cursor|agent] [args...]` opens a terminal and starts an agent through `agent-watch launch`.
- `:AgentWatchRename [title]` renames the selected agent row. Without a title, it prompts for one.

Titles with spaces must be quoted, for example `:AgentWatchLaunch "Fix parser" codex`.

## Mappings

Inside the `AgentWatch` buffer:

- `<CR>` jumps to the selected agent terminal buffer.
- `r` renames the selected agent.
- `dd` force-deletes the selected agent terminal buffer.
- `q` closes the watch window.

## Setup

```lua
return {
    dir = '~/code/agent-watch-nvim',
    cmd = { 'AgentWatch', 'AgentWatchToggle', 'AgentWatchLaunch', 'AgentWatchRename' },
    opts = {
        cli = vim.fn.expand('~/code/agent-watch/bin/agent-watch.js'),
        default_agent = 'codex',
        height = 10,
        fixed_height = true,
        watch_interval = 1000,
    },
}
```

`height` controls the bottom `:AgentWatch` window height in lines.
`fixed_height` controls whether the watch window keeps a fixed height (`winfixheight`).
