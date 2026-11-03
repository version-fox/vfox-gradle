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
test.load()
local util = require("util")

local cases = 0

-- compare_versions(a, b) is true when a comes before b in a list that starts with
-- the newest version, which is what table.sort wants from Available.
local function newer(a, b)
    return util:compare_versions({ version = a }, { version = b })
end

local function check(a, b, expected)
    assert(newer(a, b) == expected, ("%s before %s: expected %s"):format(a, b, tostring(expected)))
    cases = cases + 1
end

-- Numbers, not text: 8.14 is newer than 8.7, and 10.0 would be newer than 9.8.2.
check("8.14", "8.7", true)
check("8.7", "8.14", false)
check("10.0", "9.8.2", true)
check("9.8.2", "9.8.1", true)
check("9.0.0", "8.14.6", true)
check("8.14.6", "8.14.3", true)

-- A release with fewer numbers counts as if it ended in zeros: Gradle writes
-- 8.14 for 8.14.0 and 9.0.0 for the first release of 9. Neither is before the
-- other, as table.sort needs of two equal elements.
check("8.14", "8.14.1", false)
check("8.14.1", "8.14", true)
check("8.14", "8.14.0", false)
check("8.14.0", "8.14", false)
check("9.0", "9.0.0", false)
check("9.0.0", "9.0", false)
check("8.7", "8.7", false)

-- The headers of a download carry the User-Agent that vfox builds for the requests
-- of the plugin itself, worded as vfox's ComputeUserAgent words it:
-- "vfox/<vfox version> vfox-<plugin name>/<plugin version>", with "vfox" alone
-- where vfox gives no version and no "/<plugin version>" where there is none.
local function agent(runtime_version, plugin_name, plugin_version)
    local saved = { RUNTIME.version, PLUGIN.name, PLUGIN.version }
    RUNTIME.version, PLUGIN.name, PLUGIN.version = runtime_version, plugin_name, plugin_version
    local headers = util:download_headers()
    RUNTIME.version, PLUGIN.name, PLUGIN.version = saved[1], saved[2], saved[3]
    return headers["User-Agent"]
end

for _, case in ipairs({
    { { "1.0.13", "gradle", "0.1.1" }, "vfox/1.0.13 vfox-gradle/0.1.1" },
    { { "1.0.13", "gradle", nil }, "vfox/1.0.13 vfox-gradle" },
    { { "1.0.13", "gradle", "" }, "vfox/1.0.13 vfox-gradle" },
    { { "", "gradle", "0.1.1" }, "vfox vfox-gradle/0.1.1" },
    { { nil, "gradle", "0.1.1" }, "vfox vfox-gradle/0.1.1" },
    { { "1.0.13", nil, "0.1.1" }, "vfox/1.0.13 vfox-gradle/0.1.1" },
    { { "1.0.13", "vfox-gradle", "0.1.1" }, "vfox/1.0.13 vfox-gradle/0.1.1" },
}) do
    local args, expected = case[1], case[2]
    local got = agent(args[1], args[2], args[3])
    assert(got == expected, ("User-Agent: expected %s, got %s"):format(expected, got))
    cases = cases + 1
end

-- What the VM gives is what a real install sends, and it is never Go's default.
local real = util:download_headers()["User-Agent"]
assert(real == "vfox/" .. RUNTIME.version .. " vfox-gradle/" .. PLUGIN.version, "User-Agent: " .. real)
assert(not real:find("Go-http-client", 1, true) and not real:find("nil", 1, true), "User-Agent: " .. real)
cases = cases + 2

-- The download URL is the only other thing the module holds.
assert(util.DownloadInfoUrl:format("8.7") == "https://services.gradle.org/distributions/gradle-8.7-bin.zip")
assert(util.AvailableVersionsUrl == "https://gradle.org/releases/")
cases = cases + 2

print("PASS: " .. cases .. " version comparison cases")
