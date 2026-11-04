# vfox-gradle

[中文](README_CN.md) | [English](README.md)

[Gradle](https://gradle.org/) plugin for [vfox](https://vfox.dev/).

It installs the binary distributions that Gradle publishes at
[services.gradle.org](https://services.gradle.org/distributions/), or on a
[mirror](docs/mirror.md) of it, and checks every download against the SHA-256 sum
Gradle publishes next to it. `vfox search gradle` lists the releases on
[gradle.org/releases](https://gradle.org/releases/).

## Install

After installing [vfox](https://github.com/version-fox/vfox), install the plugin,
a Gradle release, and select it:

```bash
vfox add gradle
vfox install gradle@8.7
vfox use --global gradle@8.7
gradle --version
```

`gradle --version` shows the release that is selected. For `gradle` to be on the
`PATH`, vfox has to be hooked into your shell, see its
[quick start](https://vfox.dev/guides/quick-start.html). `vfox use` also takes
`--project` for the current directory and `--session` for the current shell, the
default.

`vfox search gradle` lists the releases, newest first, and in an interactive
terminal it lets you pick one and installs it.

Behavior that only exists on `main` and not in the latest release is marked
"Unreleased" in the pages below. [docs/changes.md](docs/changes.md) lists it, and
[docs/install-from-source.md](docs/install-from-source.md) gets you `main`.

## Java

Gradle runs on a JVM, so a JDK has to be installed first. Without one, `gradle`
stops with `ERROR: JAVA_HOME is not set and no 'java' command could be found in
your PATH.` vfox can install it too, with the
[java plugin](https://github.com/version-fox/vfox-java):

```bash
vfox add java
vfox install java@21-tem
vfox use --global java@21-tem
```

Which Java each Gradle release runs on is in Gradle's
[compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html):
on 2026-11-03, 9.8.2 needs Java 17 to 27, and the 8.14 releases run on Java 8 to 24.
The plugin sets `GRADLE_HOME` and `PATH`, and leaves `JAVA_HOME` to you.

A build that asks Gradle for a JDK of its own (`java.toolchain`) and lets the Foojay
plugin download it works with a Gradle that vfox installed, and the plugin takes no
part in it. [docs/java-toolchains.md](docs/java-toolchains.md) separates the JDK Gradle
runs on from the one the build uses, explains why Gradle does not see the other JDKs
that vfox installed, and shows how to make it use them.

A project that has the Gradle wrapper (`./gradlew`) downloads the Gradle it names
by itself, and does not use the release vfox selected. The plugin is for the
`gradle` command.

## Versions and names

A version is the name of a release as `vfox search gradle` lists it: `8.7`,
`8.14.3`, `9.0.0`. Gradle writes the first release of a line without a third
number up to 8.x (`8.7`, not `8.7.0`) and with it from 9.0.0 on, so copy the name
from the list. `latest` is the newest release. A bare major (`gradle@8`) is not a
release and does not install. The name of an install is the version, and
`vfox uninstall gradle@8.7` needs it whole. See [docs/versions.md](docs/versions.md)
for details, including release candidates and what `vfox use gradle@8` selects.

## Mirror

Set `VFOX_GRADLE_MIRRORS` to download from a mirror of
`services.gradle.org/distributions`, for example Huawei Cloud's:

```bash
export VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle
vfox install gradle@8.7
```

Mind the S at the end of the name. See [docs/mirror.md](docs/mirror.md) for the
layout a mirror has to have, the mirrors that were checked, and PowerShell.

## Platforms

Gradle's binary distribution is one zip for every system (`bin/gradle` and
`bin/gradle.bat`), and the plugin has no code of its own for any of them. The
[E2E tests](docs/e2e.md) run on Linux, amd64 and arm64; Windows and macOS are not
tested in CI.

## Documentation

**Using the plugin**

- [Versions and names](docs/versions.md): how to write a version, `latest`, release candidates, and what `vfox use` selects
- [Mirror](docs/mirror.md): `VFOX_GRADLE_MIRRORS`, what a mirror has to serve, and mirrors that were checked
- [Java toolchains](docs/java-toolchains.md): the Foojay plugin, the JDK Gradle runs on and the one it builds with, and letting Gradle use the JDKs vfox installed
- [Troubleshooting](docs/troubleshooting.md): the messages the plugin and vfox print, proxies, and where Gradle is
- [Changes](docs/changes.md): what each release changed, and what only `main` has

**Working on the plugin**

- [Install from source](docs/install-from-source.md): trying `main` before the next release
- [Development](docs/development.md): how the plugin works, how to change it and how to release it
- [E2E tests](docs/e2e.md): the dev container and the container tests

## Thanks

- [Gradle](https://gradle.org/), whose release page, distributions and SHA-256 sums the plugin installs from
