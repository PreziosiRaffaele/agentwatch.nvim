# agent-watch.nvim

Local Neovim integration for the sibling `agent-watch` CLI.

## Commands

- `:AgentWatch` opens a bottom scratch buffer showing agents attached to the current Neovim server. The view refreshes while it is visible.
- `:AgentWatchLaunch <title> [codex|cursor|agent] [args...]` opens a terminal and starts an agent through `agent-watch launch`.

Titles with spaces must be quoted, for example `:AgentWatchLaunch "Fix parser" codex`.

## Mappings

Inside the `AgentWatch` buffer:

- `<CR>` jumps to the selected agent terminal buffer.
- `dd` force-deletes the selected agent terminal buffer.
- `q` closes the watch window.

## Setup

```lua
return {
    dir = '~/code/agent-watch-nvim',
    cmd = { 'AgentWatch', 'AgentWatchLaunch' },
    opts = {
        cli = vim.fn.expand('~/code/agent-watch/bin/agent-watch.js'),
        default_agent = 'codex',
        watch_interval = 1000,
    },
}
```
