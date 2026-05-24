local M = {}

local ring_chunks = {}
local ring_queued = {}
local ring_n_evict = 0
local pos_y_pick = -9999

local function rand(i0, i1)
    return i0 + math.random(0, i1 - i0)
end

-- 0 = no similarity, 1 = high similarity
local function chunk_sim(c0, c1)
    local text0 = table.concat(c0, '\n')
    local text1 = table.concat(c1, '\n')

    -- Simple tokenization on non-word chars
    local tokens0 = {}
    for tok in string.gmatch(text0, '%w+') do
        tokens0[tok] = true
    end

    local tokens1 = {}
    for tok in string.gmatch(text1, '%w+') do
        tokens1[tok] = true
    end

    local common = 0
    for tok, _ in pairs(tokens1) do
        if tokens0[tok] then
            common = common + 1
        end
    end

    local n0 = vim.tbl_count(tokens0)
    local n1 = vim.tbl_count(tokens1)

    if (n0 + n1) == 0 then
        return 1.0
    end

    return 2.0 * common / (n0 + n1)
end

function M.get_extra()
    local extra = {}
    for _, chunk in ipairs(ring_chunks) do
        table.insert(extra, {
            text = chunk.str,
            time = chunk.time,
            filename = chunk.filename,
        })
    end
    return extra
end

function M.pick_chunk(text, no_mod, do_evict)
    local cfg = require('llama.config').get()

    if cfg.ring_n_chunks <= 0 then
        return
    end

    -- do not pick chunks from buffers with pending changes or buffers that are not files
    if no_mod then
        local bufnr = vim.api.nvim_get_current_buf()
        local modified = vim.bo[bufnr].modified
        local listed = vim.bo[bufnr].buflisted
        local fname = vim.api.nvim_buf_get_name(bufnr)
        local readable = fname ~= '' and vim.fn.filereadable(fname) == 1
        if modified or not listed or not readable then
            return
        end
    end

    if #text < 3 then
        return
    end

    local chunk
    if #text + 1 < cfg.ring_chunk_size then
        chunk = vim.deepcopy(text)
    else
        local l0 = rand(0, math.max(0, #text - math.floor(cfg.ring_chunk_size / 2)))
        local l1 = math.min(l0 + math.floor(cfg.ring_chunk_size / 2), #text)
        chunk = {}
        for i = l0 + 1, l1 do
            table.insert(chunk, text[i])
        end
    end

    local chunk_str = table.concat(chunk, '\n') .. '\n'

    -- check existence
    local exist = false
    for _, c in ipairs(ring_chunks) do
        if vim.deep_equal(c.data, chunk) then
            exist = true
            break
        end
    end
    for _, c in ipairs(ring_queued) do
        if vim.deep_equal(c.data, chunk) then
            exist = true
            break
        end
    end
    if exist then
        return
    end

    -- evict similar queued chunks
    for i = #ring_queued, 1, -1 do
        if chunk_sim(ring_queued[i].data, chunk) > 0.9 then
            if do_evict then
                table.remove(ring_queued, i)
                ring_n_evict = ring_n_evict + 1
            else
                return
            end
        end
    end

    -- evict similar ring chunks
    for i = #ring_chunks, 1, -1 do
        if chunk_sim(ring_chunks[i].data, chunk) > 0.9 then
            if do_evict then
                table.remove(ring_chunks, i)
                ring_n_evict = ring_n_evict + 1
            else
                return
            end
        end
    end

    if #ring_queued >= 16 then
        table.remove(ring_queued, 1)
    end

    table.insert(ring_queued, {
        data = chunk,
        str = chunk_str,
        time = vim.fn.reltime(),
        filename = vim.api.nvim_buf_get_name(0),
    })
end

function M.update()
    local cfg = require('llama.config').get()
    vim.fn.timer_start(cfg.ring_update_ms, function()
        M.update()
    end)

    -- skip if not in normal mode and cursor moved recently
    local t_last_move = require('llama.fim').t_last_move
    if vim.fn.mode() ~= 'n' and vim.fn.reltimefloat(vim.fn.reltime(t_last_move)) < 3.0 then
        return
    end

    if #ring_queued == 0 then
        return
    end

    if #ring_chunks == cfg.ring_n_chunks then
        table.remove(ring_chunks, 1)
    end

    table.insert(ring_chunks, table.remove(ring_queued, 1))

    local extra = M.get_extra()
    local request = {
        id_slot = 0,
        input_prefix = '',
        input_suffix = '',
        input_extra = extra,
        prompt = '',
        n_predict = 0,
        temperature = 0.0,
        samplers = {},
        stream = false,
        cache_prompt = true,
        t_max_prompt_ms = 1,
        t_max_predict_ms = 1,
        response_fields = { '' },
    }

    require('llama.http').send_noop(request)
end

function M.n_evict()
    return ring_n_evict
end

function M.n_chunks()
    return #ring_chunks
end

function M.n_queued()
    return #ring_queued
end

function M.evict_similar_to_current(chunk)
    for i = #ring_chunks, 1, -1 do
        if chunk_sim(ring_chunks[i].data, chunk) > 0.5 then
            table.remove(ring_chunks, i)
            ring_n_evict = ring_n_evict + 1
        end
    end
end

function M.get_pos_y_pick()
    return pos_y_pick
end

function M.set_pos_y_pick(y)
    pos_y_pick = y
end

return M
