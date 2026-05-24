local suggestion_util = require('llama.suggestion_util')
local keymaps = require('llama.keymaps')

local M = {}

local ns_fim = vim.api.nvim_create_namespace('llama_fim')

local state = {}

function M.get_ctx(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not state[bufnr] then
        state[bufnr] = {
            hint_shown = false,
            fim_data = {},
            current_job = nil,
            debounce_timer = nil,
            last_move_time = vim.fn.reltime(),
            indent_last = -1,
        }
    end
    return state[bufnr]
end

local function get_indent(str)
    local count = 0
    for i = 1, #str do
        local c = str:sub(i, i)
        if c == '\t' then
            count = count + vim.o.tabstop
        elseif c == ' ' then
            count = count + 1
        else
            break
        end
    end
    return count
end

function M.fim_ctx_local(pos_x, pos_y, prev)
    prev = prev or {}
    local max_y = vim.api.nvim_buf_line_count(0)
    local line_cur
    local line_cur_prefix
    local line_cur_suffix
    local lines_prefix = {}
    local lines_suffix = {}
    local indent

    local ctx_state = M.get_ctx()

    if #prev == 0 then
        line_cur = vim.api.nvim_buf_get_lines(0, pos_y - 1, pos_y, false)[1] or ''
        line_cur_prefix = string.sub(line_cur, 1, pos_x)
        line_cur_suffix = string.sub(line_cur, pos_x + 1)

        local p_start = math.max(1, pos_y - require('llama.config').get().n_prefix)
        local p_end = pos_y - 1
        if p_end >= p_start then
            lines_prefix = vim.api.nvim_buf_get_lines(0, p_start - 1, p_end, false)
        end

        local s_start = pos_y + 1
        local s_end = math.min(max_y, pos_y + require('llama.config').get().n_suffix)
        if s_end >= s_start then
            lines_suffix = vim.api.nvim_buf_get_lines(0, s_start - 1, s_end, false)
        end

        if line_cur:match('^%s*$') then
            indent = 0
            line_cur_prefix = ''
            line_cur_suffix = ''
        else
            indent = #(line_cur:match('^%s*') or '')
        end
    else
        if #prev == 1 then
            line_cur = (vim.api.nvim_buf_get_lines(0, pos_y - 1, pos_y, false)[1] or '') .. prev[1]
        else
            line_cur = prev[#prev]
        end
        line_cur_prefix = line_cur
        line_cur_suffix = ''

        local p_start = math.max(1, pos_y - require('llama.config').get().n_prefix + #prev - 1)
        local p_end = pos_y - 1
        if p_end >= p_start then
            lines_prefix = vim.api.nvim_buf_get_lines(0, p_start - 1, p_end, false)
        end
        if #prev > 1 then
            local first = (vim.api.nvim_buf_get_lines(0, pos_y - 1, pos_y, false)[1] or '') .. prev[1]
            table.insert(lines_prefix, first)
            for i = 2, #prev - 1 do
                table.insert(lines_prefix, prev[i])
            end
        end

        local s_start = pos_y + 1
        local s_end = math.min(max_y, pos_y + require('llama.config').get().n_suffix)
        if s_end >= s_start then
            lines_suffix = vim.api.nvim_buf_get_lines(0, s_start - 1, s_end, false)
        end

        indent = ctx_state.indent_last
    end

    return {
        prefix = table.concat(lines_prefix, '\n') .. (#lines_prefix > 0 and '\n' or ''),
        middle = line_cur_prefix,
        suffix = line_cur_suffix .. (#lines_suffix > 0 and '\n' or '') .. table.concat(lines_suffix, '\n') .. '\n',
        indent = indent,
        line_cur = line_cur,
        line_cur_prefix = line_cur_prefix,
        line_cur_suffix = line_cur_suffix,
    }
end

local function cancel_inflight_job(ctx)
    if ctx.current_job then
        require('llama.http').stop_job(ctx.current_job)
        ctx.current_job = nil
    end
end

local function stop_timer(ctx)
    if ctx.debounce_timer then
        ctx.debounce_timer:stop()
        ctx.debounce_timer:close()
        ctx.debounce_timer = nil
    end
end

function M.schedule_fim(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)

    cancel_inflight_job(ctx)
    stop_timer(ctx)

    local cfg = require('llama.config').get()

    ctx.debounce_timer = vim.uv.new_timer()
    ctx.debounce_timer:start(cfg.debounce, 0, function()
        vim.schedule(function()
            M.trigger_fim(bufnr)
        end)
    end)
end

function M.trigger_fim(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    if vim.api.nvim_get_current_buf() ~= bufnr then
        return
    end

    local mode = vim.fn.mode()
    if not (mode:match('^i') or mode:match('^ic') or mode:match('^ix')) then
        return
    end

    M.do_fim(-1, -1, true, {}, true)
end

function M.fim_inline(is_auto, use_cache)
    local init = require('llama.init')
    if not init.is_enabled() then
        return ''
    end

    local bufnr = vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)

    if ctx.hint_shown and not is_auto then
        M.fim_hide(bufnr)
        return ''
    end

    M.do_fim(-1, -1, is_auto, {}, use_cache)
    return ''
end

function M.do_fim(pos_x, pos_y, is_auto, prev, use_cache)
    local cfg = require('llama.config').get()
    local bufnr = vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)

    pos_x = pos_x >= 0 and pos_x or (vim.fn.col('.') - 1)
    pos_y = pos_y >= 0 and pos_y or vim.fn.line('.')

    local ctx_data = M.fim_ctx_local(pos_x, pos_y, prev)
    local prefix = ctx_data.prefix
    local middle = ctx_data.middle
    local suffix = ctx_data.suffix
    local indent = ctx_data.indent

    if is_auto and #ctx_data.line_cur_suffix > cfg.max_line_suffix then
        return
    end

    local t_max_predict_ms = cfg.t_max_predict_ms
    if #prev == 0 then
        t_max_predict_ms = 250
    end

    local hashes = {}
    table.insert(hashes, vim.fn.sha256(prefix .. middle .. '\xce' .. suffix))

    local prefix_trim = prefix
    for _ = 1, 3 do
        prefix_trim = prefix_trim:gsub('^[^\n]*\n', '', 1)
        if prefix_trim == '' then
            break
        end
        table.insert(hashes, vim.fn.sha256(prefix_trim .. middle .. '\xce' .. suffix))
    end

    if use_cache then
        for _, hash in ipairs(hashes) do
            if require('llama.cache').get(hash) ~= nil then
                return
            end
        end
    end

    ctx.indent_last = indent

    local text = vim.api.nvim_buf_get_lines(
        0,
        math.max(0, vim.fn.line('.') - math.floor(cfg.ring_chunk_size / 2) - 1),
        math.min(vim.api.nvim_buf_line_count(0), vim.fn.line('.') + math.floor(cfg.ring_chunk_size / 2)),
        false
    )

    local l0 = math.random(0, math.max(0, #text - math.floor(cfg.ring_chunk_size / 2)))
    local l1 = math.min(l0 + math.floor(cfg.ring_chunk_size / 2), #text)
    local chunk = {}
    for i = l0 + 1, l1 do
        table.insert(chunk, text[i])
    end

    require('llama.ring').evict_similar_to_current(chunk)

    local extra = require('llama.ring').get_extra()

    local request = {
        id_slot = 0,
        input_prefix = prefix,
        input_suffix = suffix,
        input_extra = extra,
        prompt = middle,
        n_predict = cfg.n_predict,
        stop = cfg.stop_strings,
        n_indent = indent,
        top_k = 40,
        top_p = 0.90,
        samplers = { 'top_k', 'top_p', 'infill' },
        stream = false,
        cache_prompt = true,
        t_max_prompt_ms = cfg.t_max_prompt_ms,
        t_max_predict_ms = t_max_predict_ms,
        response_fields = {
            'content',
            'timings/prompt_n',
            'timings/prompt_ms',
            'timings/prompt_per_token_ms',
            'timings/prompt_per_second',
            'timings/predicted_n',
            'timings/predicted_ms',
            'timings/predicted_per_token_ms',
            'timings/predicted_per_second',
            'truncated',
            'tokens_cached',
        },
    }

    if ctx.current_job then
        require('llama.http').stop_job(ctx.current_job)
    end

    ctx.current_job = require('llama.http').send_fim(request, function(_, data, _)
        M.fim_on_response(hashes, data)
    end, function(_, code, was_killed)
        M.fim_on_exit(code, was_killed)
    end)

    local delta_y = math.abs(pos_y - require('llama.ring').get_pos_y_pick())
    if is_auto and delta_y > 32 then
        local max_y = vim.api.nvim_buf_line_count(0)
        require('llama.ring').pick_chunk(
            vim.api.nvim_buf_get_lines(0, math.max(0, pos_y - cfg.ring_scope - 1), math.max(0, pos_y - cfg.n_prefix - 1), false),
            false, false
        )
        require('llama.ring').pick_chunk(
            vim.api.nvim_buf_get_lines(0, math.min(max_y - 1, pos_y + cfg.n_suffix - 1), math.min(max_y - 1, pos_y + cfg.n_suffix + cfg.ring_chunk_size - 1), false),
            false, false
        )
        require('llama.ring').set_pos_y_pick(pos_y)
    end
end

function M.fim(pos_x, pos_y, is_auto, prev, use_cache)
    M.do_fim(pos_x, pos_y, is_auto, prev, use_cache)
end

function M.fim_on_response(hashes, data)
    vim.schedule(function()
        local raw = table.concat(data, '\n')
        if #raw == 0 then
            return
        end

        if not raw:match('^%s*{') or not raw:match('"content"') then
            return
        end

        local ok, response = pcall(vim.fn.json_decode, raw)
        if not ok or not response then
            return
        end

        for _, hash in ipairs(hashes) do
            require('llama.cache').insert(hash, raw)
        end

        local bufnr = vim.api.nvim_get_current_buf()
        local ctx = M.get_ctx(bufnr)

        if not ctx.hint_shown or not ctx.fim_data.can_accept then
            require('llama.debug').log('fim_on_response', vim.fn.json_decode(raw).content or '')

            local pos_x = vim.fn.col('.') - 1
            local pos_y = vim.fn.line('.')
            M.fim_try_hint(pos_x, pos_y)
        end
    end)
end

function M.fim_on_exit(exit_code, was_killed)
    vim.schedule(function()
        -- exit code 143 = killed by SIGTERM (15), which is expected when cancelling in-flight jobs
        -- was_killed is set when stop_job is called, covering Windows where killed processes exit with code 1
        if not was_killed and exit_code ~= 0 and exit_code ~= 143 then
            vim.notify('FIM job failed with exit code: ' .. exit_code, vim.log.levels.ERROR)
        end
        local bufnr = vim.api.nvim_get_current_buf()
        local ctx = M.get_ctx(bufnr)
        ctx.current_job = nil
    end)
end

function M.on_move()
    local bufnr = vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)
    ctx.last_move_time = vim.fn.reltime()
    M.fim_hide(bufnr)
    local pos_x = vim.fn.col('.') - 1
    local pos_y = vim.fn.line('.')
    M.fim_try_hint(pos_x, pos_y)
end

function M.fim_try_hint(pos_x, pos_y)
    local mode = vim.fn.mode()
    if not (mode:match('^i') or mode:match('^ic') or mode:match('^ix')) then
        return
    end

    local ctx_data = M.fim_ctx_local(pos_x, pos_y, {})
    local prefix = ctx_data.prefix
    local middle = ctx_data.middle
    local suffix = ctx_data.suffix

    local hash = vim.fn.sha256(prefix .. middle .. '\xce' .. suffix)
    local raw = require('llama.cache').get(hash)

    if not raw then
        local pm = prefix .. middle
        local best = 0
        for i = 0, 127 do
            if #pm < (1 + i) then
                break
            end
            local removed = string.sub(pm, -(1 + i))
            local ctx_new = string.sub(pm, 1, -(2 + i)) .. '\xce' .. suffix
            local hash_new = vim.fn.sha256(ctx_new)
            local cached = require('llama.cache').get(hash_new)
            if cached and cached ~= '' then
                local ok, response_cached = pcall(vim.fn.json_decode, cached)
                if ok and response_cached and response_cached.content then
                    local expected = string.sub(response_cached.content, 1, i + 1)
                    if expected == removed then
                        response_cached.content = string.sub(response_cached.content, i + 2)
                        if #response_cached.content > 0 then
                            if not raw or #response_cached.content > best then
                                best = #response_cached.content
                                raw = vim.fn.json_encode(response_cached)
                            end
                        end
                    end
                end
            end
        end
    end

    if raw then
        M.fim_render(pos_x, pos_y, raw)
        local bufnr = vim.api.nvim_get_current_buf()
        local ctx = M.get_ctx(bufnr)
        if ctx.hint_shown then
            M.do_fim(pos_x, pos_y, true, ctx.fim_data.content, true)
        end
    end
end

function M.fim_render(pos_x, pos_y, raw)
    if vim.fn.pumvisible() == 1 then
        return
    end

    local cfg = require('llama.config').get()
    local bufnr = vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)
    local can_accept = true
    local has_info = false

    local n_prompt = 0
    local t_prompt_ms = 1.0
    local s_prompt = 0
    local n_predict = 0
    local t_predict_ms = 1.0
    local s_predict = 0
    local content = {}

    local ok, response = pcall(vim.fn.json_decode, raw)
    if ok and response then
        for part in (response.content or ''):gmatch('([^\n]*)\n?') do
            table.insert(content, part)
        end
        if content[#content] == '' then
            table.remove(content)
        end

        while #content > 0 and content[#content] == '' do
            table.remove(content)
        end

        local truncated = response['timings/truncated'] or false

        if response['timings/prompt_n'] and response['timings/prompt_ms'] and response['timings/predicted_n'] then
            n_prompt = response['timings/prompt_n'] or 0
            t_prompt_ms = tonumber(response['timings/prompt_ms']) or 1.0
            s_prompt = tonumber(response['timings/prompt_per_second']) or 0.0
            n_predict = response['timings/predicted_n'] or 0
            t_predict_ms = tonumber(response['timings/predicted_ms']) or 1.0
            s_predict = tonumber(response['timings/predicted_per_second']) or 0.0
            has_info = true
        end
    end

    if #content == 0 then
        table.insert(content, '')
        can_accept = false
    end

    local line_cur = vim.api.nvim_buf_get_lines(0, pos_y - 1, pos_y, false)[1] or ''

    if line_cur:match('^%s*$') then
        local lead = math.min(#(content[1]:match('^%s*') or ''), #line_cur)
        line_cur = string.sub(content[1], 1, lead)
        content[1] = string.sub(content[1], lead + 1)
    end

    local line_cur_prefix = string.sub(line_cur, 1, pos_x)
    local line_cur_suffix = string.sub(line_cur, pos_x + 1)

    content = suggestion_util.discard_repeating_suggestions(content, line_cur_prefix, line_cur_suffix, pos_y)

    content[#content] = content[#content] .. line_cur_suffix

    if table.concat(content, '\n'):match('^%s*$') then
        can_accept = false
    end

    local display_first_line = content[1]
    if #content == 1 then
        display_first_line = suggestion_util.remove_common_suffix(line_cur_suffix, display_first_line)
    end

    local has_multiline = #content > 1 or (display_first_line:find('%c') ~= nil)
    local first_line_display, _ = suggestion_util.get_display_adjustments(
        display_first_line, pos_x, pos_x + 1, line_cur
    )
    if first_line_display == '' then
        first_line_display = display_first_line
    end

    local info = ''
    if cfg.show_info > 0 and has_info then
        local info_prefix = '   '
        local ring = require('llama.ring')
        local cache = require('llama.cache')

        if truncated then
            info = string.format(
                '%s | WARNING: the context is full: %d, increase the server context size or reduce ring_n_chunks',
                cfg.show_info == 2 and info_prefix or 'llama.vim',
                response.tokens_cached or 0
            )
        else
            info = string.format(
                '%s | c: %d, r: %d/%d, e: %d, q: %d/16, C: %d/%d | p: %d (%.2f ms, %.2f t/s) | g: %d (%.2f ms, %.2f t/s)',
                cfg.show_info == 2 and info_prefix or 'llama.vim',
                response.tokens_cached or 0,
                ring.n_chunks(), cfg.ring_n_chunks,
                ring.n_evict(), ring.n_queued(),
                cache.count(), cfg.max_cache_keys,
                n_prompt, t_prompt_ms, s_prompt,
                n_predict, t_predict_ms, s_predict
            )
        end

        if cfg.show_info == 1 then
            vim.o.statusline = info
            info = ''
        end
    end

    vim.api.nvim_buf_clear_namespace(bufnr, ns_fim, 0, -1)

    local vt_pos = (#content == 1 and content[1] == '') and 'eol' or (has_multiline and 'eol' or 'inline')
    local extmark_opts = {
        virt_text = { { first_line_display, 'llama_hl_fim_hint' }, { info, 'llama_hl_fim_info' } },
        virt_text_pos = vt_pos,
    }
    if vt_pos == 'eol' and #content > 1 then
        extmark_opts.virt_text_win_col = vim.fn.virtcol('.') - 1
    end
    if vt_pos == 'inline' then
        extmark_opts.hl_mode = 'replace'
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_fim, pos_y - 1, pos_x, extmark_opts)

    local virt_lines = {}
    for i = 2, #content do
        table.insert(virt_lines, { { content[i], 'llama_hl_fim_hint' } })
    end
    if #virt_lines > 0 then
        vim.api.nvim_buf_set_extmark(bufnr, ns_fim, pos_y - 1, 0, {
            virt_lines = virt_lines,
        })
    end

    M.setup_accept_keymaps(bufnr)

    ctx.hint_shown = true
    ctx.fim_data = {
        pos_x = pos_x,
        pos_y = pos_y,
        line_cur = line_cur,
        can_accept = can_accept,
        content = vim.deepcopy(content),
    }
end

function M.setup_accept_keymaps(bufnr)
    local cfg = require('llama.config').get()

    local function accept_action(accept_type)
        local ctx = M.get_ctx(bufnr)
        if ctx.hint_shown and ctx.fim_data.can_accept then
            M.fim_accept(accept_type, bufnr)
            return true
        end
        return false
    end

    if cfg.keymap_fim_accept_full ~= '' then
        keymaps.register_keymap_with_passthrough('i', cfg.keymap_fim_accept_full, function()
            return accept_action('full')
        end, '[llama] accept suggestion (full)', bufnr)
    end
    if cfg.keymap_fim_accept_line ~= '' then
        keymaps.register_keymap_with_passthrough('i', cfg.keymap_fim_accept_line, function()
            return accept_action('line')
        end, '[llama] accept suggestion (line)', bufnr)
    end
    if cfg.keymap_fim_accept_word ~= '' then
        keymaps.register_keymap_with_passthrough('i', cfg.keymap_fim_accept_word, function()
            return accept_action('word')
        end, '[llama] accept suggestion (word)', bufnr)
    end
end

function M.fim_accept(accept_type, bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)
    local pos_x = ctx.fim_data.pos_x
    local pos_y = ctx.fim_data.pos_y
    local line_cur = ctx.fim_data.line_cur
    local can_accept = ctx.fim_data.can_accept
    local content = ctx.fim_data.content

    M.fim_hide(bufnr)

    if can_accept and #content > 0 then
        vim.schedule(function()
            local current_bufnr = vim.api.nvim_get_current_buf()
            if current_bufnr ~= bufnr then
                return
            end

            vim.cmd('let &undolevels = &undolevels')

            local suffix = line_cur:sub(pos_x + 1)
            local word = nil
            local word_line_idx = 0

            if accept_type == 'word' then
                local first_line_suggestion = content[1]
                if #content == 1 then
                    first_line_suggestion = first_line_suggestion:sub(1, #first_line_suggestion - #suffix)
                end
                word = first_line_suggestion:match('^%s*%S+')

                if not word and #content > 1 then
                    for i = 2, #content do
                        word = content[i]:match('^%s*%S+')
                        if word then
                            word_line_idx = i
                            break
                        end
                    end
                end
            end

            if accept_type ~= 'word' then
                vim.api.nvim_buf_set_lines(current_bufnr, pos_y - 1, pos_y, false, {
                    line_cur:sub(1, pos_x) .. content[1]
                })
            else
                if word then
                    if word_line_idx == 0 then
                        vim.api.nvim_buf_set_lines(current_bufnr, pos_y - 1, pos_y, false, {
                            line_cur:sub(1, pos_x) .. word .. suffix
                        })
                    else
                        local new_lines = {}
                        for i = 2, word_line_idx - 1 do
                            table.insert(new_lines, content[i])
                        end
                        table.insert(new_lines, word)

                        vim.api.nvim_buf_set_lines(current_bufnr, pos_y - 1, pos_y, false, {
                            line_cur:sub(1, pos_x) .. content[1] .. suffix
                        })
                        vim.api.nvim_buf_set_lines(current_bufnr, pos_y, pos_y, false, new_lines)
                    end
                elseif #content > 1 then
                    vim.api.nvim_buf_set_lines(current_bufnr, pos_y - 1, pos_y, false, {
                        line_cur:sub(1, pos_x) .. content[1] .. suffix
                    })
                else
                    vim.api.nvim_buf_set_lines(current_bufnr, pos_y - 1, pos_y, false, {
                        line_cur:sub(1, pos_x) .. suffix
                    })
                end
            end

            if #content > 1 and accept_type == 'full' then
                local new_lines = {}
                for i = 2, #content do
                    table.insert(new_lines, content[i])
                end
                vim.api.nvim_buf_set_lines(current_bufnr, pos_y, pos_y, false, new_lines)
            end

            if accept_type == 'word' then
                if word then
                    if word_line_idx == 0 then
                        vim.api.nvim_win_set_cursor(0, { pos_y, pos_x + #word })
                    else
                        vim.api.nvim_win_set_cursor(0, { pos_y + word_line_idx - 1, #word })
                    end
                elseif #content > 1 then
                    vim.api.nvim_win_set_cursor(0, { pos_y, pos_x + #content[1] })
                    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
                else
                    vim.api.nvim_win_set_cursor(0, { pos_y, pos_x })
                end
            elseif accept_type == 'line' or #content == 1 then
                vim.api.nvim_win_set_cursor(0, { pos_y, pos_x + #content[1] })
                if #content > 1 then
                    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
                end
            else
                vim.api.nvim_win_set_cursor(0, { pos_y + #content - 1, #content[#content] })
            end

            local should_schedule = false
            if accept_type == 'full' then
                should_schedule = true
            elseif accept_type == 'line' and #content == 1 then
                should_schedule = true
            elseif accept_type == 'word' then
                if #content == 1 then
                    local first_line_suggestion = content[1]
                    first_line_suggestion = first_line_suggestion:sub(1, #first_line_suggestion - #suffix)
                    if word and word == first_line_suggestion then
                        should_schedule = true
                    end
                elseif word_line_idx > 0 then
                    if word_line_idx == #content and word == content[word_line_idx] then
                        should_schedule = true
                    end
                end
            end

            if should_schedule then
                M.schedule_fim(current_bufnr)
            end
        end)
    end
end

function M.fim_hide(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)

    ctx.hint_shown = false
    vim.api.nvim_buf_clear_namespace(bufnr, ns_fim, 0, -1)

    local cfg = require('llama.config').get()
    if cfg.show_info == 1 then
        vim.o.statusline = ''
    end

    keymaps.clear_buffer_keymaps(bufnr)
end

function M.is_fim_hint_shown(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local ctx = M.get_ctx(bufnr)
    return ctx.hint_shown
end

function M.cleanup_buffer(bufnr)
    local ctx = M.get_ctx(bufnr)
    cancel_inflight_job(ctx)
    stop_timer(ctx)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_fim, 0, -1)
    keymaps.clear_buffer_keymaps(bufnr)
    state[bufnr] = nil
end

-- Backward compatibility: expose per-buffer state via module fields
-- so ring.lua can still reference require('llama.fim').t_last_move
setmetatable(M, {
    __index = function(_, key)
        if key == 'fim_hint_shown' then
            return M.get_ctx().hint_shown
        elseif key == 'fim_data' then
            return M.get_ctx().fim_data
        elseif key == 'current_job_fim' then
            return M.get_ctx().current_job
        elseif key == 't_last_move' then
            return M.get_ctx().last_move_time
        elseif key == 'indent_last' then
            return M.get_ctx().indent_last
        end
        return nil
    end,
    __newindex = function(_, key, value)
        local bufnr = vim.api.nvim_get_current_buf()
        local ctx = M.get_ctx(bufnr)
        if key == 'fim_hint_shown' then
            ctx.hint_shown = value
        elseif key == 'fim_data' then
            ctx.fim_data = value
        elseif key == 'current_job_fim' then
            ctx.current_job = value
        elseif key == 't_last_move' then
            ctx.last_move_time = value
        elseif key == 'indent_last' then
            ctx.indent_last = value
        end
    end,
})

return M