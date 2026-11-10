# Troubleshooting

[中文](zh-CN/troubleshooting.md) | [English](troubleshooting.md)

## Messages from the plugin

### `get release info failed.`

`vfox search gradle` could not read [gradle.org/releases](https://gradle.org/releases/):
the request failed, or the page answered something else than 200. See
[Network](#network). The search does not go through a mirror.

### `HTTP request error: Get "<address>": ...`

The request for the SHA-256 sum failed before it got an answer, and the address in
the message is the one that was asked: with `VFOX_GRADLE_MIRRORS` set, it is the
mirror's, see [mirror.md](mirror.md#checking-that-it-applies). After the colon
comes what the network said. See [Network](#network).

### `checksum request failed: HTTP 567 from <address>`

The request for the sum was answered, with something else than 200 or 404: the
status is in the message, and so is the address. A mirror, a firewall or a portal
that sits in front of one is refusing the request. Try the address with `curl`,
unset `VFOX_GRADLE_MIRRORS` to use services.gradle.org, or pick another mirror,
see [mirror.md](mirror.md#mirrors-that-were-checked).

### `no SHA-256 digest in <address>`

The request for the sum was answered 200, but what came back holds no 64-digit
hexadecimal digest at its start: the page of a portal or a firewall, or a file cut
short. Open the address with `curl`. See [mirror.md](mirror.md#what-a-mirror-has-to-serve).

## Messages from vfox

### `failed to download gradle@8.7.0 file, err:source file not found`

The download answered 404: there is no release by that name. The plugin downloads
`gradle-<version>-bin.zip` with the version as you typed it, so check it against
`vfox search gradle`. The common mistakes are a bare major (`gradle@8`) and a third
number that Gradle does not write (`gradle@8.7.0`, the release is `8.7`), see
[versions.md](versions.md#writing-a-version). Through a mirror, a 404 from the
mirror ends here too: it may not carry the release.

### `Checksum error, file: <path>`

vfox printed `Checksum error, file: <path>`, then `checksum error` and
`failed to install gradle`, and stopped before it unpacked anything, so nothing is
installed. The download does not match the SHA-256 sum the plugin gave vfox. A
download cut short or damaged on the way is the usual cause: try again. If it
keeps happening through a mirror, the mirror may serve another file, or an error
page: vfox saved the page of a 403 as the zip, and ended here (release 0.1.1 and
Huawei Cloud's mirror, see [changes.md](changes.md), and
[vfox#746](https://github.com/version-fox/vfox/issues/746)). Unset
`VFOX_GRADLE_MIRRORS` to see whether services.gradle.org installs.

### `WARNING: Checksum is not provided, skip verify...`

The plugin gave vfox no sum, so vfox trusts the download. With a mirror, both of
these happened, see [mirror.md](mirror.md#what-a-mirror-has-to-serve): the mirror
answered 404 for the `.sha256`, as one that keeps no such files does, and
services.gradle.org gave no sum for the release either. A network that blocks
services.gradle.org is the usual reason for that, and `curl -IL
https://services.gradle.org/distributions/gradle-8.7-bin.zip.sha256` shows it; a
release that does not exist is the other. Without a mirror, only that applies. From
services.gradle.org every release has one, and vfox prints `Verifying checksum
<digest>...` instead.

A network that drops the traffic to services.gradle.org, rather than refusing it,
holds the install up for the request timeout of vfox before the warning: 30 seconds
by default, measured on 2026-11-04 with a proxy that accepted the connection and never
answered. `vfox config plugin.http.timeout 5s` shortens it, for the requests of every
plugin; an install of 1.12 took about 20 seconds less with it.

### `install requires specifying a version for gradle`

`vfox install gradle@` with nothing after the `@`. Write a version, or `latest`.

### `gradle@8.7 is not installed`

`vfox uninstall` only knows what is installed, and by the whole name:
`vfox list gradle` shows them. `vfox use` takes the start of a version among the
installed ones, but not a number that is not there: `gradle@8.1` finds nothing
while 8.14 is installed. See [versions.md](versions.md#what-vfox-use-selects).

### `vfox requires hook support. Please ensure vfox is properly initialized with 'vfox activate'`

`vfox use` needs vfox to be hooked into your shell. See vfox's
[quick start](https://vfox.dev/guides/quick-start.html).

### Another Gradle shadows the one vfox selected

Unreleased: vfox 1.1.0 and later, plugin 0.1.3 and later. Older vfox prints
nothing here, older plugin gives no hint.

After `vfox use`, vfox warns when the `gradle` that runs is not the one it
selected, because another executable sits earlier in `PATH`, and `vfox doctor`
reports the same as `path.shadowed`. The hint names the usual culprit: a version
manager (SDKMAN! with `sdk uninstall gradle`, Homebrew with
`brew uninstall gradle`, mise with `mise uninstall gradle`, asdf with
`asdf uninstall gradle` — the last two hide behind shims in a `shims/`
directory), a Windows package manager (Chocolatey with `choco uninstall gradle`,
Scoop with `scoop uninstall gradle`, WinGet with `winget uninstall Gradle.Gradle`),
or a manual install in `/opt`, `/usr/local` or `C:\Gradle`. Remove it from `PATH`,
or put vfox first with `vfox config path.mode baseline`. A directory that has to
stay in front of vfox's can be listed in `path.preserve`. See vfox's
[path.mode](https://vfox.dev/guides/configuration.html#path-mode).

## Messages from Gradle

### `ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.`

`gradle` runs on a JVM and found none. Install a JDK and put it on the `PATH`, or
set `JAVA_HOME`, see [Java](../README.md#java) in the README. The plugin does not
set `JAVA_HOME`.

### `Cannot find a Java installation on your machine (...) matching: {languageVersion=17, ...}. Toolchain download repositories have not been configured.`

The build asks for a JDK that Gradle did not find, and nothing tells Gradle where to
download one. Gradle does not look in vfox's directories, so a JDK that vfox installed
is not found unless you tell Gradle, and without the Foojay plugin in
`settings.gradle.kts` the build cannot download one. Add the plugin, or let Gradle use
the JDK, see [java-toolchains.md](java-toolchains.md#gradle-does-not-look-in-vfoxs-directories)
and [java-toolchains.md](java-toolchains.md#letting-gradle-use-the-jdks-vfox-installed).

### `Class org.gradle.jvm.toolchain.JvmVendorSpec does not have member field '... IBM_SEMERU'`

The build pins a Foojay plugin older than 1.0.0, and the Gradle in use is 9.x: 0.10.0
with 9.8.2 was run. Move the build to 1.0.0 or later, see
[java-toolchains.md](java-toolchains.md#the-foojay-plugin-and-the-gradle-that-vfox-selects).

## Network

The plugin reads the list from `gradle.org` and the sum from
`services.gradle.org`, and vfox downloads the zip from there too. With
`VFOX_GRADLE_MIRRORS` set, the zip and the sum come from the mirror, and the sum from
`services.gradle.org` where the mirror has none. For a release
that address redirects: the sum to `downloads.gradle.org`, and the zip to
Gradle's releases on `github.com`, which hand it out from
`release-assets.githubusercontent.com` (2026-11-03). A network that blocks one of
these hosts breaks the install at the step that needs it. For another address
for the downloads, see [mirror.md](mirror.md).

vfox's own proxy setting covers the requests of the plugin and the download:

```bash
vfox config proxy.enable true
vfox config proxy.url http://127.0.0.1:7890
```

While `proxy.enable` is `false`, the usual `HTTP_PROXY`, `HTTPS_PROXY` and
`NO_PROXY` environment variables apply. Only `http` and `https` proxies are
supported.

## Things that look wrong and are not

- **A release you expect is missing from `vfox search`.** vfox keeps the result
  for 12 hours. `vfox config cache.availableHookDuration 0` turns the cache off.
  gradle.org may not list the release yet either. Release candidates are never
  listed, see [versions.md](versions.md#release-candidates).
- **`gradle@latest` is not the newest thing gradle.org announces.** `latest` is
  the first release `vfox search gradle` lists, and a release candidate is not on
  the list.
- **A project builds with another Gradle than the one you selected.** A project
  with a Gradle wrapper (`./gradlew`) downloads the Gradle it names, and the
  `gradle` command is not involved.
- **`gradle --version` shows another Gradle than the one you selected.** `vfox use`
  without `--global` or `--project` applies to the current shell only, and a
  `gradle` in an earlier directory of the `PATH` wins. `vfox current gradle` shows
  what vfox has selected, `no current version of gradle` when it is nothing.
- **A build downloaded a JDK although vfox has installed it.** Gradle looks for
  installed JDKs in a fixed set of places, and vfox's directories are not among them,
  see [java-toolchains.md](java-toolchains.md#gradle-does-not-look-in-vfoxs-directories).

## Where Gradle is

`GRADLE_HOME` is a link that `vfox use` points at the release you chose. For
`--global` it is `~/.vfox/sdks/gradle`, and `bin` in it is on the `PATH`. The
releases themselves are in `~/.vfox/cache/gradle/v-<version>/gradle-<version>`
(`/root/.vfox/cache/gradle/v-9.0.0/gradle-9.0.0` in the E2E tests). An IDE or a
build tool that wants a Gradle installation directory and should follow your
global choice can point at the first. `~/.vfox` is the default `$VFOX_HOME`. See
vfox's [configuration](https://vfox.dev/guides/configuration.html) for where the
releases and the links go when it is set, and for `storage.sdkPath`.

## Reporting a problem

Open an issue at [version-fox/vfox-gradle](https://github.com/version-fox/vfox-gradle/issues)
with the output of `vfox --version` and `vfox info gradle`, the operating system
and CPU, the command, and everything it printed. `vfox --debug <command>` prints
more.
