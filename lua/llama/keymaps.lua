local M = {}
local previous_keymaps = {}

local function get_keymap_key(bufnr, mode, key)
    if not bufnr or not mode or not key then
        return 'invalid'
    end
    return bufnr .. ':' .. mode .. ':' .. key
end

function M.register_keymap(mode, key, action, desc, bufnr)
    if not key then
        return
    end

    local keymap_key = get_keymap_key(bufnr, mode, key)
    if previous_keymaps[keymap_key] then
        M.unset_keymap_if_exists(mode, key, bufnr)
    end

    vim.keymap.set(mode, key, function()
        action()
    end, {
        desc = desc,
        silent = true,
        buffer = bufnr,
    })

    previous_keymaps[keymap_key] = { type = 'none', value = nil }
end

local function save_existing_keymap(mode, key, keymap_key, bufnr)
    local existing
    vim.api.nvim_buf_call(bufnr, function()
        existing = vim.fn.maparg(key, mode, false, true)
    end)

    if existing then
        if existing.rhs and existing.rhs ~= '' then
            previous_keymaps[keymap_key] = { type = 'rhs', value = existing.rhs }
            return
        elseif existing.callback then
            previous_keymaps[keymap_key] = { type = 'callback', value = existing.callback, expr = existing.expr == 1 }
            return
        end
    end

    previous_keymaps[keymap_key] = { type = 'none', value = nil }
end

function M.register_keymap_with_passthrough(mode, key, action, desc, bufnr)
    if not key then
        return
    end

    local keymap_key = get_keymap_key(bufnr, mode, key)

    if previous_keymaps[keymap_key] then
        M.unset_keymap_if_exists(mode, key, bufnr)
    end

    save_existing_keymap(mode, key, keymap_key, bufnr)

    vim.keymap.set(mode, key, function()
        if action() then
            return '<Ignore>'
        end

        local prev = previous_keymaps[keymap_key]

        if prev then
            if prev.type == 'rhs' then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(prev.value, true, false, true), mode, true)
                return '<Ignore>'
            elseif prev.type == 'callback' then
                if prev.expr then
                    return prev.value()
                end
                prev.value()
                return '<Ignore>'
            end
        end

        return key
    end, {
        desc = desc,
        expr = true,
        replace_keycodes = true,
        silent = true,
        buffer = bufnr,
    })
end

function M.unset_keymap_if_exists(mode, key, bufnr)
    if not key or not bufnr then
        return
    end

    pcall(vim.api.nvim_buf_del_keymap, bufnr, mode, key)

    local keymap_key = get_keymap_key(bufnr, mode, key)
    local prev = previous_keymaps[keymap_key]

    if prev then
        if prev.type == 'rhs' and prev.value then
            vim.keymap.set(mode, key, prev.value, {
                silent = true,
                buffer = bufnr,
            })
        elseif prev.type == 'callback' and prev.value then
            vim.keymap.set(mode, key, prev.value, {
                silent = true,
                buffer = bufnr,
            })
        end
    end

    previous_keymaps[keymap_key] = nil
end

function M.clear_buffer_keymaps(bufnr)
    for keymap_key, prev in pairs(previous_keymaps) do
        local prefix = tostring(bufnr) .. ':'
        if keymap_key:sub(1, #prefix) == prefix then
            local rest = keymap_key:sub(#prefix + 1)
            local mode, key = rest:match('^([^:]+):(.+)$')
            if mode and key then
                pcall(vim.api.nvim_buf_del_keymap, bufnr, mode, key)
                if prev.type == 'rhs' and prev.value then
                    vim.keymap.set(mode, key, prev.value, {
                        silent = true,
                        buffer = bufnr,
                    })
                elseif prev.type == 'callback' and prev.value then
                    vim.keymap.set(mode, key, prev.value, {
                        silent = true,
                        buffer = bufnr,
                    })
                end
            end
            previous_keymaps[keymap_key] = nil
        end
    end
end

return M