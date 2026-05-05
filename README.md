# agent-watch.nvim

Local Neovim integration for the sibling `agent-watch` CLI.

## Commands

- `:AgentWatch` opens or refreshes a bottom scratch buffer showing agents attached to the current Neovim server.
- `:AgentWatchToggle` toggles the Agent Watch window visibility. When opened, the view refreshes while it is visible.
- `:AgentWatchLaunch <title> [agent] [args...]` opens a terminal and starts an agent through `aw <agent>`.
- `:AgentWatchRename [title]` renames the selected agent row. Without a title, it prompts for one.

Titles with spaces must be quoted, for example `:AgentWatchLaunch "Fix parser" codex`.

## Mappings

Inside the `AgentWatch` buffer:

- `<CR>` jumps to the selected agent terminal buffer.
- `a` prompts for title/agent and launches a new tracked agent.
- `r` renames the selected agent.
- `dd` force-deletes the selected agent terminal buffer.
- `q` closes the watch window.

## Setup

```lua
return {
    dir = '~/code/agent-watch-nvim',
    cmd = { 'AgentWatch', 'AgentWatchToggle', 'AgentWatchLaunch', 'AgentWatchRename' },
    opts = {
        cli = 'aw',
        daemon_url = nil,
        default_agent = 'codex',
        available_agents = { 'codex', 'agent', 'claude' },
        height = 10,
        fixed_height = true,
        watch_interval = 1000,
    },
}
```

`height` controls the bottom `:AgentWatch` window height in lines.
`fixed_height` controls whether the watch window keeps a fixed height (`winfixheight`).
`daemon_url` overrides the `agent-watchd` URL. When unset, the plugin reads `~/.agent-watch/daemon.json` and then falls back to `http://127.0.0.1:3847`.
`available_agents` controls which agents can be selected/launched in your space.
Allowed values are: `codex`, `agent`, `claude`.
If `available_agents` or `default_agent` are misconfigured, the plugin surfaces an error and falls back to a safe value.

## Code quality

Format Lua files with Stylua:

```sh
stylua .
```

Verify formatting (for CI/pre-commit):

```sh
stylua --check .
```
