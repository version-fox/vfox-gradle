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

--- !!! DO NOT EDIT OR RENAME !!!
PLUGIN = {}

--- !!! MUST BE SET !!!
--- Plugin name
PLUGIN.name = "gradle"
--- Plugin author
PLUGIN.author = "ahai"
--- Plugin version
PLUGIN.version = "0.1.3"
--- Plugin homepage
PLUGIN.homepage = "https://github.com/version-fox/vfox-gradle"
--- Plugin license, please choose a correct license according to your needs.
PLUGIN.license = "Apache 2.0"
--- Plugin description
PLUGIN.description = "Gradle runtime environment."

--- !!! OPTIONAL !!!
--[[
NOTE:
    Minimum compatible vfox version.
    If the plugin is not compatible with the current vfox version,
    vfox will not load the plugin and prompt the user to upgrade vfox.
 --]]
PLUGIN.minRuntimeVersion = "0.3.0"
--[[
NOTE:
    If configured, vfox will check for updates to the plugin at this address,
    otherwise it will check for updates at the global registry.

    If you want use the global registry to distribute your plugin, you can remove this field.

    If you develop a plugin based on the template, which will automatically generate a manifest file by CI,
    you can set this address to the manifest file address, so that the plugin can be updated automatically.

 --]]
PLUGIN.manifestUrl = "https://github.com/version-fox/vfox-gradle/releases/download/manifest/manifest.json"
--- Gradle projects pin their release in gradle/wrapper/gradle-wrapper.properties;
--- vfox reads its distributionUrl when resolving project versions. A version
--- named in .vfox.toml wins over the wrapper file.
PLUGIN.legacyFilenames = {
    "gradle/wrapper/gradle-wrapper.properties",
}
--- Hints for `vfox doctor` and `vfox use` (vfox 1.1.0 and later) when another
--- Gradle shadows the one vfox selected. Older vfox versions ignore this field.
--- Each entry matches part of the shadowing executable's path (case-insensitive).
--- Detecting the shadowing itself is done by vfox; there is no PATH scan in PreUse.
PLUGIN.shadowHints = {
    {
        match = "sdkman",
        message = "SDKMAN! installed its own Gradle. Run `sdk uninstall gradle` or take its candidate directory out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "mise",
        message = "mise installed its own Gradle (a shim). Run `mise uninstall gradle` or take the shims directory out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "asdf",
        message = "asdf installed its own Gradle (a shim in the shims directory). Run `asdf uninstall gradle` or take the shims directory out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "homebrew",
        message = "Homebrew installed its own Gradle. Run `brew uninstall gradle` or take it out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "cellar",
        message = "Homebrew installed its own Gradle. Run `brew uninstall gradle` or take it out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "linuxbrew",
        message = "Linuxbrew installed its own Gradle. Run `brew uninstall gradle` or take it out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "chocolatey",
        message = "Chocolatey installed its own Gradle. Run `choco uninstall gradle` or take it out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "scoop",
        message = "Scoop installed its own Gradle. Run `scoop uninstall gradle` or take it out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "winget",
        message = "WinGet installed its own Gradle. Run `winget uninstall Gradle.Gradle` or take it out of PATH so vfox's Gradle runs.",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
    {
        match = "gradle",
        message = "Another Gradle is earlier on PATH, so `gradle` does not run the version vfox selected. Remove it from PATH or put vfox first (`vfox config path.mode baseline`).",
        url = "https://github.com/version-fox/vfox-gradle/blob/main/docs/troubleshooting.md#another-gradle-shadows-the-one-vfox-selected",
    },
}
-- Some things that need user to be attention!
PLUGIN.notes = {
    "Gradle needs a JDK. Mirrors and usage: https://github.com/version-fox/vfox-gradle/blob/main/README.md",
}
