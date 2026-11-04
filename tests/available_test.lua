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

-- gradle.org/releases lists the releases by date, so the page order is not the
-- version order: 8.14.6 comes before 9.8.1 in the fixture, as on the live page.
local function read_fixture()
    local file = assert(io.open(RUNTIME.pluginDirPath .. "/tests/fixtures/releases.html", "rb"))
    local body = file:read("*a")
    file:close()
    return body
end

-- What the next request gets. A table, because gopher-lua's closures do not see
-- a local that a case assigns after the first pcall.
local state = { requests = {}, status = 200, transport_error = nil, body = nil }

local plugin = test.load({
    os = "linux",
    arch = "amd64",
    http = function(request)
        state.requests[#state.requests + 1] = request.method .. " " .. request.url
        if state.transport_error then
            return nil, state.transport_error
        end
        return { status_code = state.status, body = state.body or read_fixture() }
    end,
})

local function names(versions)
    local list = {}
    for i, entry in ipairs(versions) do
        list[i] = entry.version
    end
    return table.concat(list, " ")
end

local cases = 0

-- Every release of the page, newest first by version number, whatever the page's
-- order is. A release with two numbers (8.14, 0.9) sorts as if it ended in .0,
-- and 9.0.0 is named with the .0, as Gradle names it.
local versions = plugin:Available({})
local expected = "9.8.2 9.8.1 9.0.0 8.14.6 8.14.3 8.14 8.7 7.6.6 2.14.1 1.0 0.9.2 0.7"
assert(names(versions) == expected, "expected " .. expected .. ", got " .. names(versions))
cases = cases + 1

-- It asks for the release page, once, and gives no note: vfox core takes the
-- first entry for `latest`, so the order above is what `latest` means.
assert(#state.requests == 1, "expected one request, got " .. #state.requests)
assert(state.requests[1] == "GET https://gradle.org/releases/", state.requests[1])
for _, entry in ipairs(versions) do
    assert(entry.note == "", entry.version .. ": expected no note, got " .. tostring(entry.note))
end
cases = cases + 2

-- A page that is not 200, or a request that fails, stops the search with one
-- message. The anchors of an error page would not be releases.
state.status = 500
state.body = "<html><body>" .. '<a name="1.0"></a>' .. "</body></html>"
local ok, err = pcall(function()
    return plugin:Available({})
end)
assert(not ok and tostring(err):find("get release info failed.", 1, true), "status 500: unexpected " .. tostring(err))
cases = cases + 1

state.status = 200
state.transport_error = "connection refused"
ok, err = pcall(function()
    return plugin:Available({})
end)
assert(
    not ok and tostring(err):find("get release info failed.", 1, true),
    "transport error: unexpected " .. tostring(err)
)
cases = cases + 1

print("PASS: " .. cases .. " Available cases")
