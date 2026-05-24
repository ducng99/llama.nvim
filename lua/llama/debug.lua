local M = {}

local debug = {
    bufnr = -1,
    log = {},
    max_lines = 1024,
    flush = -1,
    dirty = 0,
}

local function ensure_buf()
    if debug.bufnr > 0 and vim.api.nvim_buf_is_valid(debug.bufnr) then
        return true
    end

    vim.cmd('botright new')
    local winnr = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].buftype = 'nofile'
    vim.bo[bufnr].bufhidden = 'hide'
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
    vim.wo[winnr].wrap = false
    vim.wo[winnr].number = false
    vim.wo[winnr].relativenumber = false
    vim.wo[winnr].signcolumn = 'no'
    vim.wo[winnr].spell = false
    vim.wo[winnr].foldmethod = 'marker'
    vim.wo[winnr].foldmarker = '{{{,}}}'
    vim.wo[winnr].foldlevel = 0
    vim.wo[winnr].foldenable = true
    vim.wo[winnr].foldcolumn = '2'

    vim.api.nvim_buf_set_name(bufnr, '[llama.vim-debug]')
    debug.bufnr = bufnr
    return true
end

local function flush_impl()
    debug.flush = -1
    if not (debug.bufnr > 0 and vim.api.nvim_buf_is_valid(debug.bufnr)) then
        return
    end

    if debug.dirty == 0 then
        return
    end
    debug.dirty = 0

    vim.bo[debug.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(debug.bufnr, 0, -1, false, {})

    local flat = {}
    for _, block in ipairs(debug.log) do
        for _, line in ipairs(block) do
            table.insert(flat, line)
        end
    end

    if #flat > 0 then
        vim.api.nvim_buf_set_lines(debug.bufnr, 0, -1, false, flat)
    end

    vim.bo[debug.bufnr].modifiable = false
end

local function flush_sched()
    if debug.flush ~= -1 then
        return
    end
    debug.flush = vim.fn.timer_start(50, function()
        flush_impl()
    end, { repeat_count = 0 })
end

function M.log(msg, details)
    details = details or {}
    if type(details) ~= 'table' then
        details = vim.split(tostring(details), '\n')
    end

    local timestamp = os.date('%H:%M:%S')
    local header = timestamp .. ' | ' .. msg

    local block = {}
    if #details > 0 then
        header = header .. ' | ' .. (details[1] or '')
        table.insert(block, header .. ' {{{')
        for _, line in ipairs(details) do
            table.insert(block, line)
        end
        table.insert(block, '}}}')
    else
        table.insert(block, header)
    end

    table.insert(debug.log, 1, block)

    if #debug.log > debug.max_lines then
        table.remove(debug.log)
    end

    debug.dirty = 1
    flush_sched()
end

function M.toggle()
    if debug.bufnr > 0 and vim.api.nvim_buf_is_valid(debug.bufnr) then
        local winnr = vim.fn.bufwinnr(debug.bufnr)
        if winnr ~= -1 then
            vim.cmd(winnr .. 'close')
            return
        end
    end

    if debug.bufnr > 0 and vim.api.nvim_buf_is_valid(debug.bufnr) then
        vim.cmd('botright sbuffer ' .. debug.bufnr)
    else
        ensure_buf()
    end
    flush_sched()
end

function M.clear()
    debug.log = {}
    if debug.bufnr > 0 and vim.api.nvim_buf_is_valid(debug.bufnr) then
        vim.bo[debug.bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(debug.bufnr, 0, -1, false, {})
        vim.bo[debug.bufnr].modifiable = false
    end
end

function M.setup()
    M.clear()
    vim.api.nvim_create_user_command('LlamaDebugClear', function()
        M.clear()
    end, {})
    vim.api.nvim_create_user_command('LlamaDebugToggle', function()
        M.toggle()
    end, {})
end

return M
