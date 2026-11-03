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

Unreleased: release 0.1.1 prints only `no installable runtime provided` and
`failed to install gradle` for the same thing, and nothing says which request or
status. See [install-from-source.md](install-from-source.md) to try `main`.

### `no SHA-256 digest in <address>`

The request for the sum was answered 200, but what came back holds no 64-digit
hexadecimal digest at its start: the page of a portal or a firewall, or a file cut
short. Open the address with `curl`. See [mirror.md](mirror.md#what-a-mirror-has-to-serve).
This message is Unreleased too: release 0.1.1 gives vfox whatever came back as the
sum, and the install ends in `Checksum error`.

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
Huawei Cloud's mirror, see [mirror.md](mirror.md#what-a-mirror-has-to-serve), and
[vfox#746](https://github.com/version-fox/vfox/issues/746)). Unset
`VFOX_GRADLE_MIRRORS` to see whether services.gradle.org installs.

### `WARNING: Checksum is not provided, skip verify...`

The plugin gave vfox no sum, so vfox trusts the download. It happens when the
request for the `.sha256` answered 404, which a mirror that keeps no such files
does, see [mirror.md](mirror.md#what-a-mirror-has-to-serve). From services.gradle.org
every release has one, and vfox prints `Verifying checksum <digest>...` instead.

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

## Messages from Gradle

### `ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.`

`gradle` runs on a JVM and found none. Install a JDK and put it on the `PATH`, or
set `JAVA_HOME`, see [Java](../README.md#java) in the README. The plugin does not
set `JAVA_HOME`.

## Network

The plugin reads the list from `gradle.org` and the sum from
`services.gradle.org`, and vfox downloads the zip from there too. For a release
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
