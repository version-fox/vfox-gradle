# Versions and names

[中文](zh-CN/versions.md) | [English](versions.md)

## Writing a version

A version is the name of a Gradle release as `vfox search gradle` lists it. The
plugin puts it into the file name as it comes, `gradle-<version>-bin.zip`, and
downloads that, so a name that is not a release ends in a download that answers
404:

| You write | What happens |
| --- | --- |
| `gradle@8.7` | installs 8.7 |
| `gradle@8.14.3` | installs 8.14.3 |
| `gradle@9.0.0` | installs 9.0.0 |
| `gradle@v8.7` | vfox drops the `v`, and installs 8.7 |
| `gradle@latest` | vfox takes the first release `vfox search gradle` lists, the newest one: 9.8.2 on 2026-11-03 |
| `gradle@8` | `source file not found`: there is no release called 8 |
| `gradle@8.7.0` | `source file not found`: the release is called 8.7 |
| `gradle@` | `install requires specifying a version for gradle` |

Gradle writes the first release of a line without a third number up to 8.x
(`8.14`, `8.7`, `7.6`) and with it from 9.0.0 on (`9.0.0`, `9.1.0`). Both `8.14`
and `8.14.3` are releases, but `8.14.0` is not. Copy the name from the list.

## Searching

```bash
vfox search gradle
```

```text
Available versions:
 - 9.8.2
 - 9.8.1
 - 9.8.0
 ...
```

The plugin reads the page [gradle.org/releases](https://gradle.org/releases/),
which lists 174 releases, from 0.7 to 9.8.2 (2026-11-03). The page lists them by
date, so 8.14.6 sits between 9.8.2 and 9.8.1, and the plugin sorts them by their
numbers, newest first. A missing number counts as zero: 8.14 and 8.14.0 would be
equal. The first entry is what `latest` means.

An installed release is marked `(installed)`. In an interactive terminal the
search lets you pick a release and installs it. vfox keeps the result for 12
hours, so a release that gradle.org lists a minute ago may be missing:
`vfox config cache.availableHookDuration 0` turns the cache off. The search does
not go through a [mirror](mirror.md): the list always comes from gradle.org.

## Release candidates

The page lists final releases only. A release candidate is not in the search and
is never `latest`, but it installs by name, while Gradle still serves it:

```bash
vfox install gradle@9.0.0-rc-1
```

That installed on 2026-11-03 and was verified against its checksum like any other
release. Snapshots and nightly builds are out of reach: Gradle serves them from
`distributions-snapshots`, and the plugin only knows `distributions`.

## Binary distribution only

The plugin installs `gradle-<version>-bin.zip`, the binary-only distribution that
the releases page offers next to a "complete" one with the documentation and the
sources. The complete one is not available.

## Installed names

The name of an install is the version: `vfox install gradle@latest` installs 9.8.2
under that name and not under `latest`. `vfox list gradle` shows the names, one
`->` line for each, in the order of the text, not of the numbers (`8.7` comes
before `8.14`).

`vfox uninstall` needs the whole name. Unlike `vfox use`, it takes no start of a
version: `vfox uninstall gradle@8` answers `gradle@8 is not installed` while 8.7
is installed.

## What `vfox use` selects

```bash
vfox use gradle@8.7              # the current shell
vfox use --project gradle@8.7    # the current directory
vfox use --global gradle@8.7     # every new shell
```

Unlike an install, `vfox use` takes the start of a version and looks among the
installed releases. With 8.7, 8.14, 8.14.3 and 9.0.0 installed (checked with vfox
1.0.13), `vfox use gradle@8` selects 8.14.3, the newest 8.x, `gradle@8.14` selects
8.14 and not 8.14.3, and `gradle@8.1` finds nothing: it is not the start of a
number of any of them. That is vfox's own matching. The plugin's `PreUse` hook
does nothing.

## Wrapper projects

A Gradle wrapper pins its release in `gradle/wrapper/gradle-wrapper.properties`
(`distributionUrl`). In a project directory with that file, `gradle` follows the
pinned release: with 8.7 and 9.8.2 installed, a wrapper naming 8.7 selects 8.7,
without any `vfox use`. A version named in `.vfox.toml` wins over the wrapper
file, and the file is read from the current directory only. The `-all`
distribution takes the same version (the plugin installs `-bin`); a release
candidate or snapshot URL is returned as is, and installing it may fail like a
manual install of a name that is not a release. `./gradlew` is unaffected: it
still downloads and runs its own Gradle.
