# llama.nvim

Local LLM-assisted text completion for Neovim, powered by [llama.cpp](https://github.com/ggml-org/llama.cpp).

No API keys. No cloud. Just your GPU (or CPU) and a model file.

A rewrite combining [llama.vim](https://github.com/ggml-org/llama.vim) and [copilot.lua](https://github.com/zbirenbaum/copilot.lua).

## Features

- **Fill-in-the-Middle (FIM)** — Inline suggestions as you type, triggered automatically or on demand.
- **Instruction-based editing** — Select code, describe what you want, and let the model rewrite it.
- **Fully local** — Runs through your own llama.cpp server. No data leaves your machine.
- **Zero-config defaults** — Works out of the box with a standard llama.cpp server on `localhost:8012`.

## Requirements

- [Neovim](https://neovim.io/) >= 0.10
- [llama.cpp](https://github.com/ggml-org/llama.cpp) server running with a FIM-capable model (e.g., CodeLlama, DeepSeek-Coder, Qwen2.5-Coder)
- `curl` executable available in your `$PATH`

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "ducng99/llama.nvim",
  config = function()
    require("llama").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ducng99/llama.nvim",
  config = function()
    require("llama").setup()
  end,
}
```

## Quick Start

1. Start your llama.cpp server with a FIM model:

```bash
./llama-server \
  -m models/your-fim-model.gguf \
  --host 127.0.0.1 \
  --port 8012 \
  -c 4096
```

2. Open Neovim and start typing. FIM suggestions appear automatically (if enabled).

3. Accept a suggestion with `<Tab>` (default), or cycle through alternatives with `<M-]>` and `<M-[>`.

## Configuration

```lua
require("llama").setup({
  -- Server endpoints (defaults shown)
  endpoint_fim  = "http://127.0.0.1:8012/infill",
  endpoint_inst = "http://127.0.0.1:8012/v1/chat/completions",

  -- Model names (leave empty if not needed)
  model_fim  = "",
  model_inst = "",

  -- FIM settings
  n_prefix    = 256,  -- Context lines before cursor
  n_suffix    = 64,   -- Context lines after cursor
  n_predict   = 128,  -- Max tokens to generate
  stop_strings = {},
  t_max_prompt_ms   = 500,   -- Max time waiting for first token
  t_max_predict_ms  = 1000,  -- Max generation time
  auto_fim     = true,       -- Enable auto-suggestions
  max_line_suffix = 8,       -- Max lines for suffix context
  debounce     = 75,         -- Debounce delay (ms)

  -- Cache and ring buffer settings
  max_cache_keys = 250,
  ring_n_chunks   = 16,
  ring_chunk_size = 64,
  ring_scope      = 1024,
  ring_update_ms  = 1000,

  -- Keymaps (assign your own keys - all default to empty string)
  keymap_fim_trigger     = '<leader>llf',  -- FIM trigger
  keymap_fim_accept_full = '<Tab>',        -- Accept full suggestion
  keymap_fim_accept_line = '<S-Tab>',      -- Accept line only
  keymap_fim_accept_word = '<leader>ll]',  -- Accept word only
  keymap_inst_trigger    = '<leader>lli',  -- Open instruction editor
  keymap_inst_rerun      = '<leader>llr',  -- Re-run last instruction
  keymap_inst_continue   = '<leader>llc',  -- Continue generation
  keymap_inst_accept     = '<Tab>',        -- Accept instruction output
  keymap_inst_cancel     = '<Esc>',        -- Cancel instruction
  keymap_debug_toggle    = '<leader>lld',  -- Toggle debug mode
})
```



## Commands

| Command | Description |
|---------|-------------|
| `:LlamaEnable` | Enable FIM auto-suggestions |
| `:LlamaDisable` | Disable FIM auto-suggestions |
| `:LlamaToggle` | Toggle FIM on/off |
| `:LlamaInstruct` | Open instruction-based editing prompt |
| `:LlamaDebug` | Toggle debug logging |

## Instruction-Based Editing

1. Visually select a block of code.
2. Run `:LlamaInstruct` (or your mapped key).
3. Type your instruction (e.g., "refactor to use list comprehension").
4. The model generates a diff or replacement.

## How It Works

llama.nvim communicates with a local llama.cpp HTTP server using:

- `/infill` endpoint for Fill-in-the-Middle predictions
- `/v1/chat/completions` for instruction-based editing

Context is built from open buffers, recently yanked text, and the current file. A ring buffer caches chunks for smarter prompts.

## Troubleshooting

**No suggestions appear?**

- Verify your llama.cpp server is running and accessible: `curl http://127.0.0.1:8012/health`
- Check that your model supports FIM (look for `<|fim_middle|>` or `<|fim_prefix|>` tokens).
- Enable debug mode (`:LlamaDebug`) and check `:messages` for request errors.

**Slow responses?**

- Reduce `n_predict` or `n_prefix` in config.
- Ensure your server has GPU acceleration enabled (`-ngl` flag).

## Acknowledgements

- [llama.vim](https://github.com/ggml-org/llama.cpp)
- [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

## License

MIT
