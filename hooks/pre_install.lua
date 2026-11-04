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

    local checksumUrl = downloadUrl .. ".sha256"
    local resp, err = http.get({
        url = checksumUrl,
    })

    if err then
        error("HTTP request error: " .. err)
    end

    if resp.status_code == 200 then
        if resp.body then
            -- Gradle's file holds the digest and nothing else. vfox compares the text it gets
            -- with the hash of the download as it stands, so the file of a mirror that has a
            -- newline after the digest, capitals, or the format of sha256sum ("<digest>  <file>")
            -- would fail a good download. Take the digest out, in lower case.
            local digest = resp.body:match("^%s*(%x+)")
            if digest == nil or #digest ~= 64 then
                error(("no SHA-256 digest in %s"):format(checksumUrl))
            end
            result.sha256 = digest:lower()
        else
            error("Empty body in HTTP response")
        end
    elseif resp.status_code == 404 then
        -- A release that does not exist, or a mirror that keeps no .sha256 files.
        -- Go on without a checksum: vfox warns, and the download decides.
    else
        -- Returning nothing here made vfox print only "no installable runtime provided".
        error(("checksum request failed: HTTP %d from %s"):format(resp.status_code, checksumUrl))
    end

    return result
end
