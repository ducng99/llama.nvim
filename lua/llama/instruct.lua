local M = {}

local ns_inst = vim.api.nvim_create_namespace('llama_inst')

M.inst_reqs = {}
local inst_req_id = 0

function M.inst_build(l0, l1, inst, inst_prev)
    local cfg = require('llama.config').get()
    local prefix = {}
    local p_start = math.max(1, l0 - cfg.n_prefix)
    local p_end = l0 - 1
    if p_end >= p_start then
        prefix = vim.api.nvim_buf_get_lines(0, p_start - 1, p_end, false)
    end

    local selection = vim.api.nvim_buf_get_lines(0, l0 - 1, l1, false)

    local suffix = {}
    local s_start = l1 + 1
    local s_end = math.min(vim.api.nvim_buf_line_count(0), l1 + cfg.n_suffix)
    if s_end >= s_start then
        suffix = vim.api.nvim_buf_get_lines(0, s_start - 1, s_end, false)
    end

    local messages
    if inst_prev and #inst_prev > 0 then
        messages = vim.deepcopy(inst_prev)
    else
        local system_prompt = 'You are a text-editing assistant. Respond ONLY with the result of applying INSTRUCTION to SELECTION given the CONTEXT. Maintain the existing text indentation. Do not add extra code blocks. Respond only with the modified block. If the INSTRUCTION is a question, answer it directly. Do not output any extra separators. Consider the local context before (PREFIX) and after (SUFFIX) the SELECTION.\n'

        local extra = require('llama.ring').get_extra()
        local extra_texts = {}
        for _, chunk in ipairs(extra) do
            table.insert(extra_texts, vim.inspect(chunk))
        end

        system_prompt = system_prompt .. '\n'
        system_prompt = system_prompt .. '--- CONTEXT     ' .. string.rep('-', 40) .. '\n'
        system_prompt = system_prompt .. table.concat(extra_texts, '\n') .. '\n'
        system_prompt = system_prompt .. '--- PREFIX      ' .. string.rep('-', 40) .. '\n'
        system_prompt = system_prompt .. table.concat(prefix, '\n') .. '\n'
        system_prompt = system_prompt .. '--- SELECTION   ' .. string.rep('-', 40) .. '\n'
        system_prompt = system_prompt .. table.concat(selection, '\n') .. '\n'
        system_prompt = system_prompt .. '--- SUFFIX      ' .. string.rep('-', 40) .. '\n'
        system_prompt = system_prompt .. table.concat(suffix, '\n') .. '\n'

        messages = {
            { role = 'system', content = system_prompt },
        }
    end

    local user_content = ''
    if inst and inst ~= '' then
        user_content = 'INSTRUCTION: ' .. inst
    end

    table.insert(messages, { role = 'user', content = user_content })
    return messages
end

function M.inst(l0, l1)
    local req_id = inst_req_id
    inst_req_id = inst_req_id + 1

    -- warm-up request
    local messages = M.inst_build(l0, l1, '')
    local warm_request = {
        id_slot = req_id,
        messages = messages,
        samplers = {},
        n_predict = 0,
        stream = false,
        cache_prompt = true,
        response_fields = { '' },
    }
    require('llama.http').send_inst(warm_request, nil, nil)

    local inst_text = vim.fn.input('Instruction: ')
    if inst_text == '' then
        return
    end

    require('llama.debug').log('inst_send | ' .. inst_text)

    local bufnr = vim.api.nvim_get_current_buf()

    local req = {
        id = req_id,
        bufnr = bufnr,
        range = { l0, l1 },
        status = 'proc',
        result = '',
        inst = inst_text,
        inst_prev = {},
        job = nil,
        n_gen = 0,
        extmark = -1,
        extmark_virt = -1,
    }

    M.inst_reqs[req_id] = req

    -- highlight selected text
    local last_line = vim.api.nvim_buf_get_lines(bufnr, l1 - 1, l1, false)[1] or ''
    req.extmark = vim.api.nvim_buf_set_extmark(bufnr, ns_inst, l0 - 1, 0, {
        end_row = l1 - 1,
        end_col = #last_line,
        hl_group = 'llama_hl_inst_src',
    })

    M.inst_update(req_id, 'proc')

    req.inst_prev = M.inst_build(l0, l1, inst_text)
    M.inst_send(req_id, req.inst_prev)
end

function M.inst_send(req_id, messages)
    require('llama.debug').log('inst_send', table.concat(vim.tbl_map(function(m)
        return m.content
    end, messages), '\n'))

    local request = {
        id_slot = req_id,
        messages = messages,
        min_p = 0.1,
        temperature = 0.1,
        samplers = { 'min_p', 'temperature' },
        stream = true,
        cache_prompt = true,
    }

    local req = M.inst_reqs[req_id]

    if not req then
        return
    end

    req.job = require('llama.http').send_inst(request, function(_, data, _)
        M.inst_on_response(req_id, data)
    end, function(_, code, was_killed)
        M.inst_on_exit(req_id, code, was_killed)
    end)
end

function M.inst_update_pos(req)
    local bufnr = req.bufnr
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_inst, req.extmark, {})
    if not ok or vim.tbl_isempty(pos) then
        return
    end
    local extmark_line = pos[1] + 1
    req.range[2] = extmark_line + req.range[2] - req.range[1]
    req.range[1] = extmark_line
end

function M.inst_update(id, status)
    local req = M.inst_reqs[id]
    if not req then
        return
    end

    req.job = require('llama.http').send_inst(request, function(_, data, _)
        M.inst_on_response(req_id, data)
    end, function(_, code, was_killed)
        M.inst_on_exit(req_id, code, was_killed)
    end)
end

function M.inst_update_pos(req)
    local bufnr = req.bufnr
    local ok, pos = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_inst, req.extmark, {})
    if not ok or vim.tbl_isempty(pos) then
        return
    end
    local extmark_line = pos[1] + 1
    req.range[2] = extmark_line + req.range[2] - req.range[1]
    req.range[1] = extmark_line
end

function M.inst_update(id, status)
    local req = M.inst_reqs[id]
    if not req then
        return
    end

    req.status = status
    M.inst_update_pos(req)

    -- clear previous virt extmark
    if req.extmark_virt ~= -1 then
        pcall(vim.api.nvim_buf_del_extmark, req.bufnr, ns_inst, req.extmark_virt)
        req.extmark_virt = -1
    end

    local inst_trunc = req.inst
    if #inst_trunc > 128 then
        inst_trunc = string.sub(inst_trunc, 1, 127) .. '...'
    end

    local hl = ''
    local sep = '====================================='
    local virt_lines = {}
    local cfg = require('llama.config').get()

    if status == 'ready' then
        local result_lines = vim.split(req.result, '\n')
        hl = 'llama_hl_inst_virt_ready'
        virt_lines = { { { sep, hl } } }
        for _, line in ipairs(result_lines) do
            table.insert(virt_lines, { { line, hl } })
        end
    elseif status == 'proc' then
        hl = 'llama_hl_inst_virt_proc'
        virt_lines = {
            { { sep, hl } },
            { { string.format('Endpoint:    %s', cfg.endpoint_inst), hl } },
            { { string.format('Model:       %s', cfg.model_inst), hl } },
            { { string.format('Instruction: %s', inst_trunc), hl } },
            { { 'Processing ...', hl } },
        }
    elseif status == 'gen' then
        local preview = req.result:gsub('.*\n%s*', '')
        if #req.result == 0 then
            preview = '[thinking]'
        end
        hl = 'llama_hl_inst_virt_gen'
        virt_lines = {
            { { sep, hl } },
            { { string.format('Endpoint:    %s', cfg.endpoint_inst), hl } },
            { { string.format('Model:       %s', cfg.model_inst), hl } },
            { { string.format('Instruction: %s', inst_trunc), hl } },
            { { string.format('Generating:  %4d tokens | %s', req.n_gen, preview), hl } },
        }
    end

    if #virt_lines > 0 then
        table.insert(virt_lines, { { sep, hl } })
        req.extmark_virt = vim.api.nvim_buf_set_extmark(req.bufnr, ns_inst, req.range[2] - 1, 0, {
            virt_lines = virt_lines,
        })
    end
end

function M.inst_on_response(id, lines)
    vim.schedule(function()
        if not lines or #lines == 0 then
            return
        end

        local content = ''
        for _, line in ipairs(lines) do
            if #line > 5 and string.sub(line, 1, 6) == 'data: ' then
                line = string.sub(line, 7)
            end

            if line ~= '' and not line:match('^%s*$') then
                local ok, response = pcall(vim.fn.json_decode, line)
                if ok and response then
                    local choices = response.choices or {}
                    local choice = choices[1] or {}

                    if choice.delta and choice.delta.content then
                        local delta = choice.delta.content
                        if type(delta) == 'string' then
                            content = content .. delta
                        end
                    elseif choice.message and choice.message.content then
                        local delta = choice.message.content
                        if type(delta) == 'string' then
                            content = content .. delta
                        end
                    end
                else
                    require('llama.debug').log('inst_on_response parse error', line)
                end
            end
        end

        if not M.inst_reqs[id] then
            return
        end

        M.inst_update(id, 'gen')

        local req = M.inst_reqs[id]
        if content ~= '' then
            req.result = req.result .. content
        end
        req.n_gen = req.n_gen + 1
    end)
end

function M.inst_on_exit(id, exit_code, was_killed)
    vim.schedule(function()
        if not was_killed and exit_code ~= 0 then
            vim.notify('Instruct job failed with exit code: ' .. exit_code, vim.log.levels.ERROR)
            M.inst_remove(id)
            return
        end

        if was_killed then
            return
        end

        if not M.inst_reqs[id] then
            return
        end

        M.inst_update(id, 'ready')

        -- add assistant response to messages for continuation
        local req = M.inst_reqs[id]
        table.insert(req.inst_prev, { role = 'assistant', content = req.result })
    end)
end

function M.inst_remove(id)
    local req = M.inst_reqs[id]
    if not req then
        return
    end

    pcall(vim.api.nvim_buf_del_extmark, req.bufnr, ns_inst, req.extmark)
    if req.extmark_virt ~= -1 then
        pcall(vim.api.nvim_buf_del_extmark, req.bufnr, ns_inst, req.extmark_virt)
    end
    if req.job then
        require('llama.http').stop_job(req.job)
    end

    M.inst_reqs[id] = nil
end

function M.inst_callback(bufnr, l0, l1, result)
    local result_lines = vim.split(result, '\n', { plain = true })

    while #result_lines > 0 and result_lines[#result_lines] == '' do
        table.remove(result_lines)
    end

    vim.api.nvim_buf_set_lines(bufnr, l0 - 1, l1, false, result_lines)
end

function M.inst_accept()
    local line = vim.fn.line('.')

    for _, req in pairs(M.inst_reqs) do
        if req.status == 'ready' then
            M.inst_update_pos(req)
            if line >= req.range[1] and line <= req.range[2] then
                M.inst_remove(req.id)
                M.inst_callback(req.bufnr, req.range[1], req.range[2], req.result)
                return
            end
        end
    end

    -- If no active instruct, fallback to normal Tab
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Tab>', true, false, true), 'n', false)
end

function M.inst_cancel()
    local line = vim.fn.line('.')
    for _, req in pairs(M.inst_reqs) do
        if line >= req.range[1] and line <= req.range[2] then
            M.inst_remove(req.id)
            return
        end
    end
end

function M.inst_rerun()
    local lnum = vim.fn.line('.')
    for _, req in pairs(M.inst_reqs) do
        M.inst_update_pos(req)
        if req.status == 'ready' and lnum >= req.range[1] and lnum <= req.range[2] then
            require('llama.debug').log('inst_rerun')
            req.result = ''
            req.status = 'proc'
            req.n_gen = 0
            table.remove(req.inst_prev)
            M.inst_update(req.id, 'proc')
            M.inst_send(req.id, req.inst_prev)
            return
        end
    end
end

function M.inst_continue()
    local lnum = vim.fn.line('.')
    for _, req in pairs(M.inst_reqs) do
        M.inst_update_pos(req)
        if req.status == 'ready' and lnum >= req.range[1] and lnum <= req.range[2] then
            local inst_text = vim.fn.input('Next instruction: ')
            if inst_text == '' then
                return
            end

            require('llama.debug').log('inst_continue | ' .. inst_text)
            req.result = ''
            req.status = 'proc'
            req.inst = inst_text
            req.n_gen = 0
            M.inst_update(req.id, 'proc')
            req.inst_prev = M.inst_build(req.range[1], req.range[2], inst_text, req.inst_prev)
            M.inst_send(req.id, req.inst_prev)
            return
        end
    end
end

return M
