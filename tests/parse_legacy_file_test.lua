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

local cases = 0

local function parse(content, strategy)
    local path = os.tmpname()
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
    local result = plugin:ParseLegacyFile({
        filename = "gradle/wrapper/gradle-wrapper.properties",
        filepath = path,
        strategy = strategy or "specified",
        installedVersions = { "9.8.2", "8.7" },
    })
    os.remove(path)
    return result.version
end

local function check(content, expected, strategy)
    local got = parse(content, strategy)
    if expected == nil then
        assert(got == nil or got == "", "expected no version, got " .. tostring(got))
    else
        assert(got == expected, "expected " .. expected .. ", got " .. tostring(got))
    end
    cases = cases + 1
end

-- The standard file: distributionUrl names the exact release.
check("distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-bin.zip\n", "8.7")
-- An unescaped URL works too.
check("distributionUrl=https://services.gradle.org/distributions/gradle-9.8.2-bin.zip\n", "9.8.2")
-- The complete distribution takes the same version (the plugin installs -bin).
check("distributionUrl=https\\://services.gradle.org/distributions/gradle-9.8.2-all.zip\n", "9.8.2")
-- A mirror URL with the same file layout.
check("distributionUrl=https\\://mirrors.cloud.tencent.com/gradle/gradle-8.14.3-bin.zip\n", "8.14.3")
-- A release candidate is returned as is (installing it may fail like a manual install).
check("distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-rc-1-bin.zip\n", "8.7-rc-1")
-- A full file: comments, other keys and Windows line endings around the URL.
check(
    "#Thu Nov 04 2026\r\ndistributionBase=GRADLE_USER_HOME\r\ndistributionPath=wrapper/dists\r\n"
        .. "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-bin.zip\r\nzipStorePath=wrapper/dists\r\n",
    "8.7"
)
-- The pin is exact whatever the strategy: latest_installed does not remap it.
check("distributionUrl=https\\://services.gradle.org/distributions/gradle-8.7-bin.zip\n", "8.7", "latest_installed")
-- No URL, a foreign file, or an empty file: nothing to select.
check("distributionBase=GRADLE_USER_HOME\ndistributionPath=wrapper/dists\n", nil)
check("distributionUrl=https\\://example.com/files/tool-1.0.zip\n", nil)
check("", nil)

print("PASS: " .. cases .. " ParseLegacyFile cases")
