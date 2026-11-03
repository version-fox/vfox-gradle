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

-- What the checksum request gets, by URL. A table, because gopher-lua's closures
-- do not see a local that a case assigns after the first pcall.
local state = { requests = {}, answers = {} }

local plugin = test.load({
    os = "linux",
    arch = "amd64",
    http = function(request)
        state.requests[#state.requests + 1] = request.method .. " " .. request.url
        local answer = state.answers[request.url]
        assert(answer ~= nil, "unexpected request: " .. request.url)
        if answer.transport_error then
            return nil, answer.transport_error
        end
        return { status_code = answer.status, body = answer.body }
    end,
})

-- The mirror comes from the environment: os.getenv answers for it from this
-- table, whose field the cases set, and for everything else as it did.
local env = {}
local getenv = os.getenv
os.getenv = function(name)
    if name == "VFOX_GRADLE_MIRRORS" then
        return env.mirror
    end
    return getenv(name)
end

-- The digest services.gradle.org gives for gradle-8.7-bin.zip: 64 hex digits and
-- nothing around them, which is the form vfox compares with its own hash.
local sha256 = "544c35d6bd849ae8a5ed0bcea39ba677dc40f49df7d1835561582da2009b961d"

local cases = 0

local function install(version, mirror, answers)
    env.mirror = mirror
    state.requests = {}
    state.answers = answers
    return plugin:PreInstall({ version = version })
end

local function check_request(expected)
    assert(#state.requests == 1, "expected one request, got " .. table.concat(state.requests, ", "))
    assert(state.requests[1] == "GET " .. expected, "expected GET " .. expected .. ", got " .. state.requests[1])
    cases = cases + 1
end

-- Without a mirror the archive comes from services.gradle.org, and so does its
-- checksum, which is passed on as sha256 for vfox to verify the download with.
local official = "https://services.gradle.org/distributions/gradle-8.7-bin.zip"
local result = install("8.7", nil, { [official .. ".sha256"] = { status = 200, body = sha256 } })
assert(result.version == "8.7", "version: " .. tostring(result.version))
assert(result.url == official, "url: " .. tostring(result.url))
assert(result.sha256 == sha256, "sha256: " .. tostring(result.sha256))
cases = cases + 3
check_request(official .. ".sha256")

-- The download is made by vfox, which calls itself Go-http-client/1.1 unless the
-- hook names an agent. Some mirrors refuse that name with a 403 and a page of
-- HTML, which vfox saves as the archive and reports as "Checksum error". The hook
-- gives the download the name vfox gives the requests of a hook, with the plugin's
-- version: "vfox/<vfox version> vfox-gradle/<plugin version>".
local agent = result.headers and result.headers["User-Agent"]
local expected_agent = "vfox/" .. tostring(RUNTIME.version) .. " vfox-gradle/" .. tostring(PLUGIN.version)
assert(agent == expected_agent, "User-Agent: expected " .. expected_agent .. ", got " .. tostring(agent))
assert(not agent:find("Go-http-client", 1, true), "User-Agent must not be Go's default: " .. agent)
cases = cases + 2

-- The version goes into the name as typed: 9.0.0 has its .0, 8.14 has none.
for _, version in ipairs({ "9.0.0", "8.14", "0.9.2" }) do
    local url = "https://services.gradle.org/distributions/gradle-" .. version .. "-bin.zip"
    result = install(version, nil, { [url .. ".sha256"] = { status = 200, body = sha256 } })
    assert(result.url == url, version .. ": expected " .. url .. ", got " .. tostring(result.url))
    cases = cases + 1
end

-- vfox compares the digest with the hash of the download as the hook gives it, so
-- the hook gives the digest alone, in lower case, whatever the file around it is
-- like: a newline after it, capitals, the format of sha256sum, blanks before it.
-- Each of these made vfox fail a good download with "Checksum error".
for label, body in pairs({
    newline = sha256 .. "\n",
    crlf = sha256 .. "\r\n",
    capitals = sha256:upper(),
    sha256sum = sha256 .. "  gradle-8.7-bin.zip\n",
    ["sha256sum, binary mode"] = sha256 .. " *gradle-8.7-bin.zip\n",
    blanks = "  \n" .. sha256 .. "\n",
}) do
    result = install("8.7", nil, { [official .. ".sha256"] = { status = 200, body = body } })
    assert(result.sha256 == sha256, label .. ": expected " .. sha256 .. ", got " .. tostring(result.sha256))
    cases = cases + 1
end

-- A 200 that holds no digest, such as the page of a portal or a file cut short, is
-- no checksum: the install stops and names the address, rather than going on to
-- fail with "Checksum error" or without a check.
for label, body in pairs({
    html = "<html><body>Please sign in</body></html>",
    empty = "",
    short = sha256:sub(1, 63),
    long = sha256 .. "0",
}) do
    local ok, err = pcall(install, "8.7", nil, { [official .. ".sha256"] = { status = 200, body = body } })
    local want = "no SHA-256 digest in " .. official .. ".sha256"
    assert(not ok and tostring(err):find(want, 1, true), label .. ": unexpected " .. tostring(err))
    cases = cases + 1
end

-- A mirror is a prefix: the archive and its checksum are asked for there, and
-- services.gradle.org is not asked at all. Slashes at the end of the value are
-- left out, so the README's example with one gives the same URL as without.
local mirrored = "https://mirror.example/gradle/gradle-8.7-bin.zip"
for _, mirror in ipairs({
    "https://mirror.example/gradle",
    "https://mirror.example/gradle/",
    "https://mirror.example/gradle//",
}) do
    result = install("8.7", mirror, { [mirrored .. ".sha256"] = { status = 200, body = sha256 } })
    assert(result.url == mirrored, mirror .. ": expected " .. mirrored .. ", got " .. tostring(result.url))
    assert(result.sha256 == sha256, mirror .. ": sha256 " .. tostring(result.sha256))
    cases = cases + 2
    check_request(mirrored .. ".sha256")
end

result = install("8.7", "http://127.0.0.1:8080", {
    ["http://127.0.0.1:8080/gradle-8.7-bin.zip.sha256"] = { status = 200, body = sha256 },
})
assert(result.url == "http://127.0.0.1:8080/gradle-8.7-bin.zip", "no path: " .. tostring(result.url))
cases = cases + 1

-- A mirror that is only slashes is no mirror.
result = install("8.7", "/", { [official .. ".sha256"] = { status = 200, body = sha256 } })
assert(result.url == official, "slash only: " .. tostring(result.url))
cases = cases + 1

-- 404 for the checksum: a release that does not exist, or a mirror that keeps no
-- .sha256 files. The hook still names the archive and gives no digest, so vfox
-- warns that it cannot verify and the download decides (404 ends the install
-- with "source file not found").
local missing = "https://services.gradle.org/distributions/gradle-8.99-bin.zip"
result = install("8.99", nil, { [missing .. ".sha256"] = { status = 404, body = "" } })
assert(result.url == missing, "404: " .. tostring(result.url))
assert(result.sha256 == nil, "404: expected no sha256, got " .. tostring(result.sha256))
cases = cases + 2

-- Any other status stops the install with a message that names the status and
-- the address. The hook used to return nothing, and vfox printed only "no
-- installable runtime provided".
for _, status in ipairs({ 403, 500, 502, 567 }) do
    local ok, err = pcall(install, "8.7", "https://mirror.example/gradle", {
        [mirrored .. ".sha256"] = { status = status, body = "<html>denied</html>" },
    })
    local want = "checksum request failed: HTTP " .. status .. " from " .. mirrored .. ".sha256"
    assert(not ok and tostring(err):find(want, 1, true), "status " .. status .. ": unexpected " .. tostring(err))
    cases = cases + 1
end

-- A request that fails stops it too, with the address and what the network said.
-- vfox's http module words the rest ("Get "<url>": ..."), so only the parts the
-- hook and the network contribute are checked.
local ok, err = pcall(install, "8.7", "https://mirror.example/gradle", {
    [mirrored .. ".sha256"] = { transport_error = "dial tcp: lookup mirror.example: no such host" },
})
assert(not ok, "transport error: expected an error")
for _, part in ipairs({ "HTTP request error: ", mirrored .. ".sha256", "lookup mirror.example: no such host" }) do
    assert(tostring(err):find(part, 1, true), "transport error: expected " .. part .. " in " .. tostring(err))
end
cases = cases + 1

print("PASS: " .. cases .. " PreInstall cases")
