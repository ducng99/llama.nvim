# AGENTS.md

## Project

Neovim plugin (Lua) providing local LLM-assisted text completion via a llama.cpp server. Two modes: Fill-in-Middle (FIM) auto-suggest and instruction-based editing.

## Entry Points

- `plugin/llama.lua` — autoload entry, calls `require('llama').init()`
- `lua/llama/init.lua` — main module (`setup`, `enable`, `disable`, `toggle`); owns autocmd registration (`setup_autocmds`) and keymap registration/teardown on enable/disable
- `lua/llama/config.lua` — defaults and user config merge

## Configuration

Config via `require('llama').setup({...})`.
Default endpoints: `http://127.0.0.1:8012/infill` (FIM) and `http://127.0.0.1:8012/v1/chat/completions` (instruct).
Deprecated config keys are auto-renamed with a warning (see `renames` table in `config.lua`).

## Module Structure (`lua/llama/`)

| File | Purpose |
|---|---|
| `init.lua` | Lifecycle: setup, enable/disable, autocmds, keymaps |
| `config.lua` | Defaults, user config merge, deprecated key migration |
| `fim.lua` | Fill-in-Middle suggestion logic |
| `instruct.lua` | Instruction-based editing |
| `http.lua` | HTTP requests to llama.cpp server |
| `ring.lua` | Ring buffer for context chunks (open files, yanked text) |
| `cache.lua` | Prompt caching |
| `keymaps.lua` | Keymap registration helpers |
| `suggestion_util.lua` | Suggestion display utilities |
| `debug.lua` | Debug logging and toggle |

## Tests

- Framework: plenary.nvim `busted` runner
- Run all: `bash tests/run.sh`
- Run a single spec file: `bash tests/run.sh -c "PlenaryBustedFile tests/integration/fim_spec.lua"` (or invoke `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/integration/<name>_spec.lua"` directly)
- Prerequisite: `.deps/plenary.nvim` must be present (gitignored, clone manually into `.deps/plenary.nvim`)
- Spec files: `tests/integration/*_spec.lua`
- `tests/minimal_init.lua` sets up runtimepath for headless runs

## External Dependencies

- Requires `curl` executable (checked at init)
- Requires a running llama.cpp server with FIM-capable model
- No package manager, no lockfile, no build step

## Conventions

- No linter, formatter, or typecheck config in repo — follow existing Lua style
- No CI workflows
