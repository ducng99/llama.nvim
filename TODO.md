# TODO — Full FIM Refactor (Adopting copilot.lua Patterns)

## Phase 1: Keymap Passthrough Module

Create `lua/llama/keymaps.lua` (adapted from `copilot.lua/lua/copilot/keymaps/init.lua`).

- `register_keymap_with_passthrough(mode, key, action, desc, bufnr)`
  - Saves the existing buffer-local mapping (rhs string **or** Lua callback, including `expr` callbacks).
  - Registers a new buffer-local mapping that calls `action()`.
  - If `action()` returns `true` (it handled the key because a suggestion is visible), swallow the key.
  - If `action()` returns `false` (no suggestion visible), transparently fall through to the **original** mapping.
- `unset_keymap_if_exists(mode, key, bufnr)` restores the original mapping and cleans up.
- Keep an internal `previous_keymaps` registry keyed by `bufnr:mode:key`.

**Why:** This is the #1 fix. `llama.vim` currently hard-maps `<Tab>` globally in insert mode, which breaks `nvim-cmp`, snippets, and other plugins. With passthrough, `<Tab>` only accepts a suggestion when one is actually shown.

---

## Phase 2: Config Additions

Update `lua/llama/config.lua`.

- Add `debounce = 75` to the default config table.
- This controls the milliseconds to wait after the user stops typing before firing a new FIM request.

---

## Phase 3: FIM Core Refactor

Major rewrite of `lua/llama/fim.lua`.

### A. Per-Buffer State
Replace all top-level module globals (`fim_hint_shown`, `fim_data`, `current_job_fim`, `timer_fim`, `t_last_move`, `indent_last`) with a per-buffer state table.

```lua
local state = {} -- keyed by bufnr
```

Provide `get_ctx(bufnr)` (like `copilot.lua`'s `get_ctx`) that lazily initializes:
- `hint_shown`
- `fim_data` (pos, content, can_accept)
- `current_job`
- `debounce_timer`
- `last_move_time`
- `indent_last`

This prevents suggestion leaks when switching buffers.

### B. Debounce & Job Lifecycle (vim.uv Timer)
Implement the exact lifecycle from `copilot.lua/suggestion/init.lua`, using `vim.uv.new_timer()` (Lua-native, robust).

1. **`schedule_fim(bufnr)`** — called on every trigger event (`CursorMovedI`, `InsertEnter`, `BufEnter`, etc.)
   - Calls `cancel_inflight_job(ctx)`
   - Calls `stop_timer(ctx)`
   - Starts a new `debounce` timer
2. **`trigger_fim(bufnr, timer_id)`** — called when the timer fires
   - Validates that `bufnr` is still the current buffer and mode is still insert
   - Calls `do_fim()` to actually build context and send the HTTP request
3. **`cancel_inflight_job(ctx)`** — explicitly calls `require('llama.http').stop_job(ctx.current_job)`

**Why:** Currently `llama.vim` queues a 100ms retry if a job is already running, which can stack up. The new model cancels stale work and always respects the latest cursor position.

### C. Context Building
Keep `fim_ctx_local()` mostly intact (it is llama.cpp-specific and has no equivalent in copilot.lua), but clean up variable naming.

### D. Display Utilities (ported from copilot.lua)
Create `lua/llama/suggestion_util.lua`:

- **`remove_common_suffix(text_after_cursor, suggestion_first_line)`**
  - Prevents the suggestion from rendering text that is already present after the cursor.
- **`get_display_adjustments(suggestion_first_line, pos_x, cursor_col, current_line)`**
  - Handles indentation mismatches and partial overlap between the suggestion and what the user has already typed.

### E. Rendering (`fim_render`)
- Refactor to use the display utilities above instead of the current ad-hoc suffix/duplicate checks.
- For **single-line** suggestions: use `virt_text_pos = 'inline'` with `hl_mode = 'replace'` (copilot.lua style). This makes the ghost text look like native inline completion.
- For **multi-line** suggestions: keep `virt_lines` but compute them cleanly.
- Keep the info overlay (`show_info`) but attach it as a separate extmark or virt text chunk for cleaner separation.

### F. Accept & Apply (`fim_accept`)
- Add an explicit **undo breakpoint** before applying edits (`vim.cmd('let &undolevels = &undolevels')`). This matches copilot.lua and makes undo after an accept predictable.
- Refactor the accept logic (`full`, `line`, `word`) into a single flow:
  1. Compute the exact lines to insert.
  2. Apply with `nvim_buf_set_lines`.
  3. Position cursor.
- After a partial or full accept, re-trigger FIM for the next suggestion (preserve existing `llama.vim` behavior, but use the new `schedule_fim()`).

### G. Hide & Cleanup (`fim_hide`)
- Clear extmarks.
- Reset per-buffer state.
- Unset buffer-local accept keymaps via the new passthrough module.

---

## Phase 4: Init & Autocmds Update

Update `lua/llama/init.lua`.

### Keymaps
- Replace all direct `vim.keymap.set` / `vim.keymap.del` calls in `enable()` and `disable()` with the new `llama.keymaps` module.
- This applies to:
  - `keymap_fim_trigger`
  - `keymap_fim_accept_full`
  - `keymap_fim_accept_line`
  - `keymap_fim_accept_word`

### Autocmds
Add missing trigger events that `copilot.lua` uses:

- **`InsertEnter`** → `schedule_fim()` (if `auto_fim` is on). This makes suggestions appear immediately when you enter insert mode, not just after you move the cursor.
- **`BufEnter`** → if already in insert mode, `schedule_fim()`.
- Keep existing `CursorMovedI`, `InsertLeavePre`, `CompleteChanged`, `CompleteDone`, `TextYankPost`, `BufLeave`, `BufWritePost`.

---

## Phase 5: Tests

Update `tests/integration/fim_spec.lua`.

- Update existing tests to use per-buffer state (access state via a test helper or module function).
- Add tests for `remove_common_suffix` / `get_display_adjustments`.
- Add a test for keymap passthrough: simulate an existing `<Tab>` mapping, show a suggestion, accept it, then verify the original `<Tab>` mapping still works when no suggestion is visible.
- Ensure `fim_hide` correctly clears state for a specific buffer.
