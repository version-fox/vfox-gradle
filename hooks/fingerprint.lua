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

--- Records what identifies an installed Gradle: the launcher jar named in
--- lib/gradle-launcher.properties (jarFile=gradle-launcher-9.8.2.jar). The
--- distribution never changes itself after it is unpacked, so equal facts mean
--- the install is intact; a swapped or damaged lib directory shows up as drift
--- (or as unreadable), fixed by `vfox install --reinstall`.
--- One small file read, no processes, no network. Forward slashes work on
--- Windows too, so there is no separator handling.
function PLUGIN:Fingerprint(ctx)
    local path = ctx.path
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local file = io.open(path .. "/lib/gradle-launcher.properties", "r")
    if file == nil then
        return nil
    end
    local jar
    for line in file:lines() do
        local value = line:match("^%s*jarFile%s*=%s*(.-)%s*$")
        if value ~= nil and value ~= "" then
            jar = value
        end
    end
    file:close()
    if jar == nil then
        return nil
    end
    return {
        facts = {
            launcher = jar,
        },
    }
end
