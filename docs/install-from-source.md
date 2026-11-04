# Install from source

[中文](zh-CN/install-from-source.md) | [English](install-from-source.md)

`vfox add gradle` installs the latest release. To try `main` before its next
release, or a change you are working on, build the plugin from source. A plugin is
a `metadata.lua` plus the `hooks` and `lib` directories, and vfox adds one from a
zip of them.

## Ubuntu 26.04

Execute in Bash,

```bash
sudo apt install --assume-yes git zip
git clone --depth 1 https://github.com/version-fox/vfox-gradle.git
cd ./vfox-gradle/
zip -qr ./gradle.zip metadata.lua hooks lib
vfox add gradle --source ./gradle.zip
rm ./gradle.zip
```

macOS is the same, with the `git` and `zip` that come with the system.

## Windows 11

Assume that PowerShell 7 is already installed. Execute in PowerShell 7,

```powershell
winget install --id Git.Git --source winget --exact
git clone --depth 1 https://github.com/version-fox/vfox-gradle.git
cd ./vfox-gradle/
tar -a -cf ./gradle.zip metadata.lua hooks lib
vfox add gradle --source ./gradle.zip
Remove-Item ./gradle.zip
```

## Check it

```bash
vfox install gradle@8.7
vfox use --global gradle@8.7
gradle --version
```

`gradle --version` needs a JDK, see [Java](../README.md#java) in the README.
`vfox info gradle` prints the version in `metadata.lua`, which stays that of the
last release until the next one is made.

## When gradle is already added

`vfox add` refuses with `plugin named gradle already exists`. You can replace the
plugin or add the source build next to it.

To replace it, `vfox remove gradle` comes first, and it removes the releases
installed through the plugin as well: vfox says so before it asks (`-y` skips the
question). Install them again afterwards.

To keep both, give the new one another name:

```bash
vfox add gradle --source ./gradle.zip --alias gradle-dev
vfox install gradle-dev@8.7
vfox remove -y gradle-dev            # removes only gradle-dev and what it installed
```

The alias has its own list of installed releases, `vfox list` shows the two apart,
but the link `~/.vfox/sdks/gradle` that `GRADLE_HOME` names is the same for both:
vfox points it at whichever release you selected last, whichever plugin it came
from. Select a release from only one of them per scope.

## Updating

Pull, build the zip again and add it again. A plugin added under its own name has
to be removed first, and that takes the installed releases with it, so the alias is
the easier route when you update often:

```bash
vfox remove -y gradle-dev
vfox add gradle --source ./gradle.zip --alias gradle-dev
```

`vfox update gradle` compares the version in `metadata.lua` with the registry's and
prints `gradle is already the latest version` while they are equal, so it leaves a
source build alone until a release newer than that version is published.

To work on the plugin, see [development.md](development.md).
