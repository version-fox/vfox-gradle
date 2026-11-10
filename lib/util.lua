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

local Util = {}

Util.__index = Util

local UtilSingleton = setmetatable({}, Util)
UtilSingleton.AvailableVersionsUrl = "https://gradle.org/releases/"
UtilSingleton.DownloadInfoUrl = "https://services.gradle.org/distributions/gradle-%s-bin.zip"

function Util:compare_versions(v1o, v2o)
    local v1 = v1o.version
    local v2 = v2o.version
    local v1_parts = {}
    for part in string.gmatch(v1, "[^.]+") do
        table.insert(v1_parts, tonumber(part))
    end

    local v2_parts = {}
    for part in string.gmatch(v2, "[^.]+") do
        table.insert(v2_parts, tonumber(part))
    end

    for i = 1, math.max(#v1_parts, #v2_parts) do
        local v1_part = v1_parts[i] or 0
        local v2_part = v2_parts[i] or 0
        if v1_part > v2_part then
            return true
        elseif v1_part < v2_part then
            return false
        end
    end

    return false
end

--- Headers that vfox sends with the download of the archive. Without them vfox
--- identifies itself with the User-Agent of Go's HTTP client, `Go-http-client/1.1`,
--- and some mirrors (Huawei Cloud's) answer that with an error page in place of the
--- archive: vfox saves the answer and the install ends in `Checksum error`. The
--- requests of the plugin itself carry the User-Agent that vfox builds for it,
--- `vfox/<vfox version> vfox-gradle/<plugin version>`, so the download sends the
--- same, worded as vfox's `ComputeUserAgent` words it: `vfox` alone and no version
--- where vfox gives none.
--- @return table<string, string>
function Util:download_headers()
    local function present(value)
        return value ~= nil and value ~= ""
    end
    local name = "vfox-gradle"
    if PLUGIN ~= nil and present(PLUGIN.name) then
        name = PLUGIN.name:sub(1, 5) == "vfox-" and PLUGIN.name or "vfox-" .. PLUGIN.name
    end
    if PLUGIN ~= nil and present(PLUGIN.version) then
        name = name .. "/" .. PLUGIN.version
    end
    local runtime = "vfox"
    if RUNTIME ~= nil and present(RUNTIME.version) then
        runtime = runtime .. "/" .. RUNTIME.version
    end
    return { ["User-Agent"] = runtime .. " " .. name }
end

--- Whether a version name can be linked (`vfox link --detect` names what it finds).
--- vfox allows letters, digits, '.', '_', '+' and '-', starting with a letter or
--- digit, and not "latest".
--- @param version string
--- @return boolean
function Util:is_valid_version_name(version)
    if type(version) ~= "string" or version == "" or version == "latest" then
        return false
    end
    return version:match("^[A-Za-z0-9][A-Za-z0-9._+%-]*$") ~= nil
end

--- Version from a directory basename: "8.7" itself, "gradle-8.7", or
--- "gradle-9.5.1-bin" / "gradle-8.7-all" (the "-bin" / "-all" of a wrapper dist).
--- Returns nil where the name holds no version.
--- @param basename string
--- @return string|nil
function Util:parse_version_from_dirname(basename)
    if type(basename) ~= "string" or basename == "" then
        return nil
    end
    local version = basename:match("^gradle%-(.+)$") or basename
    -- A wrapper dist appends the distribution to the version: gradle-9.5.1-bin.
    version = version:gsub("%-bin$", ""):gsub("%-all$", "")
    if version == "" or version == "latest" or version == "current" then
        return nil
    end
    -- A bare word like "bin" or "tools" is not a version; Gradle releases start
    -- with a digit ("8.7", "9.8.2", "8.7-rc-1").
    if not version:match("^%d") then
        return nil
    end
    if not self:is_valid_version_name(version) then
        return nil
    end
    return version
end

--- Version from "gradle-launcher-9.8.2.jar" in the lib directory of an install.
--- @param filename string
--- @return string|nil
function Util:parse_version_from_launcher(filename)
    if type(filename) ~= "string" then
        return nil
    end
    local version = filename:match("^gradle%-launcher%-(.+)%.jar$")
    if version == nil or not self:is_valid_version_name(version) then
        return nil
    end
    return version
end

local function join_path(osType, a, b)
    if a == nil or a == "" or b == nil or b == "" then
        return nil
    end
    local sep = osType == "windows" and "\\" or "/"
    return (a:gsub("[/\\]+$", "")) .. sep .. b
end

local function add_root(roots, seen, path, kind, note, nested)
    if path == nil or path == "" or seen[path] then
        return
    end
    seen[path] = true
    table.insert(roots, { path = path, kind = kind, note = note, nested = nested or false })
end

--- Where mise keeps its data: MISE_DATA_DIR, else XDG_DATA_HOME/mise,
--- else ~/.local/share/mise. MISE_INSTALLS_DIR moves installs/ on its own.
local function mise_data_dir(osType, env, home)
    if env.MISE_DATA_DIR ~= nil and env.MISE_DATA_DIR ~= "" then
        return env.MISE_DATA_DIR
    end
    if not (osType == "windows") then
        local xdg = env.XDG_DATA_HOME
        if xdg ~= nil and xdg ~= "" then
            return join_path(osType, xdg, "mise")
        end
    end
    if home == nil or home == "" then
        return nil
    end
    if osType == "windows" then
        local local_app_data = env.LOCALAPPDATA
        if (local_app_data == nil or local_app_data == "") and home ~= nil and home ~= "" then
            local_app_data = join_path(osType, home, "AppData\\Local")
        end
        if local_app_data ~= nil and local_app_data ~= "" then
            return join_path(osType, local_app_data, "mise")
        end
        return nil
    end
    return join_path(osType, home, ".local/share/mise")
end

--- Where asdf keeps its data: ASDF_DATA_DIR (older ASDF_DIR), else ~/.asdf.
local function asdf_data_dir(osType, env, home)
    local dir = env.ASDF_DATA_DIR
    if dir == nil or dir == "" then
        dir = env.ASDF_DIR
    end
    if (dir == nil or dir == "") and home ~= nil and home ~= "" then
        dir = join_path(osType, home, ".asdf")
    end
    if dir == nil or dir == "" then
        return nil
    end
    return dir
end

--- Roots to scan for existing Gradle installations, for `vfox link --detect`.
--- `env` maps variable names to values (nil where unset), so tests can pass a
--- table instead of the real environment.
--- Each root is `{ path, kind, note }` where kind is "container" (each immediate
--- child may be a Gradle home), "home" (itself may be one), or "wrapper" (a
--- `wrapper/dists` directory whose grandchildren may be). A container with
--- `nested` also checks one level deeper, for managers whose version directory
--- holds the home in a subdirectory instead of being the home itself.
--- @param osType string "linux", "darwin" or "windows"
--- @param env table<string, string|nil>
--- @return table
function Util:detect_roots(osType, env)
    env = env or {}
    local roots = {}
    local seen = {}
    local windows = osType == "windows"
    local home = windows and (env.USERPROFILE or env.HOME) or (env.HOME or env.USERPROFILE)

    if windows then
        local program_files = {}
        if env.ProgramFiles ~= nil and env.ProgramFiles ~= "" then
            table.insert(program_files, env.ProgramFiles)
        end
        if env["ProgramW6432"] ~= nil and env["ProgramW6432"] ~= "" then
            table.insert(program_files, env["ProgramW6432"])
        end
        if env["ProgramFiles(x86)"] ~= nil and env["ProgramFiles(x86)"] ~= "" then
            table.insert(program_files, env["ProgramFiles(x86)"])
        end
        for _, base in ipairs(program_files) do
            add_root(roots, seen, join_path(osType, base, "Gradle"), "container", "via an installer")
        end
        add_root(roots, seen, "C:\\Gradle", "container", "in C:\\Gradle")
        local scoop = env.SCOOP
        if (scoop == nil or scoop == "") and home ~= nil and home ~= "" then
            scoop = join_path(osType, home, "scoop")
        end
        if scoop ~= nil and scoop ~= "" then
            add_root(roots, seen, join_path(osType, scoop, "apps\\gradle"), "container", "via Scoop")
        end
        add_root(roots, seen, "C:\\ProgramData\\chocolatey\\lib\\gradle\\tools", "container", "via Chocolatey")
        local mise_data = mise_data_dir(osType, env, home)
        if env.MISE_INSTALLS_DIR ~= nil and env.MISE_INSTALLS_DIR ~= "" then
            add_root(roots, seen, join_path(osType, env.MISE_INSTALLS_DIR, "gradle"), "container", "via mise", true)
        elseif mise_data ~= nil and mise_data ~= "" then
            add_root(roots, seen, join_path(osType, mise_data, "installs\\gradle"), "container", "via mise", true)
        end
        local asdf_data = asdf_data_dir(osType, env, home)
        if asdf_data ~= nil and asdf_data ~= "" then
            add_root(roots, seen, join_path(osType, asdf_data, "installs\\gradle"), "container", "via asdf", true)
        end
        local local_app_data = env.LOCALAPPDATA
        if (local_app_data == nil or local_app_data == "") and home ~= nil and home ~= "" then
            local_app_data = join_path(osType, home, "AppData\\Local")
        end
        if local_app_data ~= nil and local_app_data ~= "" then
            add_root(
                roots,
                seen,
                join_path(osType, local_app_data, "Microsoft\\WinGet\\Packages"),
                "container",
                "via WinGet"
            )
        end
        local user_gradle = env.GRADLE_USER_HOME
        if (user_gradle == nil or user_gradle == "") and home ~= nil and home ~= "" then
            user_gradle = join_path(osType, home, ".gradle")
        end
        if user_gradle ~= nil and user_gradle ~= "" then
            add_root(roots, seen, join_path(osType, user_gradle, "wrapper\\dists"), "wrapper", "from a Gradle wrapper")
        end
    else
        local sdkman = env.SDKMAN_DIR
        if (sdkman == nil or sdkman == "") and home ~= nil and home ~= "" then
            sdkman = join_path(osType, home, ".sdkman")
        end
        if sdkman ~= nil and sdkman ~= "" then
            add_root(roots, seen, join_path(osType, sdkman, "candidates/gradle"), "container", "via SDKMAN!")
        end
        add_root(roots, seen, "/opt/homebrew/Cellar/gradle", "container", "via Homebrew")
        add_root(roots, seen, "/usr/local/Cellar/gradle", "container", "via Homebrew")
        add_root(roots, seen, "/home/linuxbrew/.linuxbrew/Cellar/gradle", "container", "via Homebrew")
        if home ~= nil and home ~= "" then
            add_root(roots, seen, join_path(osType, home, ".linuxbrew/Cellar/gradle"), "container", "via Homebrew")
        end
        local mise_data = mise_data_dir(osType, env, home)
        if env.MISE_INSTALLS_DIR ~= nil and env.MISE_INSTALLS_DIR ~= "" then
            add_root(roots, seen, join_path(osType, env.MISE_INSTALLS_DIR, "gradle"), "container", "via mise", true)
        elseif mise_data ~= nil and mise_data ~= "" then
            add_root(roots, seen, join_path(osType, mise_data, "installs/gradle"), "container", "via mise", true)
        end
        local asdf_data = asdf_data_dir(osType, env, home)
        if asdf_data ~= nil and asdf_data ~= "" then
            add_root(roots, seen, join_path(osType, asdf_data, "installs/gradle"), "container", "via asdf", true)
        end
        add_root(roots, seen, "/opt", "container", "in /opt")
        add_root(roots, seen, "/usr/local", "container", "in /usr/local")
        add_root(roots, seen, "/usr/share/gradle", "home", "from the system package manager")
        add_root(roots, seen, "/opt/gradle", "home", "in /opt/gradle")
        add_root(roots, seen, "/usr/local/gradle", "home", "in /usr/local/gradle")
        local user_gradle = env.GRADLE_USER_HOME
        if (user_gradle == nil or user_gradle == "") and home ~= nil and home ~= "" then
            user_gradle = join_path(osType, home, ".gradle")
        end
        if user_gradle ~= nil and user_gradle ~= "" then
            add_root(roots, seen, join_path(osType, user_gradle, "wrapper/dists"), "wrapper", "from a Gradle wrapper")
        end
    end

    return roots
end

return UtilSingleton
