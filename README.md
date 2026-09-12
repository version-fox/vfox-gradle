# Introduction

vfox-gradle is a plugin for [vfox](https://vfox.lhan.me/) .

## How to use it
1. Install vfox
>For detailed installation instructions, see [Quick Start](https://vfox.lhan.me/guides/quick-start.html)
2. Add vfox-gradle plugin
```bash
vfox add gradle
```
3. Install a version
>Until then, you can specify mirrors to speed up the download. The way to do this is to add a system environment variable called **VFOX_GRADLE_MIRRORS**, e.g. in Powershell execute: 
> `$env:VFOX_GRADLE_MIRRORS= "https://mirrors.cloud.tencent.com/gradle/"`
```bash
vfox install gradle@8.7
```
4. Switch a version
```bash
vfox use gradle@8.7
```
5. View version
```bash
gradle --version

Gradle 8.7
```

## Releasing this plugin

Maintainers can publish from **Actions → Plugin → Run workflow** on the default
branch by entering a stable plugin version without the `v` prefix. The shared
workflow updates `metadata.lua`, creates the version commit and tag, and publishes
the ZIP and manifest in this repository. No local tag or extra release token is
needed. Pull requests run checks only; PR titles no longer trigger publication.

Existing version-tag pushes are supported when `PLUGIN.version` already matches
the tag. If publication fails, re-run the original failed job to resume it.

The workflow follows the shared `@v1` release-tool version. Updating the tool does
not release this plugin. See the [shared workflow documentation](https://github.com/version-fox/plugin-manifest-action)
for the package contract and first-rollout requirements.
