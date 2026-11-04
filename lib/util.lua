-- Copyright 2026 Han Li and contributors
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--   http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local Util = {}

Util.__index = Util

local UtilSingleton = setmetatable({}, Util)
UtilSingleton.AvailableVersionsUrl = "https://gradle.org/releases/"
UtilSingleton.DownloadInfoUrl = "https://services.gradle.org/distributions/gradle-%s-bin.zip"

function Util:compare_versions(v1o, v2o)
    local v1 = v1o.version
    local v2 = v2o.version
    local v1_parts = {}
    for part in string.gmatch(v1, "[^.]+") do
        table.insert(v1_parts, tonumber(part))
    end

    local v2_parts = {}
    for part in string.gmatch(v2, "[^.]+") do
        table.insert(v2_parts, tonumber(part))
    end

    for i = 1, math.max(#v1_parts, #v2_parts) do
        local v1_part = v1_parts[i] or 0
        local v2_part = v2_parts[i] or 0
        if v1_part > v2_part then
            return true
        elseif v1_part < v2_part then
            return false
        end
    end

    return false
end

--- Headers that vfox sends with the download of the archive. Without them vfox
--- identifies itself with the User-Agent of Go's HTTP client, `Go-http-client/1.1`,
--- and some mirrors (Huawei Cloud's) answer that with an error page in place of the
--- archive: vfox saves the answer and the install ends in `Checksum error`. The
--- requests of the plugin itself carry the User-Agent that vfox builds for it,
--- `vfox/<vfox version> vfox-gradle/<plugin version>`, so the download sends the
--- same, worded as vfox's `ComputeUserAgent` words it: `vfox` alone and no version
--- where vfox gives none.
--- @return table<string, string>
function Util:download_headers()
    local function present(value)
        return value ~= nil and value ~= ""
    end
    local name = "vfox-gradle"
    if PLUGIN ~= nil and present(PLUGIN.name) then
        name = PLUGIN.name:sub(1, 5) == "vfox-" and PLUGIN.name or "vfox-" .. PLUGIN.name
    end
    if PLUGIN ~= nil and present(PLUGIN.version) then
        name = name .. "/" .. PLUGIN.version
    end
    local runtime = "vfox"
    if RUNTIME ~= nil and present(RUNTIME.version) then
        runtime = runtime .. "/" .. RUNTIME.version
    end
    return { ["User-Agent"] = runtime .. " " .. name }
end

return UtilSingleton
