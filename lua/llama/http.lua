local M = {}

local function build_curl_command(endpoint, api_key)
    local cmd = {
        'curl',
        '--silent',
        '--no-buffer',
        '--fail',
        '--request', 'POST',
        '--url', endpoint,
        '--header', 'Content-Type: application/json',
        '--data', '@-',
    }

    if api_key and api_key ~= '' then
        table.insert(cmd, '--header')
        table.insert(cmd, 'Authorization: Bearer ' .. api_key)
    end

    return cmd
end

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
    local cmd = build_curl_command(cfg.endpoint_fim, cfg.api_key)
    local request_json = vim.fn.json_encode(request)

    local was_killed = false

    local function on_exit_callback(result)
        if on_response and result.stdout and #result.stdout > 0 and result.code == 0 then
            on_response(nil, split_lines(result.stdout), nil)
        end
        if on_exit then
            on_exit(nil, result.code, was_killed)
        end
    end

    local obj = vim.system(cmd, {
        stdin = request_json,
    }, on_exit_callback)

    local original_kill = obj.kill
    obj.kill = function(self, signal)
        was_killed = true
        original_kill(self, signal)
    end

    return obj
end

function M.send_inst(request, on_response, on_exit)
    local cfg = require('llama.config').get()
    if cfg.model_inst and cfg.model_inst ~= '' then
        request.model = cfg.model_inst
    end
    for k, v in pairs(cfg.inst_extra_body) do
        request[k] = v
    end
    local cmd = build_curl_command(cfg.endpoint_inst, cfg.api_key)
    local request_json = vim.fn.json_encode(request)

    local line_buffer = ''
    local was_killed = false

    local function on_exit_callback(result)
        if on_exit then
            on_exit(nil, result.code, was_killed)
        end
    end

    local obj = vim.system(cmd, {
        stdin = request_json,
        stdout = function(_, data)
            if not on_response then
                return
            end
            if data then
                line_buffer = line_buffer .. data
                while true do
                    local nl = line_buffer:find('\n', 1, true)
                    if not nl then
                        break
                    end
                    local line = line_buffer:sub(1, nl - 1)
                    line_buffer = line_buffer:sub(nl + 1)
                    on_response(nil, { line }, nil)
                end
            elseif #line_buffer > 0 then
                on_response(nil, { line_buffer }, nil)
                line_buffer = ''
            end
        end,
    }, on_exit_callback)

    local original_kill = obj.kill
    obj.kill = function(self, signal)
        was_killed = true
        original_kill(self, signal)
    end

    return obj
end

function M.send_noop(request)
    local cfg = require('llama.config').get()
    if cfg.model_fim and cfg.model_fim ~= '' then
        request.model = cfg.model_fim
    end
    local cmd = build_curl_command(cfg.endpoint_fim, cfg.api_key)
    local request_json = vim.fn.json_encode(request)

    vim.system(cmd, {
        stdin = request_json,
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
