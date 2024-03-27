local util = require("util")

--- Return all available versions provided by this plugin
--- @param ctx table Empty table used as context, for future extension
--- @return table Descriptions of available versions and accompanying tool descriptions
function PLUGIN:Available(ctx)
    local resp, err = http.get({
        url = util.AvailableVersionsUrl
    })
    if err ~= nil or resp.status_code ~= 200 then
        error('get release info failed.')
    end
    local htmlBody = resp.body
    local htmlContent= [[]] .. htmlBody .. [[]]

    local result = {}

    for version in htmlContent:gmatch('<a name="(.-)"></a>') do
        table.insert(result, {version=version,note=""})
    end
    table.sort(result, function(a, b)
        return util:compare_versions(a, b)
    end)

    return result
end