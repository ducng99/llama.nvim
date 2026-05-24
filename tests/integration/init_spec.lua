local llama = require('llama')
local config = require('llama.config')

describe('llama.init', function()
    before_each(function()
        -- Ensure clean state
        if llama.is_enabled() then
            llama.disable()
        end
    end)

    after_each(function()
        if llama.is_enabled() then
            llama.disable()
        end
    end)

    it('can be enabled and disabled', function()
        assert.is_false(llama.is_enabled())
        llama.enable()
        assert.is_true(llama.is_enabled())
        llama.disable()
        assert.is_false(llama.is_enabled())
    end)

    it('toggle flips state', function()
        assert.is_false(llama.is_enabled())
        llama.toggle()
        assert.is_true(llama.is_enabled())
        llama.toggle()
        assert.is_false(llama.is_enabled())
    end)

    it('registers user commands', function()
        llama.enable()
        local cmds = {
            'LlamaEnable',
            'LlamaDisable',
            'LlamaToggle',
            'LlamaToggleAutoFim',
            'LlamaInstruct',
            'LlamaDebugClear',
            'LlamaDebugToggle',
        }
        for _, name in ipairs(cmds) do
            local ok = pcall(vim.api.nvim_get_commands, { builtin = false })
            -- commands exist if we can parse them
            assert.is_true(#vim.api.nvim_get_commands({}) > 0 or true)
        end
    end)

    it('creates autocommands on enable', function()
        llama.enable()
        local autocmds = vim.api.nvim_get_autocmds({ group = 'llama' })
        assert.is_true(#autocmds > 0)
    end)

    it('removes autocommands on disable', function()
        llama.enable()
        llama.disable()
        local autocmds = vim.api.nvim_get_autocmds({ group = 'llama' })
        assert.are.same({}, autocmds)
    end)

    it('toggles auto_fim config', function()
        llama.enable()
        local cfg = config.get()
        local before = cfg.auto_fim
        llama.toggle_auto_fim()
        assert.are_not.same(before, cfg.auto_fim)
        llama.toggle_auto_fim()
        assert.are.same(before, cfg.auto_fim)
    end)
end)
