local M = {}

local default_url = 'http://127.0.0.1:3847'
local ensure_timeout_ms = 5000

local function trim_slash(url)
    return tostring(url or ''):gsub('/+$', '')
end

local function encode_query(value)
    if vim.uri_encode then
        return vim.uri_encode(value, 'rfc3986')
    end
    return tostring(value):gsub('([^%w%-_%.~])', function(char)
        return string.format('%%%02X', string.byte(char))
    end)
end

local function result_message(result, fallback)
    local stderr = vim.trim(result.stderr or '')
    if stderr ~= '' then
        return stderr
    end

    local stdout = vim.trim(result.stdout or '')
    if stdout ~= '' then
        return stdout
    end

    return fallback
end

local function daemon_state_url()
    local path = vim.fn.expand('~/.agent-watch/daemon.json')
    if vim.fn.filereadable(path) ~= 1 then
        return nil
    end

    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    if decoded.healthy == false then
        return nil
    end

    local url = decoded.url or decoded.daemon_url or decoded.base_url
    if type(url) == 'string' and vim.trim(url) ~= '' then
        return vim.trim(url)
    end

    local port = decoded.port
    if port then
        return 'http://127.0.0.1:' .. tostring(port)
    end

    return nil
end

function M.resolve_url(opts)
    if opts.daemon_url and vim.trim(opts.daemon_url) ~= '' then
        return trim_slash(vim.trim(opts.daemon_url))
    end

    return trim_slash(daemon_state_url() or default_url)
end

function M.ensure(opts, callback)
    vim.system({ opts.cli, 'daemon', 'ensure' }, { text = true, timeout = ensure_timeout_ms }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                local fallback = result.code == 124 and 'aw daemon ensure timed out' or 'aw daemon ensure failed'
                callback(result_message(result, fallback))
                return
            end

            callback(nil)
        end)
    end)
end

local function parse_agent_rows(stdout)
    if stdout == nil or stdout == '' then
        return {}
    end

    local ok, decoded = pcall(vim.json.decode, stdout)
    if not ok then
        error('Could not parse agent-watchd JSON: ' .. tostring(decoded))
    end

    if vim.islist(decoded) then
        return decoded
    end

    if type(decoded) == 'table' then
        for _, key in ipairs({ 'agents', 'rows', 'items' }) do
            if type(decoded[key]) == 'table' then
                return decoded[key]
            end
        end
    end

    return {}
end

-- Lists every agent the daemon tracks; ownership and project filtering happen
-- client-side in rows.filter, where buffer validity can actually be checked.
function M.list_agents(opts, callback)
    local url = M.resolve_url(opts) .. '/agents'
    vim.system({ 'curl', '-fsS', '--max-time', '5', url }, { text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                callback(nil, result_message(result, 'agent-watchd request failed'))
                return
            end

            local ok, rows_or_error = pcall(parse_agent_rows, result.stdout)
            if not ok then
                callback(nil, rows_or_error)
                return
            end

            callback(rows_or_error)
        end)
    end)
end

function M.rename(opts, id, title, callback)
    local body = vim.json.encode({ title = title })
    local url = M.resolve_url(opts) .. '/launches/' .. encode_query(id)
    vim.system({
        'curl',
        '-fsS',
        '--max-time',
        '5',
        '-X',
        'PATCH',
        '-H',
        'Content-Type: application/json',
        '--data',
        body,
        url,
    }, { text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                callback(result_message(result, 'agent-watchd rename failed'))
                return
            end
            callback(nil)
        end)
    end)
end

function M.delete(opts, id, callback)
    local url = M.resolve_url(opts) .. '/launches/' .. encode_query(id)
    vim.system({ 'curl', '-fsS', '--max-time', '5', '-X', 'DELETE', url }, { text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                callback(result_message(result, 'agent-watchd delete failed'))
                return
            end
            callback(nil)
        end)
    end)
end

return M
