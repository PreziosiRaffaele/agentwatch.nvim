# agent-watch.nvim

`agent-watch.nvim` is the Neovim integration for the `agent-watch` ecosystem.

It displays live agent state from `agent-watchd` and lets the user launch, rename, and navigate to agent terminals without leaving the editor.

---

## Architecture

The plugin communicates with `agent-watchd` using two channels:

- **HTTP API** (direct): agent listing (`GET /agents`) and renaming (`PATCH /launches/:id`) go straight to `agent-watchd`. The daemon URL is resolved from the `daemon_url` plugin option when set, otherwise from the healthy `~/.agent-watch/daemon.json` state file written by `agent-watchd`, and finally from the default `http://127.0.0.1:3847`. 
- **`aw` CLI**: launching agents. `aw <agent>` is the only operation routed through the CLI — it handles daemon startup and launch registration.

---

## Components

**Watch buffer**

- A bottom scratch buffer (`botright split`) showing agents attached to the current Neovim server.
- Filtered by `nvim_server` by calling `GET /agents?nvim_server=<current-server>`. The plugin uses the existing `vim.v.servername` when Neovim already has a server address; otherwise it starts one with `vim.fn.serverstart()` and uses the returned address. The plugin also keeps a local exact `row.nvim_server == current_server` check after parsing the response as a compatibility guard.
- Rows with an invalid terminal buffer are excluded from the view.
- Updated by polling the filtered daemon endpoint at `watch_interval` ms while the window is visible. Polling stops when the window closes.

**Launch terminal**

- Each agent is launched in a hidden terminal buffer opened with the configured terminal layout.
- Supported terminal layouts are `float`, `side`, and `tab`. The default is `float`.
- `aw <agent>` is started directly as the terminal job, passing `--nvim-server` and `--nvim-bufnr` so `agent-watchd` can link the launch back to this Neovim session.

---

## Neovim Server

The plugin calls `vim.fn.serverstart()` to ensure a server address exists and passes it to `aw` at launch time. This address is stored in the `nvim_server` field of the agent record and used to filter `GET /agents` results.

---

## Commands

| Command | Description |
| --- | --- |
| `AgentWatch` | Open or refresh the watch buffer. |
| `AgentWatchToggle` | Toggle the watch window. Stopping the watch process on close. |
| `AgentWatchLaunch <title> [agent] [args...]` | Open a terminal and start a tracked agent. |
| `AgentWatchRename [title]` | Rename the selected agent. Prompts if no title is given. |

---

## Buffer Keymaps

Inside the `AgentWatch` buffer:

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected agent terminal with the configured terminal layout. |
| `a` | Prompt for title and agent type, then launch. |
| `r` | Rename the selected agent. |
| `dd` | Force-delete the selected agent terminal buffer. |
| `q` | Close the watch window and stop the watch process. |

---

## Configuration

```lua
require('agent-watch').setup({
    cli            = 'aw',                        -- path to the aw CLI
    daemon_url     = nil,                         -- optional agent-watchd base URL override
    height         = 10,            -- watch window height in lines
    fixed_height   = true,          -- winfixheight on the watch window
    watch_interval = 1000,          -- daemon polling interval in ms
    default_agent  = 'codex',       -- pre-selected agent in the launch prompt
    available_agents = { 'codex', 'agent', 'claude' }, -- agents shown in the picker
    terminal = {
        layout       = 'float',      -- 'float', 'side', or 'tab'
        side         = 'right',      -- side split direction: 'right' or 'left'
        width        = 80,           -- side split width in columns
        float_width  = 0.9,          -- float width as editor fraction
        float_height = 0.85,         -- float height as editor fraction
    },
    commands = {
        watch  = 'AgentWatch',
        toggle = 'AgentWatchToggle',
        launch = 'AgentWatchLaunch',
        rename = 'AgentWatchRename',
    },
})
```

`available_agents` must be a non-empty subset of `{ 'codex', 'agent', 'claude' }`. `default_agent` must be in `available_agents`. Both are validated at setup time; misconfigurations surface an error and fall back to defaults.

`terminal.layout` must be one of `float`, `side`, or `tab`. Invalid terminal layout settings surface an error and fall back to defaults.

---

## Data Flow

```text
AgentWatch / AgentWatchToggle
  → ensures Neovim server is running
  → resolves daemon URL from daemon_url, ~/.agent-watch/daemon.json, or default localhost
  → polls: GET <daemon_url>/agents?nvim_server=<addr>

AgentWatchLaunch <title> [agent]
  → ensures Neovim server is running
  → creates a hidden terminal buffer
  → opens it with the configured terminal layout
  → starts terminal job: aw <agent> --title <title> --nvim-server <addr> --nvim-bufnr <bufnr>

AgentWatchRename <id> <title>
  → resolves daemon URL from daemon_url, ~/.agent-watch/daemon.json, or default localhost
  → PATCH <daemon_url>/launches/<id>  body: { "title": "<title>" }
  → refreshes the watch buffer on success
```
