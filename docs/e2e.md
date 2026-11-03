# E2E

[中文](zh-CN/e2e.md) | [English](e2e.md)

The offline Lua hook tests (`tests/*_test.lua` under `vfox plugin test`) run in the
**Test Plugin** workflow. The end-to-end suite runs in Linux containers against real
vfox and the real gradle.org, on amd64 and arm64; each vfox channel (`latest` and
`main`) gets its own throwaway container. CI runs the suite natively on the stock
runners (Docker plus Go from `actions/setup-go`). Locally, the repository dev
container reproduces that.

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
lua-language-server, actionlint, the license tool and vfox, which runs the offline
hook tests — all pinned to the versions in `.github/workflows/lint.yml`,
`license.yml` and `test.yml` — and mounts the host Docker daemon socket. The suite
then runs testcontainers against that daemon (Docker-out-of-Docker), spawning the
same target containers a native CI runner spawns; this is deliberately not
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

## Environment knobs

| Variable             | Default       | Meaning                                                                        |
| -------------------- | ------------- | ------------------------------------------------------------------------------ |
| `VFOX_VERSION`       | `latest main` | Space-separated vfox channels (`latest`, `main`)                               |
| `GRADLE_VERSION`     | `9.0.0`       | The release installed from services.gradle.org, as the plugin spells it        |
| `E2E_MAX_JOBS`       | `3`           | Parallel containers per host                                                   |
| `E2E_RETRY_ATTEMPTS` | `3`           | Attempts per network-touching exec (linear 10s backoff)                        |

The suite installs a second release, `8.7`, through its mirror stand-in, so
`GRADLE_VERSION` must be another. Both have to run on the Java 21 of the image
(Gradle 8.5 and later, and 9.x). Your own `VFOX_GRADLE_MIRRORS` stays on the host: the
containers get the environment the suite gives them.

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
included, 175 seconds. The two installs download 134 MB each.

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
```

On a Docker-only host the license and workflow checks run as containers instead (the
same images CI uses):

```bash
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header check
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header fix
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
```

## What the suite verifies

Every combination runs the same flow (one long-lived container per vfox channel,
driven from Go through `docker exec`-style calls). The target image carries a JDK
from Ubuntu, because Gradle needs one, and no Gradle: a `gradle` can only come from
what vfox installs.

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

The matrix is the two vfox channels, `latest` and `main`, on each architecture the
runner has. The pinned releases are `9.0.0`, written with the third number as Gradle
writes it since 9.0.0, and `8.7`, written without as it did up to 8.x. Old releases
stay downloadable, so the pins do not age.

## What the suite leaves out

- **Windows containers and macOS.** There is no job for either. The plugin has no
  code of its own for any system, and the distribution is one zip, but nothing in CI
  proves it for them. A Windows container suite needs a Windows host and cannot run
  in the dev container; vfox-java's `tests/e2e/windows` is what to port.
- **A real mirror.** Mirrors come and go, so the suite uses its stand-in. The
  mirrors that were checked by hand are in [mirror.md](mirror.md#mirrors-that-were-checked).
- **Proxies**, and the scopes of `vfox use` other than `--global`.
