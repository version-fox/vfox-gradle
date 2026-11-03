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

-- Lists the keys of an EnvKeys result as "key=value" lines, in order.
local function describe(keys)
    local lines = {}
    for i, entry in ipairs(keys) do
        lines[i] = entry.key .. "=" .. entry.value
    end
    return table.concat(lines, "\n")
end

local cases = 0

-- GRADLE_HOME is the install directory and its bin directory goes on the PATH.
-- vfox hands over the directory of the version in use as ctx.path.
local keys = plugin:EnvKeys({ path = "/home/user/.vfox/cache/gradle/v-8.7/gradle-8.7" })
local expected = "GRADLE_HOME=/home/user/.vfox/cache/gradle/v-8.7/gradle-8.7\n"
    .. "PATH=/home/user/.vfox/cache/gradle/v-8.7/gradle-8.7/bin"
assert(describe(keys) == expected, "expected:\n" .. expected .. "\ngot:\n" .. describe(keys))
cases = cases + 1

-- On Windows the directory has backslashes. The hook appends /bin, which Windows
-- takes as a separator as well, so the PATH entry is still the bin directory.
keys = plugin:EnvKeys({ path = [[C:\Users\John Doe\.vfox\cache\gradle\v-8.7\gradle-8.7]] })
expected = [[GRADLE_HOME=C:\Users\John Doe\.vfox\cache\gradle\v-8.7\gradle-8.7]]
    .. "\n"
    .. [[PATH=C:\Users\John Doe\.vfox\cache\gradle\v-8.7\gradle-8.7/bin]]
assert(describe(keys) == expected, "expected:\n" .. expected .. "\ngot:\n" .. describe(keys))
cases = cases + 1

print("PASS: " .. cases .. " EnvKeys cases")
