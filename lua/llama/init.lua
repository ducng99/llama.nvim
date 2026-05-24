local M = {}

local enabled = false
local augroup = vim.api.nvim_create_augroup('llama', { clear = true })

function M.setup(opts)
    require('llama.config').setup(opts)

    local cfg = require('llama.config').get()

    vim.api.nvim_set_hl(0, 'llama_hl_fim_hint', { fg = '#ff772f', ctermfg = 202, default = true })
    vim.api.nvim_set_hl(0, 'llama_hl_fim_info', { fg = '#77ff2f', ctermfg = 119, default = true })
    vim.api.nvim_set_hl(0, 'llama_hl_inst_src', { bg = '#554433', ctermbg = 236, default = true })
    vim.api.nvim_set_hl(0, 'llama_hl_inst_virt_proc', { fg = '#77ff2f', ctermfg = 119, default = true })
    vim.api.nvim_set_hl(0, 'llama_hl_inst_virt_gen', { fg = '#77ff2f', ctermfg = 119, default = true })
    vim.api.nvim_set_hl(0, 'llama_hl_inst_virt_ready', { fg = '#ff772f', ctermfg = 202, default = true })

    vim.api.nvim_create_user_command('LlamaEnable', function()
        M.enable()
    end, {})
    vim.api.nvim_create_user_command('LlamaDisable', function()
        M.disable()
    end, {})
    vim.api.nvim_create_user_command('LlamaToggle', function()
        M.toggle()
    end, {})
    vim.api.nvim_create_user_command('LlamaToggleAutoFim', function()
        M.toggle_auto_fim()
    end, {})
    vim.api.nvim_create_user_command('LlamaInstruct', function(opts)
        require('llama.instruct').inst(opts.line1, opts.line2)
    end, { range = true })

    require('llama.debug').setup()
end

function M.init()
    require('llama.debug').log('llama.vim initializing ...')

    if vim.fn.executable('curl') == 0 then
        vim.notify('llama.vim requires the "curl" command to be available', vim.log.levels.WARN)
        return
    end

    local opts = {}
    if vim.g.llama_config then
        opts = vim.g.llama_config
    end
    M.setup(opts)

    if require('llama.config').get().enable_at_startup then
        M.enable()
    end
end

function M.is_enabled()
    return enabled
end

function M.setup_autocmds()
    vim.api.nvim_clear_autocmds({ group = augroup })

    local cfg = require('llama.config').get()

    vim.api.nvim_create_autocmd('InsertLeavePre', {
        group = augroup,
        pattern = '*',
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()
            require('llama.fim').fim_hide(bufnr)
        end,
    })

    vim.api.nvim_create_autocmd('CompleteChanged', {
        group = augroup,
        pattern = '*',
        callback = function()
            local bufnr = vim.api.nvim_get_current_buf()
            require('llama.fim').fim_hide(bufnr)
        end,
    })

    vim.api.nvim_create_autocmd('CompleteDone', {
        group = augroup,
        pattern = '*',
        callback = function()
            require('llama.fim').on_move()
        end,
    })

    vim.api.nvim_create_autocmd('BufUnload', {
        group = augroup,
        pattern = '*',
        callback = function(args)
            local bufnr = tonumber(args.buf)
            if bufnr then
                require('llama.fim').cleanup_buffer(bufnr)
            end
        end,
    })

    if cfg.auto_fim then
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
            group = augroup,
            pattern = '*',
            callback = function()
                require('llama.fim').on_move()
            end,
        })

        vim.api.nvim_create_autocmd('CursorMovedI', {
            group = augroup,
            pattern = '*',
            callback = function()
                require('llama.fim').schedule_fim()
            end,
        })

        vim.api.nvim_create_autocmd('InsertEnter', {
            group = augroup,
            pattern = '*',
            callback = function()
                require('llama.fim').schedule_fim()
            end,
        })
    end

    vim.api.nvim_create_autocmd('TextYankPost', {
        group = augroup,
        pattern = '*',
        callback = function()
            if vim.v.event.operator == 'y' then
                local lines = vim.v.event.regcontents or {}
                require('llama.ring').pick_chunk(lines, false, true)
            end
        end,
    })

    vim.api.nvim_create_autocmd('BufEnter', {
        group = augroup,
        pattern = '*',
        callback = function()
            if cfg.auto_fim and vim.fn.mode():match('^[iR]') then
                require('llama.fim').schedule_fim()
            end

            local cfg_inner = require('llama.config').get()
            local line = vim.fn.line('.')
            local max_y = vim.api.nvim_buf_line_count(0)
            local l0 = math.max(1, line - math.floor(cfg_inner.ring_chunk_size / 2))
            local l1 = math.min(max_y, line + math.floor(cfg_inner.ring_chunk_size / 2))
            local lines = vim.api.nvim_buf_get_lines(0, l0 - 1, l1, false)
            require('llama.ring').pick_chunk(lines, true, true)
        end,
    })

    vim.api.nvim_create_autocmd('BufLeave', {
        group = augroup,
        pattern = '*',
        callback = function()
            local cfg_inner = require('llama.config').get()
            local line = vim.fn.line('.')
            local max_y = vim.api.nvim_buf_line_count(0)
            local l0 = math.max(1, line - math.floor(cfg_inner.ring_chunk_size / 2))
            local l1 = math.min(max_y, line + math.floor(cfg_inner.ring_chunk_size / 2))
            local lines = vim.api.nvim_buf_get_lines(0, l0 - 1, l1, false)
            require('llama.ring').pick_chunk(lines, true, true)
        end,
    })

    vim.api.nvim_create_autocmd('BufWritePost', {
        group = augroup,
        pattern = '*',
        callback = function()
            local cfg_inner = require('llama.config').get()
            local line = vim.fn.line('.')
            local max_y = vim.api.nvim_buf_line_count(0)
            local l0 = math.max(1, line - math.floor(cfg_inner.ring_chunk_size / 2))
            local l1 = math.min(max_y, line + math.floor(cfg_inner.ring_chunk_size / 2))
            local lines = vim.api.nvim_buf_get_lines(0, l0 - 1, l1, false)
            require('llama.ring').pick_chunk(lines, true, true)
        end,
    })
end

function M.enable()
    if enabled then
        return
    end

    local cfg = require('llama.config').get()
    local keymaps_mod = require('llama.keymaps')

    if cfg.keymap_fim_trigger ~= '' then
        keymaps_mod.register_keymap_with_passthrough('i', cfg.keymap_fim_trigger, function()
            return require('llama.fim').fim_inline(false, false)
        end, '[llama] trigger suggestion', 0)
    end

    if cfg.keymap_debug_toggle ~= '' then
        vim.keymap.set('n', cfg.keymap_debug_toggle, function()
            require('llama.debug').toggle()
        end, { silent = true })
    end

    if cfg.keymap_inst_trigger ~= '' then
        vim.keymap.set('v', cfg.keymap_inst_trigger, function()
            vim.cmd('LlamaInstruct')
        end, { silent = true })
    end

    if cfg.keymap_inst_rerun ~= '' then
        vim.keymap.set('n', cfg.keymap_inst_rerun, function()
            require('llama.instruct').inst_rerun()
        end, { silent = true })
    end

    if cfg.keymap_inst_continue ~= '' then
        vim.keymap.set('n', cfg.keymap_inst_continue, function()
            require('llama.instruct').inst_continue()
        end, { silent = true })
    end

    if cfg.keymap_inst_accept ~= '' then
        vim.keymap.set('n', cfg.keymap_inst_accept, function()
            require('llama.instruct').inst_accept()
        end, { silent = true })
    end

    if cfg.keymap_inst_cancel ~= '' then
        vim.keymap.set('n', cfg.keymap_inst_cancel, function()
            require('llama.instruct').inst_cancel()
        end, { silent = true })
    end

    M.setup_autocmds()

    pcall(require('llama.fim').fim_hide)

    if cfg.ring_n_chunks > 0 then
        require('llama.ring').update()
    end

    enabled = true
    require('llama.debug').log('plugin enabled')
end

function M.disable()
    local bufnr = vim.api.nvim_get_current_buf()
    require('llama.fim').fim_hide(bufnr)

    vim.api.nvim_clear_autocmds({ group = augroup })

    local cfg = require('llama.config').get()
    local keymaps_mod = require('llama.keymaps')

    if cfg.keymap_fim_trigger ~= '' then
        keymaps_mod.unset_keymap_if_exists('i', cfg.keymap_fim_trigger, 0)
    end
    if cfg.keymap_debug_toggle ~= '' then
        pcall(vim.keymap.del, 'n', cfg.keymap_debug_toggle)
    end
    if cfg.keymap_inst_trigger ~= '' then
        pcall(vim.keymap.del, 'v', cfg.keymap_inst_trigger)
    end
    if cfg.keymap_inst_rerun ~= '' then
        pcall(vim.keymap.del, 'n', cfg.keymap_inst_rerun)
    end
    if cfg.keymap_inst_continue ~= '' then
        pcall(vim.keymap.del, 'n', cfg.keymap_inst_continue)
    end
    if cfg.keymap_inst_accept ~= '' then
        pcall(vim.keymap.del, 'n', cfg.keymap_inst_accept)
    end
    if cfg.keymap_inst_cancel ~= '' then
        pcall(vim.keymap.del, 'n', cfg.keymap_inst_cancel)
    end

    enabled = false
    require('llama.debug').log('plugin disabled')
end

function M.toggle()
    if enabled then
        M.disable()
    else
        M.enable()
    end
end

function M.toggle_auto_fim()
    if not enabled then
        return
    end
    local cfg = require('llama.config').get()
    cfg.auto_fim = not cfg.auto_fim
    M.setup_autocmds()
end

return M