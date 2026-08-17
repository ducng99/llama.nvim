local M = {}

M.default = {
    endpoint_fim      = 'http://127.0.0.1:8012/infill',
    endpoint_inst     = 'http://127.0.0.1:8012/v1/chat/completions',
    model_fim         = '',
    model_inst        = '',
    inst_extra_body   = {},
    api_key           = '',
    n_prefix          = 256,
    n_suffix          = 64,
    n_predict         = 128,
    stop_strings      = {},
    t_max_prompt_ms   = 500,
    t_max_predict_ms  = 1000,
    show_info         = 2,
    auto_fim          = true,
    max_line_suffix   = 8,
    max_cache_keys    = 250,
    ring_n_chunks     = 16,
    ring_chunk_size   = 64,
    ring_scope        = 1024,
    ring_update_ms    = 1000,
    enable_at_startup = true,
    debounce          = 75,

    keymaps = {
        fim_trigger     = '',
        fim_accept_full = '',
        fim_accept_line = '',
        fim_accept_word = '',
        inst_trigger    = '',
        inst_rerun      = '',
        inst_continue   = '',
        inst_accept     = '',
        inst_cancel     = '',
        debug_toggle    = '',
    },

    theme = {
        llama_hl_fim_hint        = { fg = '#ff772f', ctermfg = 202 },
        llama_hl_fim_info        = { fg = '#77ff2f', ctermfg = 119 },
        llama_hl_inst_src        = { bg = '#554433', ctermbg = 236 },
        llama_hl_inst_virt_proc  = { fg = '#77ff2f', ctermfg = 119 },
        llama_hl_inst_virt_gen   = { fg = '#77ff2f', ctermfg = 119 },
        llama_hl_inst_virt_ready = { fg = '#ff772f', ctermfg = 202 },
    },
}

function M.setup(user)
    user = user or {}

    M.current = vim.tbl_deep_extend('force', vim.deepcopy(M.default), user)
end

function M.get()
    if not M.current then
        M.setup({})
    end
    return M.current
end

return M
