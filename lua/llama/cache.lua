local M = {}

local cache_data = {}
local cache_lru_order = {}

function M.insert(key, value)
    local cfg = require('llama.config').get()

    if vim.tbl_count(cache_data) >= cfg.max_cache_keys then
        local lru_key = table.remove(cache_lru_order, 1)
        if lru_key then
            cache_data[lru_key] = nil
        end
    end

    cache_data[key] = value

    -- Remove existing and push to end (most recent)
    for i = #cache_lru_order, 1, -1 do
        if cache_lru_order[i] == key then
            table.remove(cache_lru_order, i)
            break
        end
    end
    table.insert(cache_lru_order, key)
end

function M.get(key)
    if cache_data[key] == nil then
        return nil
    end

    -- Update LRU order
    for i = #cache_lru_order, 1, -1 do
        if cache_lru_order[i] == key then
            table.remove(cache_lru_order, i)
            break
        end
    end
    table.insert(cache_lru_order, key)

    return cache_data[key]
end

function M.count()
    return vim.tbl_count(cache_data)
end

return M
