local M = {}

function M.remove_common_suffix(str, suggestion)
    if str == '' or suggestion == '' then
        return suggestion
    end

    local str_len = #str
    local suggestion_len = #suggestion
    local shorter_len = math.min(str_len, suggestion_len)

    local matching = 0
    for i = 1, shorter_len do
        local str_char = string.sub(str, str_len - i + 1, str_len - i + 1)
        local suggestion_char = string.sub(suggestion, suggestion_len - i + 1, suggestion_len - i + 1)

        if str_char == suggestion_char then
            matching = matching + 1
        else
            break
        end
    end

    if matching == 0 then
        return suggestion
    end

    return string.sub(suggestion, 1, suggestion_len - matching)
end

function M.get_display_adjustments(suggestion_first_line, pos_x, cursor_col, current_line)
    local prefix = string.sub(current_line, 1, pos_x)
    local choice_text = prefix .. suggestion_first_line

    local typed = string.sub(current_line, 1, cursor_col - 1)

    if typed == '' then
        return choice_text, 0
    end

    if typed:match('^%s+$') then
        local choice_ws = choice_text:match('^(%s*)') or ''
        local typed_len = #typed
        local choice_ws_len = #choice_ws

        if typed_len <= choice_ws_len then
            return string.sub(choice_text, typed_len + 1), 0
        else
            return string.sub(choice_text, choice_ws_len + 1), typed_len - choice_ws_len
        end
    end

    if string.sub(choice_text, 1, #typed) == typed then
        return string.sub(choice_text, #typed + 1), 0
    end

    return '', 0
end

function M.discard_repeating_suggestions(content, line_cur_prefix, line_cur_suffix, pos_y)
    if #content == 1 and content[1] == '' then
        return content
    end

    if #content > 1 and content[1] == '' then
        local next_lines = vim.api.nvim_buf_get_lines(0, pos_y, pos_y + #content - 1, false)
        local match = true
        for i = 1, #content - 1 do
            if not next_lines[i] or content[i + 1] ~= next_lines[i] then
                match = false
                break
            end
        end
        if match then
            return { '' }
        end
    end

    if #content == 1 and content[1] == line_cur_suffix then
        return { '' }
    end

    local cmp_y = pos_y + 1
    local max_y = vim.api.nvim_buf_line_count(0)
    while cmp_y <= max_y do
        local l = vim.api.nvim_buf_get_lines(0, cmp_y - 1, cmp_y, false)[1] or ''
        if not l:match('^%s*$') then
            break
        end
        cmp_y = cmp_y + 1
    end

    if (line_cur_prefix .. content[1]) == (vim.api.nvim_buf_get_lines(0, cmp_y - 1, cmp_y, false)[1] or '') then
        if #content == 1 then
            return { '' }
        elseif #content == 2 then
            local next_next = vim.api.nvim_buf_get_lines(0, cmp_y, cmp_y + 1, false)[1] or ''
            if content[2] == string.sub(next_next, 1, #content[2]) then
                return { '' }
            end
        elseif #content > 2 then
            local mids = {}
            for i = 1, #content - 2 do
                mids[i] = vim.api.nvim_buf_get_lines(0, cmp_y + i - 1, cmp_y + i, false)[1] or ''
            end
            local match = true
            for i = 2, #content - 1 do
                if content[i] ~= mids[i - 1] then
                    match = false
                    break
                end
            end
            if match then
                return { '' }
            end
        end
    end

    return content
end

return M