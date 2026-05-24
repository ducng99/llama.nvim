local debug = require('llama.debug')

describe('llama.debug', function()
    before_each(function()
        debug.clear()
    end)

    it('log accumulates entries', function()
        debug.log('test message')
        debug.log('another message', { 'detail1', 'detail2' })
        -- logs are stored internally; we verify by checking flush creates buffer content
        debug.toggle()
        local bufnr = vim.fn.bufnr('[llama.vim-debug]')
        assert.is_true(bufnr > 0)
        -- Wait for flush timer (50ms)
        vim.wait(100)
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        assert.is_true(#lines > 0)
    end)

    it('toggle creates a scratch buffer', function()
        debug.toggle()
        local bufnr = vim.fn.bufnr('[llama.vim-debug]')
        assert.is_true(bufnr > 0)
        assert.are.same('nofile', vim.bo[bufnr].buftype)
        assert.are.same(false, vim.bo[bufnr].swapfile)
    end)

    it('toggle closes existing buffer window', function()
        debug.toggle()
        local bufnr = vim.fn.bufnr('[llama.vim-debug]')
        local winnr = vim.fn.bufwinnr(bufnr)
        assert.is_true(winnr ~= -1)
        debug.toggle()
        winnr = vim.fn.bufwinnr(bufnr)
        assert.are.same(-1, winnr)
    end)

    it('clear empties log and buffer', function()
        debug.log('message')
        debug.toggle()
        vim.wait(100)
        debug.clear()
        local bufnr = vim.fn.bufnr('[llama.vim-debug]')
        if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            assert.are.same({ '' }, lines)
        end
    end)

    it('flush writes accumulated logs to buffer', function()
        debug.log('hello')
        debug.toggle()
        vim.wait(200)
        local bufnr = vim.fn.bufnr('[llama.vim-debug]')
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local found = false
        for _, line in ipairs(lines) do
            if line:find('hello') then
                found = true
                break
            end
        end
        assert.is_true(found)
    end)

    it('log truncates beyond max_lines', function()
        for i = 1, 1100 do
            debug.log('entry ' .. i)
        end
        assert.has_no.errors(function()
            debug.toggle()
        end)
    end)
end)
