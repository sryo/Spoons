local json = require("hs.json")

local M = {}

function M.decodeBatch(body)
    if type(body) ~= "string" or #body == 0 then
        return nil, "empty body"
    end
    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= "table" then
        return nil, "invalid json"
    end
    if type(data.events) ~= "table" then
        return nil, "missing events array"
    end
    return data
end

function M.encode(tbl)
    return json.encode(tbl)
end

return M
