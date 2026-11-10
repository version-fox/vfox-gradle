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

-- Java properties escapes in the URL (the file writes https\:...).
local function unescape(value)
    return (
        value:gsub("\\(.)", {
            ["\\"] = "\\",
            [":"] = ":",
            ["="] = "=",
            [" "] = " ",
            ["t"] = "\t",
            ["n"] = "\n",
            ["r"] = "\r",
        })
    )
end

-- The Gradle version from a wrapper distributionUrl: the gradle-<version> in
-- .../gradle-8.7-bin.zip, .../gradle-9.8.2-all.zip or .../gradle-8.7-rc-1-bin.zip,
-- from any host (services.gradle.org, a mirror, or a local file). Returns nil
-- where the URL names no Gradle release.
local function version_from_url(url)
    if type(url) ~= "string" or url == "" then
        return nil
    end
    local clean = url:match("^([^%?#]+)") or url
    local file = clean:match("([^/]+)%s*$")
    if file == nil then
        return nil
    end
    local lower = file:lower()
    local version = lower:match("^gradle%-(.-)%-bin%.zip$") or lower:match("^gradle%-(.-)%-all%.zip$")
    if version == nil then
        return nil
    end
    if not util:is_valid_version_name(version) then
        return nil
    end
    return version
end

--- Reads the Gradle a wrapper project pins: the distributionUrl in
--- gradle/wrapper/gradle-wrapper.properties, e.g.
--- https\: //services.gradle.org/distributions/gradle-8.7-bin.zip.
--- The wrapper pins one exact release, so it is returned as is whatever the
--- resolution strategy: vfox selects it when installed, and names what is
--- missing when it is not. A -all distribution takes the same version (the
--- plugin installs -bin). Where the file has no readable URL, nothing is
--- returned and vfox carries on as if the file were not there.
function PLUGIN:ParseLegacyFile(ctx)
    local filepath = ctx.filepath
    if type(filepath) ~= "string" or filepath == "" then
        return {}
    end
    local file = io.open(filepath, "r")
    if file == nil then
        return {}
    end
    -- java.util.Properties keeps the last value; comments start with # or !.
    local url
    for line in file:lines() do
        if not line:match("^%s*[#!]") then
            local value = line:match("^%s*distributionUrl%s*[=:]%s*(.-)%s*$")
            if value ~= nil and value ~= "" then
                url = value
            end
        end
    end
    file:close()
    if url == nil then
        return {}
    end
    local version = version_from_url(unescape(url))
    if version == nil then
        return {}
    end
    return { version = version }
end
