# agent-watch.nvim

`agent-watch.nvim` is the Neovim integration for the `agent-watch` ecosystem.

It displays live agent state from `agent-watchd` and lets the user launch, rename, and navigate to agent terminals without leaving the editor.

---

## Architecture

The plugin communicates with `agent-watchd` using two channels:

- **HTTP API** (direct): agent listing (`GET /agents`, unfiltered — all row filtering happens client-side), renaming (`PATCH /launches/:id`), and deleting records (`DELETE /launches/:id`) go straight to `agent-watchd`. The daemon URL is resolved from the `daemon_url` plugin option when set, otherwise from the healthy `~/.agent-watch/daemon.json` state file written by `agent-watchd`, and finally from the default `http://127.0.0.1:3847`. 
- **`aw` CLI**: launching and resuming agents. `aw <agent>` and `aw resume <id>` are the only operations routed through the CLI — they handle daemon startup and launch registration.

---

## Components

**Watch buffer**

- A bottom scratch buffer (`botright split`) showing agents attached to the current Neovim server, plus resumable `exited` agents from the same project.
- Each poll performs a single unfiltered `GET /agents` request and partitions the rows client-side. A row is kept when either:
  - its `nvim_server` matches the current server and its terminal buffer is valid (owned rows); or
  - its `state` is `exited` and its `project_root` matches the local project root (adoptable rows) — kept regardless of `nvim_server` and without a terminal-buffer validity check, since the buffer belongs to a dead session. Their stale `nvim_terminal_bufnr` is cleared when kept, so buffer actions can never mistake it for a local buffer.
- The plugin uses the existing `vim.v.servername` when Neovim already has a server address; otherwise it starts one with `vim.fn.serverstart()` and uses the returned address.
- The project root is the same project identity `agent-watchd` stores in `project_root`: inside a Git repository, the repository main working tree (parent directory of `git rev-parse --path-format=absolute --git-common-dir`, so linked worktrees group with their repository); outside a Git repository, the cwd itself. It is resolved once per watch session, like the server address.
- Kept rows are sorted by launch ID ascending.
- Visible columns are `TITLE`, `STATE`, `AGENT`, `UPDATED`, and `BRANCH`.
- The `STATE` column is highlighted with plugin-owned highlight groups linked to standard Neovim groups, so colors come from the user's active colorscheme.
- Updated by polling the filtered daemon endpoint at `watch_interval` ms while the window is visible. Polling stops when the window closes.

**Launch terminal**

- Each agent is launched in a hidden terminal buffer opened with the configured terminal layout.
- Supported terminal layouts are `float`, `side`, and `tab`. The default is `side`.
- `aw <agent>` is started directly as the terminal job, passing `--nvim-server` and `--nvim-bufnr` so `agent-watchd` can link the launch back to this Neovim session.
- The latest-agent toggle prefers the last terminal launched or opened in the current Neovim session. If that buffer is missing or invalid, it fetches the current daemon rows for this Neovim server and opens the valid row with the highest launch ID.

**Worktree tabs**

- The default `nvim` worktree opener creates a new tab and switches the tab-local working directory to the selected worktree.
- For linked Git worktrees, the opener stores tab-local Agent Watch metadata. The repository main working tree keeps normal tab labels.
- When `worktree_tab_label` is enabled, `setup()` loads the worktree-tab module after configuration validation. If Neovim has no custom tabline configured, Agent Watch installs a tabline that labels linked worktree tabs as `[branch] fileName`.
- Custom tabline plugins are not overwritten. They can read `vim.t.agent_watch_branch`, `vim.t.agent_watch_title`, and `vim.t.agent_watch_worktree` for linked Agent Watch worktree tabs.

---

## Neovim Server

The plugin calls `vim.fn.serverstart()` to ensure a server address exists and passes it to `aw` at launch time. This address is stored in the `nvim_server` field of the agent record and used to filter `GET /agents` results.

---

## Commands

| Command | Description |
| --- | --- |
| `AgentWatch` | Open or refresh the watch buffer. |
| `AgentWatchToggle` | Toggle the watch window. Stopping the watch process on close. |
| `AgentWatchToggleLatest` | Toggle the latest agent terminal. Closes it when visible, opens it when hidden. |
| `AgentWatchLaunch <title> [agent]` | Open a terminal and start a tracked agent. |
| `AgentWatchLaunchWorktree <title> [branch] [agent]` | Create a Git worktree, then open a terminal and start a tracked agent in it. `branch` is derived from `title` when omitted. |
| `AgentWatchAttachWorktree <path> [title] [agent]` | Open a terminal and start a tracked agent inside an existing Git worktree at `<path>`. `title` is derived from the worktree's current branch name (or the path basename when HEAD is detached) when omitted. |
| `AgentWatchRename [title]` | Rename the selected agent. Prompts if no title is given. |

---

## Buffer Keymaps

Inside the `AgentWatch` buffer:

| Key | Action |
| --- | --- |
| `<CR>` | Open the selected agent terminal with the configured terminal layout. On an `exited` row, resume the agent instead. |
| `a` | Prompt for title and agent type, then launch. |
| `r` | Rename the selected agent. |
| `o` | Open the selected agent's worktree with the configured `worktree_opener`. |
| `dd` | Delete the selected agent after confirmation. |
| `dw` | Delete the selected agent's Git worktree and agent record after confirmation. Does not delete the branch. |
| `q` | Close the watch window and stop the watch process. |
| `?` | Toggle the floating help window for the complete watch-buffer keymap. |

The watch-window statusline is intentionally compact:

```text
Agent Watch  <CR> open  a add  r rename  ? help  q close
```

The full keymap is available from a centered floating help window opened with `?`.
Inside that help window, `?`, `q`, and `<Esc>` close the help. The help buffer is
scratch, unlisted, readonly, and not modifiable. Closing the watch window also
closes any visible help window.

Global normal-mode mappings:

| Key | Action |
| --- | --- |
| `<leader>aw` | Toggle the Agent Watch window. |
| `<C-\><C-\>` | Toggle the latest agent terminal. |

Inside agent terminal buffers, in terminal and normal mode:

| Key | Action |
| --- | --- |
| `<C-\><C-\>` | Toggle the latest agent terminal. |

---

## Configuration

```lua
require('agent-watch').setup({
    cli            = 'aw',                        -- path to the aw CLI
    daemon_url     = nil,                         -- optional agent-watchd base URL override
    height         = 8,             -- watch window height in lines
    fixed_height   = true,          -- winfixheight on the watch window
    watch_interval = 1000,          -- daemon polling interval in ms
    worktree_tab_label = true,      -- label nvim worktree tabs as [branch] fileName
    default_agent  = 'claude',      -- pre-selected agent in the launch prompt
    available_agents = { 'codex', 'agent', 'claude' }, -- agents shown in the picker
    terminal = {
        layout       = 'side',       -- 'float', 'side', or 'tab'
        side         = 'right',      -- side split direction: 'right' or 'left'
        width        = 80,           -- side split width in columns
        float_width  = 0.9,          -- float width as editor fraction
        float_height = 0.85,         -- float height as editor fraction
    },
    worktree_opener = 'nvim',         -- 'nvim' (new tab + tcd) or 'tmux' (new window)
    keymaps = {
        toggle = '<leader>aw',
        toggle_latest = '<C-\\><C-\\>',
    },
})
```

`available_agents` must be a non-empty subset of `{ 'codex', 'agent', 'claude' }`. `default_agent` must be in `available_agents`. Both are validated at setup time; misconfigurations surface an error and fall back to defaults.

`terminal.layout` must be one of `float`, `side`, or `tab`. Invalid terminal layout settings surface an error and fall back to defaults.

`worktree_opener` must be one of `nvim` or `tmux`. Invalid values surface an error and fall back to `nvim`.

`worktree_tab_label` controls whether Agent Watch installs its default worktree tabline when Neovim's `tabline` option is empty. Set it to `false` to leave the tabline untouched. The default tabline labels linked worktrees only; the repository main working tree keeps normal tab labels.

### Highlight Groups

State colors in the watch buffer use these highlight groups. Defaults are set
with `default = true`, so users and colorschemes can override them.

| Group | Default link | Used for |
| --- | --- | --- |
| `AgentWatchStateRunning` | `DiagnosticInfo` | session_started, working, running, active, busy |
| `AgentWatchStateWaiting` | `DiagnosticWarn` | running_tool, running_shell, needs_approval, waiting, queued, pending, blocked |
| `AgentWatchStateDone` | `DiagnosticOk` | done, complete, completed, success, succeeded |
| `AgentWatchStateError` | `DiagnosticError` | failed, error, failure, stopped, cancelled, canceled |
| `AgentWatchStateIdle` | `Comment` | idle, ready, stale, exited |
| `AgentWatchStateChanged` | `DiagnosticHint` | edited_file |
| `AgentWatchStateUnknown` | `Comment` | any other non-empty state |

Users can customize a group after setup, for example:

```lua
vim.api.nvim_set_hl(0, 'AgentWatchStateRunning', { link = 'String' })
```

---

## Data Flow

```text
AgentWatch / AgentWatchToggle
  → ensures Neovim server is running
  → resolves the project root from Neovim's cwd (main worktree root, or the cwd outside a Git repo)
  → resolves daemon URL from daemon_url, ~/.agent-watch/daemon.json, or default localhost
  → polls: GET <daemon_url>/agents
  → keeps rows owned by this Neovim server (server match + valid terminal buffer)
    and exited rows whose project_root matches the local project root

AgentWatchToggleLatest
  → closes the last launched/opened agent terminal when it is visible
  → otherwise reopens the last launched/opened terminal with the configured layout
  → if local latest state is invalid, fetches GET <daemon_url>/agents
  → chooses the valid row owned by this Neovim server with the highest launch ID and opens it

AgentWatchLaunch <title> [agent]
  → ensures Neovim server is running
  → creates a hidden terminal buffer
  → opens it with the configured terminal layout
  → starts terminal job: aw <agent> --title <title> --nvim-server <addr> --nvim-bufnr <bufnr>

AgentWatchLaunchWorktree <title> [branch] [agent]
  → resolves the current Git repository root
  → when <branch> is omitted, derives it from <title> (lowercased, runs of non-[a-z0-9._] replaced by -, trimmed of leading/trailing -)
  → when a 2nd positional is given and matches an available agent name, treats it as <agent> and still derives <branch> from <title>
  → uses the provided agent, or default_agent when omitted
  → branch_slug is the trimmed branch with non-[A-Za-z0-9._] runs replaced by -
  → creates a Git worktree at ../<branch_slug>
  → creates a hidden terminal buffer with cwd set to the worktree path
  → opens it with the configured terminal layout
  → starts terminal job: aw <agent> --title <title> --nvim-server <addr> --nvim-bufnr <bufnr>

AgentWatchAttachWorktree <path> [title] [agent]
  → expands ~ and resolves <path> to an absolute, real path
  → verifies the path exists and is a directory
  → runs: git -C <path> worktree list --porcelain
  → confirms <path> matches a registered worktree entry (linked or main)
  → when <title> is omitted, derives it from the worktree's current branch (git -C <path> rev-parse --abbrev-ref HEAD), falling back to the resolved path's basename when HEAD is detached or the call fails
  → when a 2nd positional is given and matches an available agent name, treats it as <agent> and still derives <title> via the same rule
  → uses the provided agent, or default_agent when omitted
  → ensures Neovim server is running
  → creates a hidden terminal buffer with cwd set to <path>
  → opens it with the configured terminal layout
  → starts terminal job: aw <agent> --title <title> --nvim-server <addr> --nvim-bufnr <bufnr>

Resume selected agent (<CR> on exited row)
  → verifies the row's folder still exists and is a directory; errors otherwise
  → ensures Neovim server is running
  → creates a hidden terminal buffer with cwd set to the row's folder
  → opens it with the configured terminal layout
  → starts terminal job: aw resume <id> --nvim-server <addr> --nvim-bufnr <bufnr>
  → the daemon re-attaches the record to this session; the resumed terminal becomes the latest-agent toggle target
  → deletes the row's stale terminal buffer when this session launched it

Watch-buffer dd
  → reads the selected row's launch ID
  → prompts: Delete agent <title-or-id>? [y/N]
  → on confirmation, DELETE <daemon_url>/launches/<id>
  → on success, force-deletes the selected terminal buffer if it still exists
  → refreshes the watch buffer

Watch-buffer dw
  → reads the selected row's launch ID
  → reads the selected row's folder
  → verifies the folder exists and is a registered linked Git worktree
  → refuses to remove the repository main working tree
  → prompts: Delete worktree <absolute-path> and agent <title-or-id>? [y/N]
  → on confirmation, runs: git -C <absolute-path> worktree remove <absolute-path>
  → on successful worktree removal, DELETE <daemon_url>/launches/<id>
  → on successful agent deletion, force-deletes the selected terminal buffer if it still exists
  → refreshes the watch buffer

AgentWatchRename <id> <title>
  → resolves daemon URL from daemon_url, ~/.agent-watch/daemon.json, or default localhost
  → PATCH <daemon_url>/launches/<id>  body: { "title": "<title>" }
  → refreshes the watch buffer on success

Open selected worktree (o)
  → selected row folder from watch buffer
  → nvim opener (default): tabnew, then tcd <folder>
  → for linked worktrees, stores vim.t.agent_watch_title, vim.t.agent_watch_branch, and vim.t.agent_watch_worktree
  → default Agent Watch tabline labels linked worktree tabs as [branch] fileName when enabled
  → tmux opener: requires $TMUX; starts detached job: tmux new-window -n <title> -c <folder>
```
