local M = {}

M.default = {
    endpoint_fim           = 'http://127.0.0.1:8012/infill',
    endpoint_inst          = 'http://127.0.0.1:8012/v1/chat/completions',
    model_fim              = '',
    model_inst             = '',
    inst_extra_body        = {},
    api_key                = '',
    n_prefix               = 256,
    n_suffix               = 64,
    n_predict              = 128,
    stop_strings           = {},
    t_max_prompt_ms        = 500,
    t_max_predict_ms       = 1000,
    show_info              = 2,
    auto_fim               = true,
    max_line_suffix        = 8,
    max_cache_keys         = 250,
    ring_n_chunks          = 16,
    ring_chunk_size        = 64,
    ring_scope             = 1024,
    ring_update_ms         = 1000,
    keymap_fim_trigger     = '',
    keymap_fim_accept_full = '',
    keymap_fim_accept_line = '',
    keymap_fim_accept_word = '',
    keymap_inst_trigger    = '',
    keymap_inst_rerun      = '',
    keymap_inst_continue   = '',
    keymap_inst_accept     = '',
    keymap_inst_cancel     = '',
    keymap_debug_toggle    = '',
    enable_at_startup      = true,
    debounce               = 75,
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
