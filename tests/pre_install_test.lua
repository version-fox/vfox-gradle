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

-- Every request the hook made, in the order it made them.
local function check_requests(expected)
    local want = {}
    for i, url in ipairs(expected) do
        want[i] = "GET " .. url
    end
    local got = table.concat(state.requests, ", ")
    assert(got == table.concat(want, ", "), "expected " .. table.concat(want, ", ") .. ", got " .. got)
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

-- 404 for the checksum with no mirror: a release that does not exist. The hook
-- still names the archive and gives no digest, so vfox warns that it cannot verify
-- and the download decides (404 ends the install with "source file not found").
-- services.gradle.org has just been asked, so it is not asked a second time.
local missing = "https://services.gradle.org/distributions/gradle-8.99-bin.zip"
result = install("8.99", nil, { [missing .. ".sha256"] = { status = 404, body = "" } })
assert(result.url == missing, "404: " .. tostring(result.url))
assert(result.sha256 == nil, "404: expected no sha256, got " .. tostring(result.sha256))
cases = cases + 2
check_request(missing .. ".sha256")

-- 404 at a mirror: it keeps no .sha256 files (Tencent Cloud's has none for the
-- releases after 8.0.1), or it does not carry the release. With no digest vfox warns
-- and trusts the download, so the hook asks services.gradle.org for the digest of the
-- same file, and vfox verifies the mirror's copy against the one Gradle publishes. The
-- archive stays the mirror's. The mirror is asked first, and services.gradle.org once,
-- after it.
local mirrored_sum = mirrored .. ".sha256"
local official_sum = official .. ".sha256"
for _, mirror in ipairs({ "https://mirror.example/gradle", "https://mirror.example/gradle/" }) do
    result = install("8.7", mirror, {
        [mirrored_sum] = { status = 404, body = "" },
        [official_sum] = { status = 200, body = sha256 },
    })
    assert(result.url == mirrored, mirror .. ": the archive is the mirror's, got " .. tostring(result.url))
    assert(result.sha256 == sha256, mirror .. ": sha256 " .. tostring(result.sha256))
    cases = cases + 2
    check_requests({ mirrored_sum, official_sum })
end

-- The digest of Gradle goes through the same reading as a mirror's would.
result = install("8.7", "https://mirror.example/gradle", {
    [mirrored_sum] = { status = 404, body = "" },
    [official_sum] = { status = 200, body = sha256:upper() .. "  gradle-8.7-bin.zip\n" },
})
assert(result.sha256 == sha256, "sha256sum format from Gradle: " .. tostring(result.sha256))
cases = cases + 1

-- A mirror that is services.gradle.org has answered already: no second request.
result = install("8.99", "https://services.gradle.org/distributions/", {
    [missing .. ".sha256"] = { status = 404, body = "" },
})
assert(result.url == missing, "mirror that is Gradle: " .. tostring(result.url))
assert(result.sha256 == nil, "mirror that is Gradle: expected no sha256, got " .. tostring(result.sha256))
cases = cases + 2
check_request(missing .. ".sha256")

-- services.gradle.org gives no digest either: not a 404, a refusal, a page in place
-- of the file, a network that blocks it. It was not the server asked for, so none of
-- this stops the install. The hook goes on without a digest as it does for any mirror
-- that has none: vfox warns, and the download decides.
for label, answer in pairs({
    ["404"] = { status = 404, body = "" },
    ["403"] = { status = 403, body = "<html>denied</html>" },
    ["500"] = { status = 500, body = "" },
    ["567"] = { status = 567, body = "<html>denied</html>" },
    ["a page"] = { status = 200, body = "<html><body>Please sign in</body></html>" },
    ["empty"] = { status = 200, body = "" },
    ["short"] = { status = 200, body = sha256:sub(1, 63) },
    ["network"] = { transport_error = "dial tcp 104.18.0.1:443: i/o timeout" },
}) do
    result = install("8.7", "https://mirror.example/gradle", {
        [mirrored_sum] = { status = 404, body = "" },
        [official_sum] = answer,
    })
    assert(result.url == mirrored, label .. ": the archive is the mirror's, got " .. tostring(result.url))
    assert(result.sha256 == nil, label .. ": expected no sha256, got " .. tostring(result.sha256))
    cases = cases + 2
    check_requests({ mirrored_sum, official_sum })
end

-- Any other status stops the install with a message that names the status and
-- the address. The hook used to return nothing, and vfox printed only "no
-- installable runtime provided". The mirror was asked for and it is at fault, so
-- services.gradle.org is not asked for a digest in its place.
for _, status in ipairs({ 403, 500, 502, 567 }) do
    local ok, err = pcall(install, "8.7", "https://mirror.example/gradle", {
        [mirrored_sum] = { status = status, body = "<html>denied</html>" },
    })
    local want = "checksum request failed: HTTP " .. status .. " from " .. mirrored_sum
    assert(not ok and tostring(err):find(want, 1, true), "status " .. status .. ": unexpected " .. tostring(err))
    check_requests({ mirrored_sum })
    cases = cases + 1
end

-- A 200 from the mirror that holds no digest is the page of a portal, or a file cut
-- short, and stops it as well: another server's digest would hide that.
local ok, err = pcall(install, "8.7", "https://mirror.example/gradle", {
    [mirrored_sum] = { status = 200, body = "<html><body>Please sign in</body></html>" },
})
assert(
    not ok and tostring(err):find("no SHA-256 digest in " .. mirrored_sum, 1, true),
    "portal: unexpected " .. tostring(err)
)
check_requests({ mirrored_sum })
cases = cases + 1

-- A request that fails stops it too, with the address and what the network said.
-- vfox's http module words the rest ("Get "<url>": ..."), so only the parts the
-- hook and the network contribute are checked.
ok, err = pcall(install, "8.7", "https://mirror.example/gradle", {
    [mirrored_sum] = { transport_error = "dial tcp: lookup mirror.example: no such host" },
})
assert(not ok, "transport error: expected an error")
for _, part in ipairs({ "HTTP request error: ", mirrored_sum, "lookup mirror.example: no such host" }) do
    assert(tostring(err):find(part, 1, true), "transport error: expected " .. part .. " in " .. tostring(err))
end
check_requests({ mirrored_sum })
cases = cases + 1

print("PASS: " .. cases .. " PreInstall cases")
