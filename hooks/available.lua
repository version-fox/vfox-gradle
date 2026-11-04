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

local util = require("util")
local http = require("http")
--- Return all available versions provided by this plugin
--- @param ctx table Empty table used as context, for future extension
--- @return table Descriptions of available versions and accompanying tool descriptions
function PLUGIN:Available(ctx)
    local resp, err = http.get({
        url = util.AvailableVersionsUrl,
    })
    if err ~= nil or resp.status_code ~= 200 then
        error("get release info failed.")
    end
    local htmlBody = resp.body
    local htmlContent = [[]] .. htmlBody .. [[]]

    local result = {}

    for version in htmlContent:gmatch('<a name="(.-)"></a>') do
        table.insert(result, { version = version, note = "" })
    end
    table.sort(result, function(a, b)
        return util:compare_versions(a, b)
    end)

    return result
end
