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
      '}',
    })
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

  it('fim_accept full with single-line suggestion that overlaps suffix does not duplicate suffix chars', function()
    -- Buffer: '    return x;', cursor after 'x' (pos_x = 12)
    -- suffix = ';' (the semicolon after x)
    -- Model generates ' = 1;' which already ends with ';' (overlap with suffix)
    -- After fix: content stored = ' = 1;' (overlap removed before appending suffix)
    --             wait — content[1] should be ' = 1;' (overlap removed: ' = 1' + ';' suffix)
    -- Acceptance result should be '    return x = 1;' — no duplicate semicolon
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      'function hello() {',
      '    console.log("hello");',
      '    return x;',
      '}',
    })
    local ctx = fim.get_ctx(bufnr)
    ctx.fim_data = {
      pos_x = 12,
      pos_y = 3,
      line_cur = '    return x;',
      can_accept = true,
      content = { ' = 1;' },
    }
    ctx.hint_shown = true

    fim.fim_accept('full', bufnr)

    wait_for_lines(bufnr, 2, 3, { '    return x = 1;' })
  end)

  it('fim_accept line with single-line suggestion that overlaps suffix does not duplicate suffix chars', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '    return x;',
    })
    local ctx = fim.get_ctx(bufnr)
    ctx.fim_data = {
      pos_x = 12,
      pos_y = 1,
      line_cur = '    return x;',
      can_accept = true,
      content = { ' = 1;' },
    }
    ctx.hint_shown = true

    fim.fim_accept('line', bufnr)

    wait_for_lines(bufnr, 0, 1, { '    return x = 1;' })
  end)

  it('fim_accept full with multi-line suggestion where last line overlaps suffix does not duplicate suffix chars', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      'function foo() {',
      '    return x;',
      '}',
    })
    local ctx = fim.get_ctx(bufnr)
    ctx.fim_data = {
      pos_x = 12,
      pos_y = 2,
      line_cur = '    return x;',
      can_accept = true,
      content = { ' = 1', '    return y;' },
    }
    ctx.hint_shown = true

    fim.fim_accept('full', bufnr)

    wait_for_lines(bufnr, 1, 4, {
      '    return x = 1',
      '    return y;',
      '}',
    })
  end)

  it('fim_accept word with single-line suggestion that overlaps suffix does not duplicate suffix chars', function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '    return x;',
    })
    local ctx = fim.get_ctx(bufnr)
    ctx.fim_data = {
      pos_x = 12,
      pos_y = 1,
      line_cur = '    return x;',
      can_accept = true,
      content = { ' value;' },
    }
    ctx.hint_shown = true

    fim.fim_accept('word', bufnr)

    wait_for_lines(bufnr, 0, 1, { '    return x value;' })
  end)

  it('fim_render stores content without duplicate suffix chars for single-line suggestion', function()
    -- Simulate the relevant parts of fim_render: the model outputs ' = 1;'
    -- and suffix is ';'. After our fix, content[#content] = remove_common_suffix(';', ' = 1;') .. ';'
    -- which equals ' = 1' .. ';' = ' = 1;' (overlap removed, no duplicate).
    local line_cur_suffix = ';'
    local content = { ' = 1;' }
    content[#content] = suggestion_util.remove_common_suffix(line_cur_suffix, content[#content]) .. line_cur_suffix
    -- Verify no duplicate ';;' at the end
    assert.are.same(' = 1;', content[1])
    assert.is_nil(content[1]:match(';;$'))
  end)

  it('fim_render stores content without duplicate suffix chars for multi-line suggestion', function()
    local line_cur_suffix = ';'
    local content = { ' = 1', '    return y;' }
    content[#content] = suggestion_util.remove_common_suffix(line_cur_suffix, content[#content]) .. line_cur_suffix
    -- Last line should be '    return y;' (overlap removed), no ';;' at end
    assert.are.same('    return y;', content[#content])
    assert.is_nil(content[#content]:match(';;$'))
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
    local content = suggestion_util.discard_repeating_suggestions({ '' }, '    // cursor here', ';', 3)
    assert.are.same({ '' }, content)
  end)

  it('discard_repeating_suggestions keeps non-repeating content', function()
    local content = suggestion_util.discard_repeating_suggestions({ ' unique' }, '    // cursor here', '', 3)
    assert.are.same({ ' unique' }, content)
  end)

  describe('build_completion_prompt', function()
    local fim_cfg = {
      prefix = '<PRE>',
      suffix = '<SUF>',
      middle = '<MID>',
      repo_name = '<REPO>',
      file_sep = '<SEP>',
      format = 'psm',
    }

    it('builds repo header and relative file names from extra chunks', function()
      local extra = {
        { text = 'chunk A\n', filename = '/home/u/proj/src/a.lua' },
        { text = 'chunk B\n', filename = '/home/u/proj/lib/b.lua' },
      }
      local prompt = fim.build_completion_prompt(fim_cfg, 'pre', 'mid', 'suf', extra, '/home/u/proj/src/c.lua')
      assert.are.same('<REPO>proj\n<SEP>src/a.lua\nchunk A\n<SEP>lib/b.lua\nchunk B\n<SEP>src/c.lua\n<PRE>pre<SUF>suf<MID>mid', prompt)
    end)

    it('falls back to base names when paths share no directory', function()
      local extra = { { text = 'x\n', filename = '/other/place/x.lua' } }
      local prompt = fim.build_completion_prompt(fim_cfg, '', '', '', extra, '/somewhere/else/main.lua')
      assert.are.same('<SEP>x.lua\nx\n<SEP>main.lua\n<PRE><SUF><MID>', prompt)
    end)

    it('uses base name when the current file sits directly in the repo dir', function()
      local prompt = fim.build_completion_prompt(fim_cfg, 'p', 'm', 's', {}, '/home/u/proj/main.lua')
      assert.are.same('<REPO>proj\n<SEP>main.lua\n<PRE>p<SUF>s<MID>m', prompt)
    end)

    it('omits repo token when no file name is available', function()
      local prompt = fim.build_completion_prompt(fim_cfg, 'p', 'm', 's', {}, '')
      assert.are.same('<SEP><PRE>p<SUF>s<MID>m', prompt)
    end)

    it('handles extra chunks without file names', function()
      local extra = { { text = 'scratch\n', filename = '' } }
      local prompt = fim.build_completion_prompt(fim_cfg, '', '', '', extra, '/home/u/proj/main.lua')
      assert.are.same('<REPO>proj\n<SEP>scratch\n<SEP>main.lua\n<PRE><SUF><MID>', prompt)
    end)

    it('respects pms and spm formats', function()
      local pms = vim.tbl_extend('force', fim_cfg, { format = 'pms' })
      assert.are.same('<REPO>proj\n<SEP>main.lua\n<PRE>p<MID>m<SUF>s', fim.build_completion_prompt(pms, 'p', 'm', 's', {}, '/w/proj/main.lua'))
      local spm = vim.tbl_extend('force', fim_cfg, { format = 'spm' })
      assert.are.same('<REPO>proj\n<SEP>main.lua\n<SUF>s<PRE>p<MID>m', fim.build_completion_prompt(spm, 'p', 'm', 's', {}, '/w/proj/main.lua'))
    end)
  end)

  describe('do_fim completion mode', function()
    local captured

    before_each(function()
      require('llama.config').setup({ fim_config = { mode = 'completion' } })
      captured = {}
      package.loaded['llama.ring'] = {
        get_extra = function()
          return { { text = 'extra body\n', filename = '/tmp/llama_test_proj/lib/util.lua' } }
        end,
        evict_similar_to_current = function() end,
        get_pos_y_pick = function()
          return 0
        end,
        pick_chunk = function() end,
        set_pos_y_pick = function() end,
      }
      package.loaded['llama.http'] = {
        send_fim = function(request)
          captured.request = request
          return 'job'
        end,
        stop_job = function() end,
      }
    end)

    after_each(function()
      package.loaded['llama.ring'] = nil
      package.loaded['llama.http'] = nil
      require('llama.config').setup({})
    end)

    it('sends prompt with repo/file names from ring extra', function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, '/tmp/llama_test_proj/src/main.lua')
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local a = 1', 'local b = ' })
      vim.api.nvim_set_current_buf(buf)

      fim.do_fim(9, 2, false, {}, false)

      assert.are.same(
        '<|repo_name|>llama_test_proj\n'
          .. '<|file_sep|>lib/util.lua\nextra body\n'
          .. '<|file_sep|>src/main.lua\n'
          .. '<|fim_prefix|>local a = 1\n<|fim_suffix|> \n<|fim_middle|>local b =',
        captured.request.prompt
      )

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
