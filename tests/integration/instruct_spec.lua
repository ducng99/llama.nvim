local instruct = require('llama.instruct')

describe('llama.instruct', function()
    local bufnr

    before_each(function()
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            'function add(a, b) {',
            '    return a + b;',
            '}',
            '',
            'function sub(a, b) {',
            '    return a - b;',
            '}',
        })
    end)

    after_each(function()
        pcall(function()
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    it('inst_build produces correct message structure', function()
        local messages = instruct.inst_build(2, 3, 'add logging', {})
        assert.are.same(2, #messages)
        assert.are.same('system', messages[1].role)
        assert.are.same('user', messages[2].role)
        assert.is_true(messages[1].content:find('PREFIX') ~= nil)
        assert.is_true(messages[1].content:find('SELECTION') ~= nil)
        assert.is_true(messages[1].content:find('SUFFIX') ~= nil)
        assert.are.same('INSTRUCTION: add logging', messages[2].content)
    end)

    it('inst_build with inst_prev appends user message', function()
        local prev = {
            { role = 'system', content = 'sys' },
            { role = 'user', content = 'first' },
            { role = 'assistant', content = 'ans' },
        }
        local messages = instruct.inst_build(2, 3, 'second', prev)
        assert.are.same(4, #messages)
        assert.are.same('user', messages[4].role)
        assert.are.same('INSTRUCTION: second', messages[4].content)
    end)

    it('inst_build with empty instruction produces empty user content', function()
        local messages = instruct.inst_build(2, 3, '', {})
        assert.are.same('', messages[2].content)
    end)

    it('inst_callback replaces buffer range', function()
        instruct.inst_callback(bufnr, 2, 3, '    console.log(a + b);\n    return a + b;')
        -- Check only line 2 (the replaced line)
        local line = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1]
        assert.are.same('    console.log(a + b);', line)
    end)

    it('inst_callback removes trailing empty lines', function()
        instruct.inst_callback(bufnr, 2, 3, '    console.log(a + b);\n\n')
        local line = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1]
        assert.are.same('    console.log(a + b);', line)
    end)

    local function wait_for(condition)
        local ok = vim.wait(500, condition)
        assert.is_true(ok, 'timed out waiting for scheduled callback')
    end

    it('inst_on_response parses SSE data lines', function()
        local req_id = 0
        instruct.inst_reqs[req_id] = {
            id = req_id,
            bufnr = bufnr,
            range = { 2, 3 },
            status = 'proc',
            result = '',
            inst = 'test',
            inst_prev = {},
            job = nil,
            n_gen = 0,
            extmark = -1,
            extmark_virt = -1,
        }

        local lines = {
            'data: {"choices":[{"delta":{"content":"hello "}}]}',
            'data: {"choices":[{"delta":{"content":"world"}}]}',
        }

        instruct.inst_on_response(req_id, lines)

        wait_for(function()
            local req = instruct.inst_reqs[req_id]
            return req and req.result == 'hello world' and req.n_gen > 0
        end)

        local req = instruct.inst_reqs[req_id]
        assert.are.same('hello world', req.result)
        assert.is_true(req.n_gen > 0)

        -- cleanup
        instruct.inst_remove(req_id)
    end)

    it('inst_on_response handles non-stream message format', function()
        local req_id = 1
        instruct.inst_reqs[req_id] = {
            id = req_id,
            bufnr = bufnr,
            range = { 2, 3 },
            status = 'proc',
            result = '',
            inst = 'test',
            inst_prev = {},
            job = nil,
            n_gen = 0,
            extmark = -1,
            extmark_virt = -1,
        }

        local lines = {
            'data: {"choices":[{"message":{"content":"done"}}]}',
        }

        instruct.inst_on_response(req_id, lines)

        wait_for(function()
            local req = instruct.inst_reqs[req_id]
            return req and req.result == 'done'
        end)

        assert.are.same('done', instruct.inst_reqs[req_id].result)

        instruct.inst_remove(req_id)
    end)

    it('inst_on_response ignores parse errors gracefully', function()
        local req_id = 2
        instruct.inst_reqs[req_id] = {
            id = req_id,
            bufnr = bufnr,
            range = { 2, 3 },
            status = 'proc',
            result = '',
            inst = 'test',
            inst_prev = {},
            job = nil,
            n_gen = 0,
            extmark = -1,
            extmark_virt = -1,
        }

        local lines = {
            'data: not-json',
        }

        -- Should not error
        assert.has_no.errors(function()
            instruct.inst_on_response(req_id, lines)
        end)

        instruct.inst_remove(req_id)
    end)
end)
