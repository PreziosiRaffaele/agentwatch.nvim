# AGENTS.md

## Project

This is a local Neovim plugin for the sibling `agent-watch` CLI.

- Plugin root: this repository.
- CLI dependency: `/Users/raffaelepreziosi/code/agent-watch/bin/agent-watch.js`
- Dotfiles lazy.nvim spec: `/Users/raffaelepreziosi/dotfiles/config/nvim/lua/rpreziosi/plugins/agentWatch.lua`

## Source of Truth

Use `docs/spec.md` as the source of truth for product behavior, command semantics,
daemon API usage, configuration, and user-facing data flow. Do not duplicate that
content here. When behavior changes, update the spec first, then keep this file
limited to contributor workflow and engineering practices.

`README.md` is the user-facing quickstart. Keep it concise and consistent with
the spec.

## Compatibility Policy

This project is in beta. By default, do not preserve backward compatibility; prefer always clean design.
When changing or removing public commands, flags, columns, or JSON fields, update the README, spec, and this file so the supported surface is explicit.

## Folder Structure

- `plugin/agent-watch.lua`: Neovim startup shim. Keep it minimal; require the Lua module and call setup only.
- `lua/agent-watch/`: plugin implementation.
- `tests/`: test suite (see Testing below).
- `docs/spec.md`: canonical product and integration spec.
- `README.md`: installation and daily-use documentation.
- `AGENTS.md`: contributor workflow, code quality, and development guardrails.

Avoid adding new top-level directories unless they have a clear role.

## Development Practices

- Keep the startup path cheap. Avoid expensive work in `plugin/agent-watch.lua` or during `setup()`.
- When sending a command into a terminal job, keep using `vim.fn.shellescape` for every command part.
- Prefer small, local helpers over broad abstractions. Extract only when it reduces real duplication or clarifies a boundary.
- Preserve user buffers and windows. Any buffer deletion or window closing must be tied to an explicit plugin action described in the spec.
- Avoid unrelated dotfiles changes. Existing local changes in dotfiles may belong to the user.

When creating lua modules:

- Group code by responsibility, not by generic file type.
- Do not create huge Lua modules that take on multiple responsibilities.
- Prefer explicit exported functions over broad utility modules.
- Keep module APIs small; do not export internals just for tests unless there is a clear reason.
- Use domain names for files and functions, not vague names like `helpers`, `utils`, or `common` unless the code is truly cross-cutting.
- Prefer plain objects and simple functions before introducing classes.
- Avoid barrel files.
- Before adding a new module, define its owner responsibility in one sentence. If that sentence has multiple unrelated responsibilities, split the module.
- Add comments only for non-obvious control flow or integration constraints.

## Feature Workflow

For every new feature, follow this sequence:

1. **Draft the feature spec** — create `docs/<feature-name>.md` in the feature branch.
   Describe the goal, configuration, behavior, and what changes `docs/spec.md` will
   need. Do not modify `docs/spec.md` yet.
2. **Develop and test** — implement the feature and verify it against the feature spec.
3. **Update the main spec** — apply the changes described in the feature spec to
   `docs/spec.md`, then delete the feature spec file.

## Testing

Tests use [`mini.test`](https://github.com/echasnovski/mini.nvim) in headless
Neovim. The suite is fully offline and deterministic: the plugin talks to
`agent-watchd` only through `curl` and to agents only through the `aw` CLI, so
both are replaced by stubs in `tests/helpers/fake_bin/`. No real daemon, agent,
or network is ever contacted — never add a test that drives a live agent.

- `tests/unit/` — pure-logic cases (rows, config, daemon URL/JSON parsing,
  worktree slug/path, highlight mapping). Run in the runner process.
- `tests/integration/` — drive the real commands and keymaps in a child Neovim
  (`MiniTest.new_child_neovim`) against the stub `curl` (canned `/agents`,
  recorded `PATCH`) and fake `aw`, plus real temporary git repos for worktrees.
- `tests/helpers/` — `child.lua` (child bootstrap, PATH, wait helpers) and the
  `fake_bin/` stubs. `tests/minimal_init.lua` bootstraps the rtp for both the
  runner and child Neovims.

Run the full suite with `make test` (clones the test-only `mini.nvim` into
`deps/` on first run). Run one file with:

```sh
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua MiniTest.run_file('tests/unit/test_rows.lua')"
```

The `test-nvim` Claude Code skill wraps these commands.

## Verification

After any edit to `*.lua` files, run `make quality` before finishing.
This runs luacheck (static analysis) and stylua (formatting) and must pass with no errors.
Run `make test` (or `make check` for both) when you change plugin behavior or tests.
