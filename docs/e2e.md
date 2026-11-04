# E2E

[中文](zh-CN/e2e.md) | [English](e2e.md)

The offline Lua hook tests (`tests/*_test.lua` under `vfox plugin test`) run in the
**Test Plugin** workflow. The end-to-end suite runs in containers against real vfox
and the real gradle.org, on Linux and on Windows, each on amd64 and arm64; each vfox
channel (`latest` and `main`) gets its own throwaway container. CI runs the suite
natively on the stock runners (Docker plus Go from `actions/setup-go`). Locally, the
repository dev container reproduces that on Linux; on Windows a Docker Compose runner
image does, since dev containers cannot host Windows container images (see below).

The sections below say how to run the suite. The list of every check is at the end,
under [What the suite verifies](#what-the-suite-verifies).

## Dev container

`.devcontainer/` opens a Linux development environment that works on all four host
platforms:

| Host                  | How the dev container runs                     |
| --------------------- | ---------------------------------------------- |
| Linux amd64 / arm64   | natively                                       |
| Windows amd64 / arm64 | Docker Desktop in Linux-container mode (WSL 2) |

It carries Go 1.27.1 (the version CI installs), the Docker CLI, stylua,
lua-language-server, actionlint, the license tools and vfox, which runs the offline
hook tests — all pinned to the versions in `.github/workflows/lint.yml`,
`license.yml` and `test.yml` — and mounts the host Docker daemon socket. The Linux
suite then runs testcontainers against that daemon (Docker-out-of-Docker), spawning
the same target containers a native CI runner spawns; this is deliberately not
Docker-in-Docker, so image cache and networking stay the host's. The image needs no
workspace files, so the build context stays at `.devcontainer/`;
`postCreateCommand` warms the Go module cache for `tests/e2e` so the first test run
does not stop to download.

Open it with any Dev Containers spec tool — **Dev Containers: Reopen in Container**
in VS Code/Cursor, or the CLI:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

`TESTCONTAINERS_RYUK_DISABLED=true` is preset: Ryuk publishes a port on the host
daemon and waits for the suite to dial it back, which a Docker-out-of-Docker
container cannot do. The suite terminates every container explicitly via
`t.Cleanup` instead; leftovers from killed runs share the `vfox-gradle-e2e-` name
prefix for pruning. Rootless Docker users export
`DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"` on the host before opening the
container. On Windows hosts, keeping the checkout inside WSL 2 (e.g. under
`\\wsl$`) keeps file and bind-mount access fast; a checkout on the Windows
filesystem works too.

Windows *container* coverage (`tests/e2e/windows`) cannot run in a dev container:
the Dev Containers spec does not support Windows container images
([vscode-remote-release#445](https://github.com/microsoft/vscode-remote-release/issues/445)),
and Windows containers only run on a Windows daemon. That suite keeps its Docker
Compose runner on a Windows host; see [Windows 11](#windows-11) below.

## Environment knobs

| Variable             | Default                              | Meaning                                                                 |
| -------------------- | ------------------------------------ | ----------------------------------------------------------------------- |
| `VFOX_VERSION`       | `latest main`                        | Space-separated vfox channels (`latest`, `main`)                        |
| `GRADLE_VERSION`     | `9.0.0` (Linux), `9.2.0` (Windows)   | The release installed from services.gradle.org, as the plugin spells it |
| `E2E_MAX_JOBS`       | `3` (Linux), `2` (Windows)           | Parallel containers per host                                            |
| `E2E_RETRY_ATTEMPTS` | `3`                                  | Attempts per network-touching exec (linear 10s backoff)                 |

The Linux suite installs a second release, `8.7`, through its mirror stand-in, and a
third, `1.12`, through another, so `GRADLE_VERSION` must be neither there.
`GRADLE_VERSION` and `8.7` have to run on the Java 21 of the image (Gradle 8.5 and
later, and 9.x); `1.12` is installed and never run. The Windows suite installs `9.2.1`
as its second release, from services.gradle.org, so `GRADLE_VERSION` must not be that
one there; both have to run on the Java 21 of its image, and on arm64 that means 9.2.0
or later (see [Windows 11](#windows-11)). Your own `VFOX_GRADLE_MIRRORS` stays on the
host: the containers get the environment the suite gives them.

## Linux (Ubuntu 26.04)

Inside the dev container, from the repository root:

```bash
cd tests/e2e
go test -v -timeout 55m -run TestE2E ./linux
```

Scope it down while iterating the same way:

```bash
VFOX_VERSION=latest E2E_MAX_JOBS=1 go test -v -timeout 55m -run TestE2E ./linux
```

On a native host the same command works with two prerequisites — Docker Engine
(rootful or rootless) and Go 1.27.1 — which is exactly what CI provisions. Rootless
Docker users point the Docker client at their socket
(`export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"`); the dev container's
socket mount covers that case for you.

On 2026-11-03 one combination took 113 seconds, and the whole run, the image build
included, 175 seconds. The two installs then downloaded 134 MB each; the third, 1.12,
adds 42 MB.

## Windows 11

Windows containers cannot be emulated across architectures, so the ARM64 suite needs
an ARM64 host (a Copilot+ PC or the `windows-11-arm` CI runner).

There is no dev container for this suite — the Dev Containers spec rejects Windows
container images (see [Dev container](#dev-container)) — so it keeps its Docker
Compose runner. The runner image (`Dockerfile-runner`: stock servercore plus the
pinned Go, which also builds vfox `main`) drives the host daemon through the mounted
named pipe; the host requirement is Docker in Windows-container mode plus the
Compose v5 plugin (installed once per machine below). Go never touches the host, so
it cannot conflict with a vfox-managed toolchain.

As vfox-java found, the `windows-11-arm` runner has no Windows Hypervisor Platform
feature, so Hyper-V isolation is unavailable; process isolation needs only the
Containers feature.

CI skips the runner image: in vfox-java, extracting its Go took two and a half
minutes on `windows-11-arm`, where `actions/setup-go` already provides the same Go.
CI runs `go test ./windows` on the runner with `E2E_MAX_JOBS=3`, after
`use-local-disk.ps1` moves Docker's data root, Go's caches and the temp directory
off the runners' network-attached C: onto a local disk: `windows-latest`'s D:, or the
unformatted NVMe disk of `windows-11-arm`, which it formats. Image layers and the
containers' files are written file by file, so on C: pulling servercore alone took
five minutes in vfox-java. The script refuses to run outside GitHub Actions.

The image (`tests/e2e/windows/Dockerfile`) is the stock servercore, PowerShell 7,
which drives every exec, and Temurin 21, each unpacked from a zip by
`bootstrap-tools.ps1`. The JDK is checked against the SHA-256 that Adoptium publishes.
It is `jdk-21.0.12.1+1`, the newest release with a zip for both architectures on
2026-11-04: the x64 zip of 21.0.13+9 was out, the aarch64 one was not. There is no
Gradle in the image, as on Linux: a `gradle` can only come from what vfox installs.

The suite installs `9.2.0` and `9.2.1` where the Linux suite installs `9.0.0` and
`8.7`. Gradle loads a library of native-platform for its console, its file system
and the Windows registry, and a build of it for Windows on ARM64 came with 9.2.0:
the `lib` directories of 8.7, 9.0.0 and 9.1.0 hold no
`native-platform-windows-aarch64`, and the one of 9.2.0 holds two (2026-11-04). Gradle
decided not to backport it to 8.x ([gradle/gradle#35396](https://github.com/gradle/gradle/issues/35396),
[#21703](https://github.com/gradle/gradle/issues/21703)). So both jobs take the first
release that runs natively on both architectures, and its successor.

Every combination runs with `VFOX_HOME` pointing inside a path containing a space
(`C:\Users\John Doe\.vfox`), mirroring
[vfox-flutter#33](https://github.com/version-fox/vfox-flutter/issues/33). vfox handles
such paths since 1.0.13 ([vfox#712](https://github.com/version-fox/vfox/pull/712)), so
the `latest` release and `main` both run against it, and the distribution is unpacked
below it.

On 2026-11-04, in the first run of this suite in CI
([vfox-gradle#7](https://github.com/version-fox/vfox-gradle/pull/7)), one combination
took 56 and 58 seconds on `windows-latest` (`latest`, then `main`) and 90 and 86 on
`windows-11-arm`. The `go test` step took 3 min 48 s and 5 min 46 s, the image build
included: pulling servercore took 2 min 4 s and 3 min 10 s, and `bootstrap-tools.ps1`
18 s and 47 s. The jobs took 4 min 26 s and 9 min 9 s. The second includes 1 min 57 s
for the Docker engine, which `install-docker-arm64.ps1` built from source because the
cache had no entry yet. The two installs of a combination download 136 MB each.

The rerun of the same code the same day (a documentation commit on top) was slower on
`windows-latest`: 90 and 86 seconds per combination, 5 min 27 s for the `go test` step
and 6 min 22 s for the job. On `windows-11-arm` it was about the same, with 94 and 90
seconds and 6 min 3 s, but the Docker engine came from the cache in 12 seconds, so the
job took 7 min 38 s. Neither run retried anything. Allow for a difference of that size
between runs.

### x64

All commands below run in PowerShell 7. If it is not installed yet, install it first
(this single bootstrap command may run in the built-in Windows PowerShell):

```powershell
winget install --id Microsoft.PowerShell --source winget --exact
```

1. Execute in PowerShell 7,

```powershell
winget install --id Git.Git --source winget --exact
# Configure Git appropriately.

curl.exe -fsSL `
    "https://raw.githubusercontent.com/microsoft/Windows-Containers/Main/helpful_tools/Install-DockerCE/install-docker-ce.ps1" `
    -o ./install-docker-ce.ps1
```

2. Execute in PowerShell 7 with administrator privileges,

```powershell
./install-docker-ce.ps1
```

3. Execute in PowerShell 7,

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.docker\cli-plugins" | Out-Null

curl.exe -fsSL `
    "https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-windows-x86_64.exe" `
    -o "$env:USERPROFILE\.docker\cli-plugins\docker-compose.exe"

git clone git@github.com:version-fox/vfox-gradle.git
cd ./vfox-gradle/
docker compose -f tests/e2e/windows/compose.amd64.yaml run --rm --build e2e
```

### arm64

All commands below run in PowerShell 7. If it is not installed yet, install it first
(this single bootstrap command may run in the built-in Windows PowerShell):

```powershell
winget install --id Microsoft.PowerShell --source winget --exact
```

1. Execute in PowerShell 7,

```powershell
winget install --id Git.Git --source winget --exact
# Configure Git appropriately.
winget install --id GoLang.Go --source winget --exact
git clone git@github.com:version-fox/vfox-gradle.git
cd ./vfox-gradle/
pwsh -NoProfile -File .\tests\e2e\windows\install-docker-arm64.ps1
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.docker\cli-plugins" | Out-Null

curl.exe -fsSL `
    "https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-windows-aarch64.exe" `
    -o "$env:USERPROFILE\.docker\cli-plugins\docker-compose.exe"

docker compose -f tests/e2e/windows/compose.arm64.yaml run --rm --build e2e
```

On arm64, Go is also what builds the engine, so `install-docker-arm64.ps1` runs
before the suite; the compose runner image then carries its own pinned Go for the
tests, and the host Go is not used again. The script reuses an engine of its pinned
version that it built before; CI restores one from a cache keyed on the script. Scope
the run down with `$env:VFOX_VERSION = 'latest'` in front of the compose command, as
on the other platforms.

## Local checks

Execute from the dev container — everything below is preinstalled and pinned to the
versions the workflows use — or provision the same tools on a host.

```bash
# Go and Lua checks (.github/workflows/lint.yml).
cd tests/e2e
go test -short ./...
test -z "$(gofmt -l .)"
go vet ./...
cd ../..

stylua --check .
lua-language-server --check . --checklevel=Warning
actionlint
```

```bash
# Offline hook tests (.github/workflows/test.yml).
vfox plugin test .
```

```bash
# License headers (.github/workflows/license.yml).
license-eye header check
license-eye header fix
addlicense -check -f .license.tpl tests/e2e/windows/*.ps1
addlicense -f .license.tpl tests/e2e/windows/*.ps1
```

On a Docker-only host the license and workflow checks run as containers instead (the
same images CI uses):

```bash
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header check
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header fix
docker run --rm -v "$PWD:/src" ghcr.io/google/addlicense:v1.2.0 -check -f .license.tpl tests/e2e/windows/*.ps1
docker run --rm -v "$PWD:/src" ghcr.io/google/addlicense:v1.2.0 -f .license.tpl tests/e2e/windows/*.ps1
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
```

License-eye checks the PowerShell files too but cannot fix them, so `addlicense`
writes their headers and checks them in CI (`.licenserc.yaml` says why). The Windows
suite is compiled and vetted by the same Go checks as the Linux one, on any host;
only running it needs a Windows host.

## What the suite verifies

On Linux every combination runs the same flow (one long-lived container per vfox
channel, driven from Go through `docker exec`-style calls). The target image carries
a JDK from Ubuntu, because Gradle needs one, and no Gradle: a `gradle` can only come
from what vfox installs. [On Windows](#on-windows) the flow is the same where it can
be.

1. vfox is installed from the requested channel — the latest release (`latest`) or
   built from source (`main`) — and the local `gradle` plugin is registered from
   this checkout. Then the notes printed by `vfox info gradle` must link to the
   README, which says how to use a mirror and that Gradle needs a JDK.
2. `vfox search gradle` runs the `Available` hook against the live
   gradle.org/releases and must list both releases the suite installs, each release
   once and newest first, though the page lists them by date. It listed 174 releases
   on 2026-11-03. If gradle.org changes the markup of the page, this is where it
   shows.
3. Names no release has fail, with `source file not found` and nothing installed:
   `99.0`, and `8.7.0` and `8.14.0`, which Gradle writes without the third number.
4. An install through a mirror that does not exist, with
   `VFOX_GRADLE_MIRRORS=https://invalid.example.invalid/`, fails, and the error names
   `https://invalid.example.invalid/gradle-9.0.0-bin.zip.sha256`: the plugin read the
   variable, and joined the value that ends in a slash with one slash. Release 0.1.1
   asked for `…/gradle//gradle-9.0.0-bin.zip.sha256`.
5. `gradle@latest` is the first release the search lists (9.8.2 on 2026-11-03). The
   install goes to the mirror that does not exist, so vfox prints
   `Using latest version: 9.8.2` and fails on the request for its sum, and nothing is
   downloaded.
6. A mirror that answers 567 for the sum, as a gateway can, stops the install with
   `checksum request failed: HTTP 567 from http://127.0.0.1:8081/gradle-9.0.0-bin.zip.sha256`.
   Release 0.1.1 printed only `no installable runtime provided`.
7. The pinned release installs from services.gradle.org under that name. vfox must
   print `Verifying checksum <digest>...` with 64 hexadecimal digits, not `WARNING:
   Checksum is not provided, skip verify...`, and the digest must be the one Gradle
   publishes for the release. vfox compares it with the hash of the file it
   downloaded and fails the install if they differ, so the install succeeding proves
   the digest is the file's. `vfox search gradle` then marks the release
   `(installed)`.
8. After `vfox use --global`, a new activated shell has that Gradle: `gradle
   --version` reports the release, `GRADLE_HOME` (`~/.vfox/sdks/gradle`) resolves to
   `~/.vfox/cache/gradle/v-9.0.0/gradle-9.0.0`, `gradle` is the `bin/gradle` in it,
   `vfox current gradle` reports it, and a build with one task runs. That last one
   shows the unpacked distribution works as a whole: the launcher keeps its execute
   bit, and the libraries under `lib/` and the Groovy that compiles the script load.
9. The second release, 8.7, installs through the stand-in for a mirror in
   `tests/e2e/linux/mirror`, which listens on the loopback of the container and asks
   services.gradle.org for what it serves. It behaves like the mirrors met in real
   installs, so the install proves three things release 0.1.1 gets wrong. The value
   ends in a slash, and the stand-in answers 404 to a path with a second one. It
   answers 403 and a page of HTML to Go's default `User-Agent`, as Huawei Cloud's
   mirror does, which vfox downloads with unless the plugin names another: vfox
   saved the page as the zip and ended in `Checksum error`. And its `.sha256` is
   written as `sha256sum` writes it, `<digest>  <file>` and a newline, where
   vfox compares the text as it is. The stand-in's log must show a `GET` for the
   `.sha256` and for the zip, both answered 200, and the digest vfox verified must
   be the one Gradle publishes, as in item 7.
10. `vfox use` switches between the two releases: each time `gradle --version`,
    `GRADLE_HOME` and `gradle` follow (item 8). `vfox list gradle` shows both, and
    `vfox uninstall gradle@8.7` leaves the other working.
11. The third release, 1.12, installs through a second stand-in that serves the zips and
    answers 404 to every `.sha256`: a mirror that keeps no sums, as Tencent Cloud's
    has none for the releases after 8.0.1. Its log must show the `GET` for the
    `.sha256` answered 404 and the one for the zip answered 200. vfox must still print
    `Verifying checksum <digest>...` and not `WARNING: Checksum is not provided, skip
    verify...`, and the digest must be the one Gradle publishes, as in item 7: the
    plugin took it from services.gradle.org, and vfox compared it with the hash of the
    zip it downloaded from the mirror. Release 0.1.1 gave vfox no digest, and the
    install ended in the warning. The release is 42 MB and is never run.

### On Windows

The Windows suite runs items 1 to 5, 7, 8 and 10, with the differences below, and
leaves out 6, 9 and 11, which need the mirror stand-in (see [What the suite leaves
out](#what-the-suite-leaves-out)). Before them it checks that the image carries a
JDK 21 in `JAVA_HOME`, and its commands are PowerShell 7's.

- **Item 1.** `latest` is the Windows zip of the latest release,
  `vfox_<version>_windows_x86_64.zip` or `vfox_<version>_windows_aarch64.zip`. `main`
  is built on the runner, with its Go, while the image builds, and layered onto the
  image as `vfox.exe`: building it in each container meant installing Go there first.
  The plugin is packed with Windows' own `tar -a -cf`, and `vfox add gradle --source`
  registers it.
- **Items 7 and 10.** The pinned release is `9.2.0` and the second release `9.2.1`,
  both from services.gradle.org, where Linux installs 8.7 through the stand-in. The
  digest vfox verifies must be the one Gradle publishes for each.
- **Item 8.** A global `vfox use` writes the variables to the registry of the account
  on Windows (`HKCU\Environment`, vfox 1.0.13, `internal/env/registry_windows.go`),
  which does no harm in a throwaway container and would on a machine of your own, so
  the suite runs it only there. The new shell is the one `vfox activate pwsh` sets up,
  with the export of `vfox env`. `GRADLE_HOME` is a link in the `.vfox\sdks` directory
  of the user profile (the one of the slot the suite gives each container, so without
  the space), a junction that vfox makes with PowerShell's `New-Item -ItemType
  Junction` (vfox 1.0.13, `internal/shared/util/file.go`), and it must resolve to
  `cache\gradle\v-9.2.0\gradle-9.2.0` in the vfox home, the one with the space. The
  `gradle` that PowerShell finds must be the `bin\gradle.bat` of that link. The hook adds `/bin` to the path of
  the link, so the `PATH` entry can have a slash among its backslashes. The offline
  test of `EnvKeys` takes it for granted that Windows reads that slash as a
  separator; the Windows suite is where that is checked.

The matrix is the two vfox channels, `latest` and `main`, on each architecture the
runner has. The pinned releases of the Linux suite are `9.0.0`, written with the third
number as Gradle writes it since 9.0.0, `8.7`, written without as it did up to 8.x,
and `1.12`, which is small; the Windows suite pins `9.2.0` and `9.2.1` (see [Windows
11](#windows-11)). Old releases stay downloadable, so the pins do not age.

## What the suite leaves out

- **macOS.** There is no job for it. The plugin has no code of its own for any
  system, and the distribution is one zip, but nothing in CI proves it for macOS.
- **The mirror stand-in on Windows.** Items 6, 9 and 11 run on Linux only. They
  exercise the Lua of the plugin against a mirror, and that Lua has no code of its
  own for any system. Starting the stand-in in a Windows container needs a process
  that outlives the `docker exec` that starts it, which the suite does not do yet.
- **A real mirror.** Mirrors come and go, so the suite uses its stand-in. The
  mirrors that were checked by hand are in [mirror.md](mirror.md#mirrors-that-were-checked).
- **Proxies**, and the scopes of `vfox use` other than `--global`.
