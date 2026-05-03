# AGENTS.md

## Project

This is a local Neovim plugin for the sibling `agent-watch` CLI.

- Plugin root: `/Users/raffaelepreziosi/code/agent-watch-nvim`
- CLI dependency: `/Users/raffaelepreziosi/code/agent-watch/bin/agent-watch.js`
- Dotfiles lazy.nvim spec: `/Users/raffaelepreziosi/dotfiles/config/nvim/lua/rpreziosi/plugins/agentWatch.lua`

The plugin is loaded locally from `~/code/agent-watch-nvim`.

## Files

- `plugin/agent-watch.lua` is the startup shim. Keep it minimal.
- `lua/agent-watch/init.lua` contains the implementation.
- `README.md` documents user-facing commands and setup.
- `AGENTS.md` documents contributor and agent workflow.

## Commands

- `:AgentWatch` opens or refreshes the bottom scratch buffer for agents attached to the current Neovim server.
- `:AgentWatchLaunch <title> [codex|cursor|agent] [args...]` opens a terminal and runs `agent-watch launch`.
- `:AgentWatchRename [title]` renames the selected row with `agent-watch rename <id> <title>`.

`AgentWatchLaunch` must always pass:

- `--title <title>`
- `--nvim-server <current server>`
- `--nvim-terminal-bufnr <terminal buffer number>`
- the selected agent, or `opts.default_agent` when omitted

## Behavior Notes

- Ensure a Neovim server exists with `vim.v.servername` or `vim.fn.serverstart()`.
- Use `vim.system({ cli, 'list', '--json', '--filter', 'nvim_server=' .. server }, { text = true }, callback)` for one-shot listing.
- Use `agent-watch list --json --filter nvim_server=<server> --watch --interval <ms>` for the live watch buffer.
- Parse JSON with `vim.json.decode`.
- The CLI currently returns a JSON object with a `rows` array; keep support for list-shaped JSON and common container keys.
- Ask the CLI to filter by `nvim_server`, and keep local exact `row.nvim_server == current_server` filtering as a compatibility guard.
- Keep the watch buffer scratch-only: `buftype=nofile`, `bufhidden=hide`, `swapfile=false`, `filetype=agent-watch`.
- Do not delete or alter buffers except when the user presses `dd` on a mapped agent row.
- `r` on an agent row prompts for a new title and refreshes the list after rename succeeds.
- `dd` force-deletes the selected row's `nvim_terminal_bufnr`, which terminates that terminal job.

## Style

- Use Lua patterns already present in `lua/agent-watch/init.lua`.
- Prefer explicit argument lists for process execution.
- When sending a command into a terminal job, keep using `vim.fn.shellescape` for every command part.
- Keep edits ASCII unless there is a concrete reason to do otherwise.
- Avoid unrelated dotfiles changes. Existing local changes in dotfiles may belong to the user.

## Verification

Run from the plugin root:

```sh
nvim --headless -u NONE -i NONE -c "set shadafile=NONE" -c "set rtp+=/Users/raffaelepreziosi/code/agent-watch-nvim" -c "lua require('agent-watch').setup()" -c "qa"
```

Check CLI compatibility:

```sh
/Users/raffaelepreziosi/code/agent-watch/bin/agent-watch.js list --json --filter nvim_server=/tmp/nonexistent-agent-watch-server
```

Parse the lazy.nvim spec when it changes:

```sh
nvim --headless -u NONE -i NONE -c "set shadafile=NONE" -c "luafile /Users/raffaelepreziosi/dotfiles/config/nvim/lua/rpreziosi/plugins/agentWatch.lua" -c "qa"
```

Full `:AgentWatch` headless verification may need permission outside the sandbox because Neovim must create a server socket:

```sh
nvim --headless -u NONE -i NONE -c "set shadafile=NONE" -c "set rtp+=/Users/raffaelepreziosi/code/agent-watch-nvim" -c "runtime plugin/agent-watch.lua" -c "AgentWatch" -c "sleep 500m" -c "qa!"
```

## Manual Checks

- `:AgentWatch` opens a bottom buffer and shows only agents for the current Neovim server.
- `:AgentWatchLaunch "Some title"` launches the configured default agent.
- `:AgentWatchLaunch "Some title" cursor` launches Cursor through the CLI.
- `<CR>` on an agent row jumps to its terminal buffer.
- `r` on an agent row renames the tracked agent title.
- `dd` on an agent row deletes that terminal buffer and refreshes the list.
