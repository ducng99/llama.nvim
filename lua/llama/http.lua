local M = {}

local function split_lines(str)
    local lines = {}
    local pos = 1
    while pos <= #str do
        local nl = str:find('\n', pos, true)
        if nl then
            table.insert(lines, str:sub(pos, nl - 1))
            pos = nl + 1
        else
            table.insert(lines, str:sub(pos))
            break
        end
    end
    if str:sub(-1) == '\n' then
        table.insert(lines, '')
    end
    return lines
end

function M.send_fim(request, on_response, on_exit)
    local cfg = require('llama.config').get()
    if cfg.model_fim and cfg.model_fim ~= '' then
        request.model = cfg.model_fim
    end
    local endpoint = cfg.endpoint_fim
    local request_json = vim.fn.json_encode(request)

    local headers = { ['Content-Type'] = 'application/json' }
    if cfg.api_key and cfg.api_key ~= '' then
        headers['Authorization'] = 'Bearer ' .. cfg.api_key
    end

    local was_killed = false

    local job = vim.net.request('POST', endpoint, {
        body = request_json,
        headers = headers,
    }, function(err, res)
        if on_response and not err and res and res.body and #res.body > 0 then
            on_response(nil, split_lines(res.body), nil)
        end
        if on_exit then
            local code = err and 1 or 0
            on_exit(nil, code, was_killed)
        end
    end)

    local wrapper = {
        kill = function(_, _)
            was_killed = true
            if job then
                pcall(function()
                    job:close()
                end)
            end
        end,
    }

    return wrapper
end

function M.send_inst(request, on_response, on_exit)
    local cfg = require('llama.config').get()
    if cfg.model_inst and cfg.model_inst ~= '' then
        request.model = cfg.model_inst
    end
    local endpoint = cfg.endpoint_inst
    local request_json = vim.fn.json_encode(request)

    local headers = { ['Content-Type'] = 'application/json' }
    if cfg.api_key and cfg.api_key ~= '' then
        headers['Authorization'] = 'Bearer ' .. cfg.api_key
    end

    local was_killed = false

    local job = vim.net.request('POST', endpoint, {
        body = request_json,
        headers = headers,
    }, function(err, res)
        if on_response and not err and res and res.body and #res.body > 0 then
            local lines = split_lines(res.body)
            for _, line in ipairs(lines) do
                on_response(nil, { line }, nil)
            end
        end
        if on_exit then
            local code = err and 1 or 0
            on_exit(nil, code, was_killed)
        end
    end)

    local wrapper = {
        kill = function(_, _)
            was_killed = true
            if job then
                pcall(function()
                    job:close()
                end)
            end
        end,
    }

    return wrapper
end

function M.send_noop(request)
    local cfg = require('llama.config').get()
    if cfg.model_fim and cfg.model_fim ~= '' then
        request.model = cfg.model_fim
    end
    local endpoint = cfg.endpoint_fim
    local request_json = vim.fn.json_encode(request)

    local headers = { ['Content-Type'] = 'application/json' }
    if cfg.api_key and cfg.api_key ~= '' then
        headers['Authorization'] = 'Bearer ' .. cfg.api_key
    end

    vim.net.request('POST', endpoint, {
        body = request_json,
        headers = headers,
    }, nil)
end

function M.stop_job(job)
    if job then
        pcall(function()
            job:kill()
        end)
    end
end

return M
