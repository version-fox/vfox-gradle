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
local plugin = test.load({
    os = "linux",
    arch = "amd64",
    env = {
        HOME = "/home/me",
        GRADLE_USER_HOME = false,
        SDKMAN_DIR = false,
    },
})
local util = require("util")

-- vfox 1.0.13 and older do not know the Detect hook: the core never loads
-- hooks/detect.lua and the test proxy has no Detect method. Load the file
-- directly and call PLUGIN instead, so the same assertions run on both.
local function call_detect()
    if plugin.Detect ~= nil then
        return plugin:Detect({})
    end
    dofile(RUNTIME.pluginDirPath .. "/hooks/detect.lua")
    return PLUGIN:Detect({})
end

local cases = 0

-- Directory basenames: the version itself, gradle-<version>, or a wrapper dist
-- with -bin/-all. Anything without a leading digit is not a version.
local function check_dirname(basename, expected)
    assert(
        util:parse_version_from_dirname(basename) == expected,
        basename
            .. ": expected "
            .. tostring(expected)
            .. ", got "
            .. tostring(util:parse_version_from_dirname(basename))
    )
    cases = cases + 1
end

check_dirname("8.7", "8.7")
check_dirname("9.8.2", "9.8.2")
check_dirname("gradle-8.7", "8.7")
check_dirname("gradle-9.5.1", "9.5.1")
check_dirname("gradle-9.5.1-bin", "9.5.1")
check_dirname("gradle-8.7-all", "8.7")
check_dirname("gradle-8.7-rc-1", "8.7-rc-1")
check_dirname("gradle-8.7-rc-1-bin", "8.7-rc-1")
check_dirname("current", nil)
check_dirname("latest", nil)
check_dirname("bin", nil)
check_dirname("tools", nil)
check_dirname("", nil)

-- The launcher jar in lib/ names the version where the directory does not.
local function check_launcher(filename, expected)
    assert(
        util:parse_version_from_launcher(filename) == expected,
        filename
            .. ": expected "
            .. tostring(expected)
            .. ", got "
            .. tostring(util:parse_version_from_launcher(filename))
    )
    cases = cases + 1
end

check_launcher("gradle-launcher-9.8.2.jar", "9.8.2")
check_launcher("gradle-launcher-8.7.jar", "8.7")
check_launcher("gradle-launcher.properties", nil)
check_launcher("ant-launcher-1.10.17.jar", nil)

-- vfox names a link like a version: letters, digits, '.', '_', '+' and '-',
-- starting with a letter or digit, and never "latest".
assert(util:is_valid_version_name("8.7"), "8.7 should be valid")
assert(util:is_valid_version_name("9.8.2"), "9.8.2 should be valid")
assert(util:is_valid_version_name("8.7-rc-1"), "8.7-rc-1 should be valid")
assert(not util:is_valid_version_name("latest"), "latest should be invalid")
assert(not util:is_valid_version_name(""), "empty should be invalid")
assert(not util:is_valid_version_name("a/b"), "a/b should be invalid")
assert(not util:is_valid_version_name("-x"), "-x should be invalid")
cases = cases + 7

-- The roots to scan come from the environment, with SDKMAN_DIR winning over
-- ~/.sdkman and GRADLE_USER_HOME over ~/.gradle.
local function has_root(roots, path, kind)
    for _, root in ipairs(roots) do
        if root.path == path and root.kind == kind then
            return true
        end
    end
    return false
end

local linux_roots = util:detect_roots("linux", { HOME = "/home/me" })
assert(has_root(linux_roots, "/home/me/.sdkman/candidates/gradle", "container"), "sdkman container missing")
assert(has_root(linux_roots, "/opt/homebrew/Cellar/gradle", "container"), "brew container missing")
assert(has_root(linux_roots, "/home/me/.local/share/mise/installs/gradle", "container"), "mise container missing")
assert(has_root(linux_roots, "/home/me/.asdf/installs/gradle", "container"), "asdf container missing")
assert(has_root(linux_roots, "/usr/share/gradle", "home"), "system home missing")
assert(has_root(linux_roots, "/home/me/.gradle/wrapper/dists", "wrapper"), "wrapper dists missing")
cases = cases + 6

local sdkman_roots = util:detect_roots("linux", { HOME = "/home/me", SDKMAN_DIR = "/opt/sdkman" })
assert(has_root(sdkman_roots, "/opt/sdkman/candidates/gradle", "container"), "SDKMAN_DIR not honored")
cases = cases + 1

local data_dir_roots = util:detect_roots("linux", {
    HOME = "/home/me",
    MISE_DATA_DIR = "/opt/mise",
    ASDF_DATA_DIR = "/opt/asdf",
})
assert(has_root(data_dir_roots, "/opt/mise/installs/gradle", "container"), "MISE_DATA_DIR not honored")
assert(has_root(data_dir_roots, "/opt/asdf/installs/gradle", "container"), "ASDF_DATA_DIR not honored")
local xdg_roots = util:detect_roots("linux", { HOME = "/home/me", XDG_DATA_HOME = "/home/me/.xdg" })
assert(has_root(xdg_roots, "/home/me/.xdg/mise/installs/gradle", "container"), "XDG_DATA_HOME not honored")
cases = cases + 3

local windows_roots = util:detect_roots("windows", {
    USERPROFILE = "C:\\Users\\me",
    ProgramFiles = "C:\\Program Files",
    SCOOP = "C:\\scoop",
})
assert(has_root(windows_roots, "C:\\Program Files\\Gradle", "container"), "Program Files container missing")
assert(has_root(windows_roots, "C:\\Gradle", "container"), "C:\\Gradle container missing")
assert(has_root(windows_roots, "C:\\scoop\\apps\\gradle", "container"), "scoop container missing")
assert(
    has_root(windows_roots, "C:\\Users\\me\\AppData\\Local\\mise\\installs\\gradle", "container"),
    "windows mise container missing"
)
assert(has_root(windows_roots, "C:\\Users\\me\\.asdf\\installs\\gradle", "container"), "windows asdf container missing")
assert(
    has_root(windows_roots, "C:\\Users\\me\\AppData\\Local\\Microsoft\\WinGet\\Packages", "container"),
    "WinGet container missing"
)
assert(has_root(windows_roots, "C:\\Users\\me\\.gradle\\wrapper\\dists", "wrapper"), "windows wrapper dists missing")
cases = cases + 7

local local_app_data_roots = util:detect_roots("windows", {
    USERPROFILE = "C:\\Users\\me",
    LOCALAPPDATA = "D:\\Local",
})
assert(
    has_root(local_app_data_roots, "D:\\Local\\Microsoft\\WinGet\\Packages", "container"),
    "LOCALAPPDATA not honored"
)
assert(
    has_root(local_app_data_roots, "D:\\Local\\mise\\installs\\gradle", "container"),
    "windows MISE_DATA_DIR fallback wrong"
)
cases = cases + 2

-- Detect scans the faked machine: SDKMAN! holds 8.7 and 9.8.2 (plus a "current"
-- link that is skipped), /opt holds gradle-8.14, /usr/share/gradle holds an
-- install whose directory carries no version (read from its launcher jar),
-- mise holds 8.10 directly and 8.9 one level down (installs/gradle/8.9/gradle-8.9),
-- asdf holds 8.5, and the wrapper holds a finished 9.5.1 (with .ok) and an
-- unfinished 9.6 (without).
local listings = {
    ["/home/me/.sdkman/candidates/gradle"] = "8.7\n9.8.2\ncurrent\n",
    ["/opt/homebrew/Cellar/gradle"] = "",
    ["/usr/local/Cellar/gradle"] = "",
    ["/home/linuxbrew/.linuxbrew/Cellar/gradle"] = "",
    ["/home/me/.linuxbrew/Cellar/gradle"] = "",
    ["/home/me/.local/share/mise/installs/gradle"] = "8.10\n8.9\n",
    ["/home/me/.local/share/mise/installs/gradle/8.9"] = "gradle-8.9\n",
    ["/home/me/.asdf/installs/gradle"] = "8.5\n",
    ["/opt"] = "gradle-8.14\nfoo\n",
    ["/usr/local"] = "bin\n",
    ["/home/me/.gradle/wrapper/dists"] = "gradle-9.5.1-bin\ngradle-9.6-bin\n",
    ["/home/me/.gradle/wrapper/dists/gradle-9.5.1-bin"] = "iq79hdu3mqx29lgffhp8bfmx\n",
    ["/home/me/.gradle/wrapper/dists/gradle-9.5.1-bin/iq79hdu3mqx29lgffhp8bfmx"] = "gradle-9.5.1\n",
    ["/home/me/.gradle/wrapper/dists/gradle-9.6-bin"] = "aaaa\n",
    ["/home/me/.gradle/wrapper/dists/gradle-9.6-bin/aaaa"] = "gradle-9.6\n",
    ["/usr/share/gradle/lib"] = "gradle-launcher-7.6.6.jar\n",
    ["/opt/gradle/lib"] = "",
    ["/usr/local/gradle/lib"] = "",
}
local homes = {
    ["/home/me/.sdkman/candidates/gradle/8.7"] = true,
    ["/home/me/.sdkman/candidates/gradle/9.8.2"] = true,
    ["/home/me/.local/share/mise/installs/gradle/8.10"] = true,
    ["/home/me/.local/share/mise/installs/gradle/8.9/gradle-8.9"] = true,
    ["/home/me/.asdf/installs/gradle/8.5"] = true,
    ["/opt/gradle-8.14"] = true,
    ["/usr/share/gradle"] = true,
    ["/home/me/.gradle/wrapper/dists/gradle-9.5.1-bin/iq79hdu3mqx29lgffhp8bfmx/gradle-9.5.1"] = true,
    ["/home/me/.gradle/wrapper/dists/gradle-9.6-bin/aaaa/gradle-9.6"] = true,
}
local ok_files = {
    ["/home/me/.gradle/wrapper/dists/gradle-9.5.1-bin/iq79hdu3mqx29lgffhp8bfmx/gradle-9.5.1-bin.zip.ok"] = true,
}

local original_popen = io.popen
local original_open = io.open
io.popen = function(command)
    local dir = command:match("'([^']+)'")
    local output = dir and listings[dir] or ""
    return {
        read = function(_, _)
            return output
        end,
        close = function() end,
    }
end
io.open = function(path, _)
    if homes[path:gsub("/bin/gradle%.bat$", ""):gsub("/bin/gradle$", "")] and path:find("/bin/gradle", 1, true) then
        return { close = function() end }
    end
    if path:find("gradle%-launcher%-", 1, true) then
        return nil
    end
    if ok_files[path] then
        return { close = function() end }
    end
    if path == "/usr/share/gradle/bin/gradle" then
        return { close = function() end }
    end
    return original_open(path, "r")
end

local found = call_detect()
io.popen = original_popen
io.open = original_open

local function by_version(list)
    local map = {}
    for _, entry in ipairs(list) do
        map[entry.version] = entry
    end
    return map
end

local got = by_version(found)
for _, version in ipairs({ "8.7", "9.8.2", "8.10", "8.9", "8.5", "8.14", "7.6.6", "9.5.1" }) do
    assert(got[version] ~= nil, version .. " should be detected, got: " .. #found)
    cases = cases + 1
end
-- The unfinished wrapper download (no .ok) is skipped, and "current" never
-- becomes a version.
assert(got["9.6"] == nil, "unfinished wrapper dist should be skipped")
assert(got["current"] == nil, "current should be skipped")
cases = cases + 2
-- Each entry carries the directory EnvKeys expects and a note.
assert(
    got["8.7"].path == "/home/me/.sdkman/candidates/gradle/8.7",
    "8.7 path: " .. tostring(got["8.7"] and got["8.7"].path)
)
assert(got["8.7"].note ~= nil and got["8.7"].note ~= "", "8.7 should have a note")
assert(
    got["9.5.1"].path:find("wrapper/dists", 1, true) ~= nil,
    "9.5.1 should come from the wrapper: " .. tostring(got["9.5.1"].path)
)
assert(got["8.10"].note == "via mise", "8.10 note: " .. tostring(got["8.10"].note))
assert(got["8.5"].note == "via asdf", "8.5 note: " .. tostring(got["8.5"].note))
assert(
    got["8.9"].path == "/home/me/.local/share/mise/installs/gradle/8.9/gradle-8.9",
    "8.9 path: " .. tostring(got["8.9"] and got["8.9"].path)
)
cases = cases + 6

print("PASS: " .. cases .. " Detect cases")
