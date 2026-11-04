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
local os = require("os")
local http = require("http")

--- @class PreInstallContext
--- @field version string User-input version

--- Reads the SHA-256 digest that a server keeps at `url`.
--- Gradle's file holds the digest and nothing else. vfox compares the text it gets
--- with the hash of the download as it stands, so the file of a mirror that has a
--- newline after the digest, capitals, or the format of sha256sum ("<digest>  <file>")
--- would fail a good download. Take the digest out, in lower case.
---
--- There are three outcomes, and the caller decides what each is worth:
--- a digest; neither a digest nor a problem, which is the 404 of a server that keeps
--- no such file; and no digest with a problem, the message of a request or an answer
--- that is no good.
--- @param url string
--- @return string|nil digest
--- @return string|nil problem
local function read_digest(url)
    local resp, err = http.get({
        url = url,
    })
    if err then
        return nil, "HTTP request error: " .. err
    end

    if resp.status_code == 200 then
        if resp.body then
            local digest = resp.body:match("^%s*(%x+)")
            if digest == nil or #digest ~= 64 then
                return nil, ("no SHA-256 digest in %s"):format(url)
            end
            return digest:lower(), nil
        end
        return nil, "Empty body in HTTP response"
    elseif resp.status_code == 404 then
        return nil, nil
    end
    -- Returning nothing for these made vfox print only "no installable runtime provided".
    return nil, ("checksum request failed: HTTP %d from %s"):format(resp.status_code, url)
end

--- Returns some pre-installed information, such as version number, download address, local files, etc.
--- If checksum is provided, vfox will automatically check it for you.
--- @param ctx PreInstallContext
--- @return table Version information
function PLUGIN:PreInstall(ctx)
    local result = {}
    local version = ctx.version
    result.version = version

    local downloadUrl = ""
    -- A mirror is a prefix of the file name. Slashes at the end of the value are left
    -- out, so "https://mirror.example/gradle/" does not ask for "gradle//gradle-...".
    local mirrorUrl = os.getenv("VFOX_GRADLE_MIRRORS")
    if mirrorUrl ~= nil then
        mirrorUrl = mirrorUrl:gsub("/+$", "")
    end

    if mirrorUrl ~= nil and mirrorUrl ~= "" then
        downloadUrl = mirrorUrl .. "/gradle-" .. version .. "-bin.zip"
    else
        downloadUrl = util.DownloadInfoUrl:format(version)
    end

    result.url = downloadUrl
    -- vfox downloads the archive itself, as Go-http-client/1.1 unless told another name.
    -- Some mirrors answer that with 403 and a page of HTML, which vfox saves as the
    -- archive and then reports as "Checksum error". The request for the checksum below
    -- goes out as "vfox/<version> vfox-gradle/<version>", and so does the download.
    result.headers = util:download_headers()

    -- The digest is asked for where the archive is. Any answer but a digest or a 404 stops
    -- the install: falling back to another server would hide the fault of the mirror.
    local checksumUrl = downloadUrl .. ".sha256"
    local digest, problem = read_digest(checksumUrl)
    if problem then
        error(problem)
    end

    -- A 404 is a release that does not exist, or a mirror that keeps no .sha256 files
    -- (Tencent Cloud's has none for the releases after 8.0.1). Without a digest vfox
    -- warns and trusts the download, so ask services.gradle.org for the digest of the
    -- same file: a mirror holds copies, and the copy is verified against the digest
    -- Gradle publishes. That server was not the one asked for, and a network that needs
    -- a mirror may block it, so if it gives no digest either, go on without one: vfox
    -- warns, and the download decides.
    if digest == nil then
        local officialChecksumUrl = util.DownloadInfoUrl:format(version) .. ".sha256"
        if officialChecksumUrl ~= checksumUrl then
            digest = read_digest(officialChecksumUrl)
        end
    end
    result.sha256 = digest

    return result
end
