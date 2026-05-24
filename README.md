# llama.vim

Local LLM-assisted text completion for Neovim.

<img width="485" alt="image" src="https://github.com/user-attachments/assets/a950e38c-3b3f-4c46-94fe-0d6e0f790fc6">

#### Fill-in-Middle (FIM) completions

![llama vim-spec-1](https://github.com/user-attachments/assets/404ebc2a-e4b8-4119-999b-e5365ec3208d)

#### Instruction-based editing

https://github.com/user-attachments/assets/641a6e72-f1a2-4fe5-b0fd-c2597c6f4cdc

https://github.com/user-attachments/assets/68bff15b-2d91-4800-985d-b7b110a0ccb7

---

## Features

- Auto-suggest on cursor movement in `Insert` mode
- Accept a suggestion with `Tab`
- Accept the first line of a suggestion with `Shift+Tab`
- Instruction-based editing with `<leader>lli`
- Control max text generation time
- Configure scope of context around the cursor
- Ring context with chunks from open and edited files and yanked text
- [Supports very large contexts even on low-end hardware via smart context reuse](https://github.com/ggml-org/llama.cpp/pull/9787)
- Display performance stats

## Requirements

- Neovim 0.10+
- `curl`
- [llama.cpp](https://github.com/ggml-org/llama.cpp) server running with a FIM-compatible model

## Installation

### lazy.nvim

```lua
{
    'ggml-org/llama.vim',
    opts = {
        -- your configuration here
    },
}
```

### packer.nvim

```lua
use {
    'ggml-org/llama.vim',
    config = function()
        require('llama').setup({
            -- your configuration here
        })
    end
}
```

### Plugin configuration

You can customize *llama.vim* by calling `require('llama').setup({...})` or by
setting `vim.g.llama_config` before the plugin loads.

Examples:

1. Disable the inline info:

    ```lua
    require('llama').setup({ show_info = 0 })
    ```

2. Disable auto FIM (Fill-In-the-Middle) completion:

    ```lua
    {
        'ggml-org/llama.vim',
        opts = {
            auto_fim = false,
        },
    }
    ```

3. Configure FIM keymaps:

    ```lua
    require('llama').setup({
        keymap_fim_trigger     = '<leader>llf',
        keymap_fim_accept_full = '<Tab>',
        keymap_fim_accept_line = '<S-Tab>',
        keymap_fim_accept_word = '<leader>ll]',
    })
    ```

4. Configure instruction-based editing keymaps:

    ```lua
    require('llama').setup({
        keymap_inst_trigger  = '<leader>lli',
        keymap_inst_rerun    = '<leader>llr',
        keymap_inst_continue = '<leader>llc',
        keymap_inst_accept   = '<Tab>',
        keymap_inst_cancel   = '<Esc>',
    })
    ```

5. Force single-line FIM completion:

    ```lua
    require('llama').setup({
        n_prefix = 1024,
        n_suffix = 1024,
        auto_fim = false,
        keymap_fim_accept_full = '<C-S>',
        stop_strings = { '\n' },
        enable_at_startup = false,
    })
    ```

Please refer to `:help llama_config` or the [source](./lua/llama/config.lua)
for the full list of options.

### llama.cpp setup

The plugin requires a [llama.cpp](https://github.com/ggml-org/llama.cpp) server instance to be running at the configured `endpoint_fim` and/or `endpoint_inst`.

#### Mac OS

```bash
brew install llama.cpp
```

#### Windows

```bash
winget install llama.cpp
```

#### Any other OS

Either build from source or use the latest binaries: https://github.com/ggml-org/llama.cpp/releases

### llama.cpp settings

Here are recommended settings, depending on the amount of VRAM that you have:

- More than 64GB VRAM:

  ```bash
  llama-server --fim-qwen-30b-default
  ```

- More than 16GB VRAM:

  ```bash
  llama-server --fim-qwen-7b-default
  ```

- Less than 16GB VRAM:

  ```bash
  llama-server --fim-qwen-3b-default
  ```

- Less than 8GB VRAM:

  ```bash
  llama-server --fim-qwen-1.5b-default
  ```

Use `:help llama` for more details.

### Recommended LLMs

The plugin requires FIM-compatible models: [HF collection](https://huggingface.co/collections/ggml-org/llamavim-6720fece33898ac10544ecf9)

## Examples

<img width="1758" alt="image" src="https://github.com/user-attachments/assets/8f5748b3-183a-4b7f-90e1-9148f0a58883">

### Using `llama.vim` on M1 Pro (2021) with `Qwen2.5-Coder 1.5B Q8_0`:

<img width="1512" alt="image" src="https://github.com/user-attachments/assets/0ccb93c6-c5c5-4376-a5a3-cc99fafc5eef">

The orange text is the generated suggestion. The green text contains performance stats for the FIM request: the currently used context is `15186` tokens and the maximum is `32768`. There are `30` chunks in the ring buffer with extra context (out of `64`). So far, `1` chunk has been evicted in the current session and there are `0` chunks in queue. The newly computed prompt tokens for this request were `260` and the generated tokens were `24`. It took `1245 ms` to generate this suggestion after entering the letter `c` on the current line.

### Using `llama.vim` on M2 Ultra with `Qwen2.5-Coder 7B Q8_0`:

https://github.com/user-attachments/assets/1f1eb408-8ac2-4bd2-b2cf-6ab7d6816754

Demonstrates that the global context is accumulated and maintained across different files and showcases the overall latency when working in a large codebase.

### Another example on a small Swift code

![llama vim-swift](https://github.com/user-attachments/assets/206c8399-ff73-495d-ba67-65725138c021)

## Implementation details

The plugin aims to be very simple and lightweight and at the same time to provide high-quality and performant local FIM completions, even on consumer-grade hardware. Read more on how this is achieved in the following links:

- Initial implementation and technical description: https://github.com/ggml-org/llama.cpp/pull/9787
- Classic Vim support: https://github.com/ggml-org/llama.cpp/pull/9995

## Other IDEs

- VS Code: https://github.com/ggml-org/llama.vscode
