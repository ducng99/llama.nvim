local fim = require('llama.fim')
local suggestion_util = require('llama.suggestion_util')

describe('llama.fim', function()
    local bufnr

    before_each(function()
        bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            'function hello() {',
            '    console.log("hello");',
            '    // cursor here',
            '    return 42;',
            '}',
        })
    end)

    after_each(function()
        pcall(function()
            fim.fim_hide(bufnr)
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end)
    end)

    it('fim_ctx_local builds correct prefix/middle/suffix', function()
        local ctx = fim.fim_ctx_local(4, 3, {})
        assert.is_string(ctx.prefix)
        assert.is_string(ctx.middle)
        assert.is_string(ctx.suffix)
        assert.are.same('    ', ctx.middle)
        assert.is_true(#ctx.prefix > 0)
        assert.is_true(#ctx.suffix > 0)
    end)

    it('fim_ctx_local with prev appends to middle', function()
        local ctx = fim.fim_ctx_local(4, 3, { ' appended' })
        assert.are.same('    // cursor here appended', ctx.middle)
    end)

    it('fim_hide clears extmarks', function()
        fim.fim_hide(bufnr)
        local ns = vim.api.nvim_create_namespace('llama_fim')
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
        assert.are.same({}, marks)
    end)

    local function wait_for_lines(bufnr, start_row, end_row, expected)
        local ok = vim.wait(500, function()
            local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, false)
            if #lines ~= #expected then
                return false
            end
            for i = 1, #expected do
                if lines[i] ~= expected[i] then
                    return false
                end
            end
            return true
        end)
        assert.is_true(ok, 'timed out waiting for buffer lines to update')
    end

    it('fim_accept full inserts text', function()
        local ctx = fim.get_ctx(bufnr)
        ctx.fim_data = {
            pos_x = 18,
            pos_y = 3,
            line_cur = '    // cursor here',
            can_accept = true,
            content = { ' world', '    // done' },
        }
        ctx.hint_shown = true

        fim.fim_accept('full', bufnr)

        wait_for_lines(bufnr, 2, 4, { '    // cursor here world', '    // done' })
    end)

    it('fim_accept line inserts first line only', function()
        local ctx = fim.get_ctx(bufnr)
        ctx.fim_data = {
            pos_x = 18,
            pos_y = 3,
            line_cur = '    // cursor here',
            can_accept = true,
            content = { ' world', '    // done' },
        }
        ctx.hint_shown = true

        fim.fim_accept('line', bufnr)

        wait_for_lines(bufnr, 2, 4, { '    // cursor here world', '    return 42;' })
    end)

    it('fim_accept word inserts first word', function()
        local ctx = fim.get_ctx(bufnr)
        ctx.fim_data = {
            pos_x = 18,
            pos_y = 3,
            line_cur = '    // cursor here',
            can_accept = true,
            content = { ' hello world' },
        }
        ctx.hint_shown = true

        fim.fim_accept('word', bufnr)

        wait_for_lines(bufnr, 2, 3, { '    // cursor here hello' })
    end)

    it('fim_accept word at end of line accepts into next line', function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            'function hello() {',
            '    console.log("hello");',
            '    // cursor here',
            '    return 42;',
            '}',
        })
        local ctx = fim.get_ctx(bufnr)
        ctx.fim_data = {
            pos_x = 18,
            pos_y = 3,
            line_cur = '    // cursor here',
            can_accept = true,
            content = { '', '    next_line more', '}' },
        }
        ctx.hint_shown = true

        fim.fim_accept('word', bufnr)

        wait_for_lines(bufnr, 2, 6, {
            '    // cursor here',
            '    next_line',
            '    return 42;',
            '}',
        })
        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.are.same({ 4, 12 }, cursor)
    end)

    it('fim_accept word at end of line with empty lines before word', function()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
            'function hello() {',
            '    console.log("hello");',
            '    // cursor here',
            '    return 42;',
            '}', }
        )
        local ctx = fim.get_ctx(bufnr)
        ctx.fim_data = {
            pos_x = 18,
            pos_y = 3,
            line_cur = '    // cursor here',
            can_accept = true,
            content = { '', '', '    hello world' },
        }
        ctx.hint_shown = true

        fim.fim_accept('word', bufnr)

        wait_for_lines(bufnr, 2, 7, {
            '    // cursor here',
            '',
            '    hello',
            '    return 42;',
            '}',
        })
        local cursor = vim.api.nvim_win_get_cursor(0)
        assert.are.same({ 5, 8 }, cursor)
    end)

    it('on_move hides hint and updates timestamp', function()
        local ctx = fim.get_ctx(bufnr)
        ctx.fim_data = {
            pos_x = 0,
            pos_y = 1,
            line_cur = 'function hello() {',
            can_accept = false,
            content = { '' },
        }
        ctx.hint_shown = true
        fim.on_move()
        assert.is_false(ctx.hint_shown)
    end)

    it('per-buffer state is isolated', function()
        local ctx1 = fim.get_ctx(bufnr)
        ctx1.hint_shown = true

        local bufnr2 = vim.api.nvim_create_buf(false, true)
        local ctx2 = fim.get_ctx(bufnr2)
        assert.is_false(ctx2.hint_shown)

        pcall(function()
            vim.api.nvim_buf_delete(bufnr2, { force = true })
        end)
    end)

    it('cleanup_buffer resets state', function()
        local ctx = fim.get_ctx(bufnr)
        ctx.hint_shown = true
        ctx.current_job = nil
        fim.cleanup_buffer(bufnr)
        local new_ctx = fim.get_ctx(bufnr)
        assert.is_false(new_ctx.hint_shown)
    end)

    it('is_fim_hint_shown works with bufnr', function()
        local ctx = fim.get_ctx(bufnr)
        ctx.hint_shown = true
        assert.is_true(fim.is_fim_hint_shown(bufnr))
        fim.fim_hide(bufnr)
        assert.is_false(fim.is_fim_hint_shown(bufnr))
    end)

    it('fim_on_response rejects error responses', function()
        local cache = require('llama.cache')
        local hash = vim.fn.sha256('prefix middle \xce suffix')
        local hashes = { hash }

        -- Error response without content
        fim.fim_on_response(hashes, { '{"error": {"message": "test error"}}' })
        vim.wait(100)
        assert.is_nil(cache.get(hash))

        -- Response with null content
        fim.fim_on_response(hashes, { '{"content": null}' })
        vim.wait(100)
        assert.is_nil(cache.get(hash))

        -- Response with missing content field
        fim.fim_on_response(hashes, { '{"timings": {}}' })
        vim.wait(100)
        assert.is_nil(cache.get(hash))

        -- Response with whitespace-only content
        fim.fim_on_response(hashes, { '{"content": " \\n"}' })
        vim.wait(100)
        assert.is_nil(cache.get(hash))
    end)

    it('fim_on_response caches valid responses', function()
        local cache = require('llama.cache')
        local hash = vim.fn.sha256('prefix middle \xce suffix')
        local hashes = { hash }

        fim.fim_on_response(hashes, { '{"content": "hello world"}' })
        vim.wait(100)

        assert.is_not_nil(cache.get(hash))
    end)
end)

describe('llama.suggestion_util', function()
    it('remove_common_suffix removes trailing match', function()
        assert.are.same('hello', suggestion_util.remove_common_suffix('world', 'helloworld'))
    end)

    it('remove_common_suffix returns suggestion when no match', function()
        assert.are.same('abcdef', suggestion_util.remove_common_suffix('xyz', 'abcdef'))
    end)

    it('remove_common_suffix returns suggestion when str is empty', function()
        assert.are.same('hello', suggestion_util.remove_common_suffix('', 'hello'))
    end)

    it('remove_common_suffix returns suggestion when suggestion is empty', function()
        assert.are.same('', suggestion_util.remove_common_suffix('hello', ''))
    end)

    it('get_display_adjustments handles empty typed', function()
        local display, outdent = suggestion_util.get_display_adjustments('world', 0, 1, 'hello')
        assert.are.same('world', display)
        assert.are.same(0, outdent)
    end)

    it('get_display_adjustments handles whitespace-only typed', function()
        local display, outdent = suggestion_util.get_display_adjustments('  foo', 0, 3, '  hello')
        assert.are.same('foo', display)
        assert.are.same(0, outdent)
    end)

    it('get_display_adjustments handles typed matching prefix', function()
        local display, outdent = suggestion_util.get_display_adjustments('world', 5, 6, 'helloworld')
        assert.are.same('world', display)
        assert.are.same(0, outdent)
    end)

    it('get_display_adjustments returns suggestion suffix when no prefix match', function()
        local display, outdent = suggestion_util.get_display_adjustments('xyz', 5, 6, 'helloworld')
        assert.are.same('xyz', display)
        assert.are.same(0, outdent)
    end)

    it('discard_repeating_suggestions removes exact suffix match', function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            'function hello() {',
            '    console.log("hello");',
            '    // cursor here',
            '    return 42;',
            '}',
        })
        local content = suggestion_util.discard_repeating_suggestions(
            { '' }, '    // cursor here', ';', 3
        )
        assert.are.same({ '' }, content)
    end)

    it('discard_repeating_suggestions keeps non-repeating content', function()
        local content = suggestion_util.discard_repeating_suggestions(
            { ' unique' }, '    // cursor here', '', 3
        )
        assert.are.same({ ' unique' }, content)
    end)
end)