local util = require("util")
local os = require("os")
local http = require("http")
--- Returns some pre-installed information, such as version number, download address, local files, etc.
--- If checksum is provided, vfox will automatically check it for you.
--- @param ctx table
--- @field ctx.version string User-input version
--- @return table Version information
function PLUGIN:PreInstall(ctx)

    local result = {}
    local version = ctx.version
    result.version = version

    local downloadUrl = ""
    local mirrorUrl = os.getenv("VFOX_GRADLE_MIRRORS")

    if mirrorUrl ~=nil then
        downloadUrl = mirrorUrl.."/gradle-"..version.."-bin.zip"
    else
        downloadUrl = util.DownloadInfoUrl:format(version)
    end

    result.url = downloadUrl

    local resp, err = http.get({
        url = downloadUrl..".sha256"
    })

    if err then
        error("HTTP request error: " .. err)
    end

    if resp.status_code == 200 then
        if resp.body then
            result.sha256 = resp.body
        else
            error("Empty body in HTTP response")
        end
    elseif resp.status_code == 404 then
        -- do nothing
    else
        return nil
    end

    return result
end