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

local function is_windows()
    return RUNTIME ~= nil and RUNTIME.osType == "windows"
end

local function sep()
    if is_windows() then
        return "\\"
    end
    return "/"
end

local function join_path(a, b)
    if a == nil or a == "" or b == nil or b == "" then
        return nil
    end
    return (a:gsub("[/\\]+$", "")) .. sep() .. b
end

local function basename(path)
    if path == nil then
        return nil
    end
    return path:match("([^/\\]+)[/\\]*$")
end

-- Quote a path for the platform shell. On Windows the shell is cmd.exe:
-- vfox 1.0.13 and newer pass the command line through verbatim, so a path with
-- spaces (C:\Users\John Doe\.gradle) is safe in double quotes. Paths that need
-- no quoting stay bare.
local function quote(value)
    if is_windows() then
        if value:find("%s") then
            return '"' .. value .. '"'
        end
        return value
    end
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- Immediate children of a directory, by name. Missing or unreadable directories
-- give an empty list: Detect skips what is not there.
local function list_names(dir)
    if dir == nil or dir == "" then
        return {}
    end
    local command
    if is_windows() then
        command = "dir /b /ad " .. quote(dir) .. " 2>nul"
    else
        command = "ls -1 -- " .. quote(dir) .. " 2>/dev/null"
    end
    local ok, pipe = pcall(io.popen, command)
    if not ok or pipe == nil then
        return {}
    end
    local ok_read, content = pcall(function()
        return pipe:read("*a")
    end)
    pcall(function()
        pipe:close()
    end)
    if not ok_read or content == nil or content == "" then
        return {}
    end
    local names = {}
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
        line = line:match("^(.-)%s*$")
        if line ~= nil and line ~= "" then
            table.insert(names, line)
        end
    end
    return names
end

local function file_exists(path)
    if path == nil then
        return false
    end
    local ok, file = pcall(io.open, path, "r")
    if not ok or file == nil then
        return false
    end
    pcall(function()
        file:close()
    end)
    return true
end

local function is_gradle_home(dir)
    return file_exists(join_path(dir, "bin" .. sep() .. "gradle"))
        or file_exists(join_path(dir, "bin" .. sep() .. "gradle.bat"))
end

-- The version an installed directory holds: its own name ("8.7", "gradle-8.7",
-- "gradle-9.5.1"), or the gradle-launcher jar in its lib directory
-- ("gradle-launcher-9.8.2.jar") where the name carries none ("/usr/share/gradle").
local function version_for_home(dir)
    local version = util:parse_version_from_dirname(basename(dir))
    if version ~= nil then
        return version
    end
    local lib = join_path(dir, "lib")
    for _, name in ipairs(list_names(lib)) do
        version = util:parse_version_from_launcher(name)
        if version ~= nil then
            return version
        end
    end
    return nil
end

--- Finds Gradle installations that vfox did not install, for
--- `vfox link --detect gradle`: SDKMAN!, Homebrew, mise and asdf candidates,
--- system and manual installs (including Chocolatey, Scoop and WinGet on
--- Windows), and the distributions a Gradle wrapper downloaded.
--- Returns `{ version, path, note }` with the version named as `vfox search`
--- names it ("8.7", "9.8.2"). Entries already installed or linked are skipped
--- by vfox itself.
function PLUGIN:Detect(ctx)
    local env = {
        HOME = os.getenv("HOME"),
        USERPROFILE = os.getenv("USERPROFILE"),
        XDG_DATA_HOME = os.getenv("XDG_DATA_HOME"),
        SDKMAN_DIR = os.getenv("SDKMAN_DIR"),
        GRADLE_USER_HOME = os.getenv("GRADLE_USER_HOME"),
        SCOOP = os.getenv("SCOOP"),
        MISE_DATA_DIR = os.getenv("MISE_DATA_DIR"),
        MISE_INSTALLS_DIR = os.getenv("MISE_INSTALLS_DIR"),
        ASDF_DATA_DIR = os.getenv("ASDF_DATA_DIR"),
        ASDF_DIR = os.getenv("ASDF_DIR"),
        LOCALAPPDATA = os.getenv("LOCALAPPDATA"),
        ProgramFiles = os.getenv("ProgramFiles"),
        ProgramW6432 = os.getenv("ProgramW6432"),
        ["ProgramFiles(x86)"] = os.getenv("ProgramFiles(x86)"),
    }
    local roots = util:detect_roots(RUNTIME.osType, env)

    local seen = {}
    local found = {}
    local function add(path, note)
        if path == nil then
            return
        end
        local version = version_for_home(path)
        if version == nil or seen[version] then
            return
        end
        seen[version] = true
        table.insert(found, { version = version, path = path, note = note })
    end

    for _, root in ipairs(roots) do
        if root.kind == "home" then
            if is_gradle_home(root.path) then
                add(root.path, root.note)
            end
        elseif root.kind == "container" then
            for _, name in ipairs(list_names(root.path)) do
                if name ~= "current" and name ~= "latest" then
                    local candidate = join_path(root.path, name)
                    if is_gradle_home(candidate) then
                        add(candidate, root.note)
                    elseif root.nested then
                        -- Some managers keep the home one level down
                        -- (installs/gradle/8.9/gradle-8.9).
                        for _, inner in ipairs(list_names(candidate)) do
                            local nested_candidate = join_path(candidate, inner)
                            if is_gradle_home(nested_candidate) then
                                add(nested_candidate, root.note)
                            end
                        end
                    end
                end
            end
        elseif root.kind == "wrapper" then
            -- wrapper/dists/gradle-9.5.1-bin/<hash>/gradle-9.5.1: the outer name
            -- carries the version, the hash directory a ".ok" marker when the
            -- download finished, and the inner directory is the Gradle home.
            for _, outer in ipairs(list_names(root.path)) do
                local outer_version = util:parse_version_from_dirname(outer)
                if outer_version ~= nil then
                    local outer_dir = join_path(root.path, outer)
                    for _, hash in ipairs(list_names(outer_dir)) do
                        local hash_dir = join_path(outer_dir, hash)
                        if file_exists(join_path(hash_dir, outer .. ".zip.ok")) then
                            for _, inner in ipairs(list_names(hash_dir)) do
                                local candidate = join_path(hash_dir, inner)
                                if is_gradle_home(candidate) then
                                    add(candidate, root.note)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return found
end
