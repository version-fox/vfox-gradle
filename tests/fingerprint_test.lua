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

local test = require("vfox.test")
local plugin = test.load({ os = "linux", arch = "amd64" })

-- vfox 1.0.13 and older do not know the Fingerprint hook: the core never loads
-- hooks/fingerprint.lua and the test proxy has no Fingerprint method. Load the
-- file directly and call PLUGIN instead, so the same assertions run on both.
local function call_fingerprint(path)
    if plugin.Fingerprint ~= nil then
        return plugin:Fingerprint({ path = path })
    end
    dofile(RUNTIME.pluginDirPath .. "/hooks/fingerprint.lua")
    return PLUGIN:Fingerprint({ path = path })
end

local cases = 0

-- The launcher jar of a 9.8.2 install, as lib/gradle-launcher.properties names it.
local properties = "dependencies=ant,groovy,guava\njarFile=gradle-launcher-9.8.2.jar\n"

local original_open = io.open
io.open = function(path, mode)
    if path == "/fake/gradle-9.8.2/lib/gradle-launcher.properties" then
        local lines = {}
        for line in (properties .. "\n"):gmatch("(.-)\n") do
            table.insert(lines, line)
        end
        local i = 0
        return {
            lines = function()
                return function()
                    i = i + 1
                    return lines[i]
                end
            end,
            close = function() end,
        }
    end
    if path == "/fake/broken/lib/gradle-launcher.properties" then
        return nil
    end
    return original_open(path, mode)
end

-- The one fact is the launcher jar: it names the installed release.
local found = call_fingerprint("/fake/gradle-9.8.2")
assert(
    found ~= nil and found.facts ~= nil and found.facts.launcher == "gradle-launcher-9.8.2.jar",
    "launcher fact missing"
)
cases = cases + 1

-- Forward slashes work on Windows too, so a Windows path reads the same file.
io.open = function(path, mode)
    if path == "C:/fake/gradle-9.8.2/lib/gradle-launcher.properties" then
        local done = false
        return {
            lines = function()
                return function()
                    if done then
                        return nil
                    end
                    done = true
                    return "jarFile=gradle-launcher-9.8.2.jar"
                end
            end,
            close = function() end,
        }
    end
    return original_open(path, mode)
end
found = call_fingerprint("C:/fake/gradle-9.8.2")
assert(found ~= nil and found.facts.launcher == "gradle-launcher-9.8.2.jar", "windows path should read the same file")
cases = cases + 1

-- An install without the properties file records nothing, instead of erroring:
-- vfox then skips the drift check for it.
io.open = function(path, mode)
    if path == "/fake/broken/lib/gradle-launcher.properties" then
        return nil
    end
    return original_open(path, mode)
end
assert(call_fingerprint("/fake/broken") == nil, "unreadable properties should record no facts")
assert(call_fingerprint("") == nil, "empty path should record no facts")
cases = cases + 2

io.open = original_open

print("PASS: " .. cases .. " Fingerprint cases")
