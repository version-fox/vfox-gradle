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
