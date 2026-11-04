# Development

[中文](zh-CN/development.md) | [English](development.md)

## Layout

```text
metadata.lua                    plugin name, version and notes
hooks/available.lua             vfox search: the releases on gradle.org/releases
hooks/pre_install.lua           vfox install: the URL of the zip (or of a mirror), its SHA-256 and the User-Agent
hooks/env_keys.lua              GRADLE_HOME and PATH
hooks/pre_use.lua               does nothing, vfox matches what was typed against the installed releases
hooks/post_install.lua          does nothing
lib/util.lua                    the two URLs, the comparison of versions and the headers of a download
tests/*_test.lua                offline hook tests, run by vfox plugin test
tests/fixtures/releases.html    a saved excerpt of gradle.org/releases, read by the test of Available
tests/e2e/                      container tests, see e2e.md
Injection.lua                   type hints for what vfox injects, never loaded
README.md, docs/                the documentation; README_CN.md and docs/zh-CN/ are the Chinese version
.devcontainer/                  Linux development container, see e2e.md
.github/workflows/              test, lint, license, e2e and publish
opencode.jsonc                  lets OpenCode agent sessions in this repository run git push, gh pr create and gh pr comment without asking
```

vfox loads `metadata.lua`, calls a hook when a command needs it, and puts `PLUGIN`
and `RUNTIME` (`osType`, `archType`, `version`) in scope, and the modules `http`
and `json`. `osType` and `archType` are Go's `GOOS` and `GOARCH` of the vfox
binary. `lib/util.lua` is loaded with `require("util")`.

## What runs for a command

| You run | Hooks |
| --- | --- |
| `vfox search gradle` | `Available` |
| `vfox install gradle@8.7` | `PreInstall` returns the URL, the digest and the User-Agent. vfox downloads, verifies and unpacks, then calls `PostInstall` |
| `vfox install gradle@latest` | vfox calls `Available` and takes its first entry, then goes on as above |
| `vfox use gradle@8.7` | `PreUse` returns nothing and vfox matches the name against the installed releases. `EnvKeys` provides the variables |
| `vfox uninstall gradle@8.7` | none, the name has to be exact |

A few contracts that cost time to find:

- `PreInstall` returns `version`, `url`, `sha256` and `headers`. `version` is the
  name of the install, and the hook returns it as typed. The key of the digest names
  the algorithm, and vfox hashes the download with it and compares the hex digest
  with the text it was given, as it stands: lower case, with nothing around it, or
  the install fails with `Checksum error` whatever the download is. So the hook
  takes the digest out of the file it read, which a mirror may have written in the
  format of `sha256sum`, and lower-cases it.
- vfox makes the download itself, as `Go-http-client/1.1` unless `headers` says
  otherwise. A mirror that refuses Go's default agent with a 403 and a page of HTML
  (Huawei Cloud's does, 2026-11-03) gets that page saved as the zip, and the install
  ends in `Checksum error`. The hook sets `User-Agent` in `headers`, to the string
  vfox uses for the requests of a hook (`util:download_headers()`).
- Without a digest vfox only warns (`Checksum is not provided`) and goes on to
  download, and it verifies a download only against a digest the hook gave it. So
  where a mirror answers 404 for the `.sha256`, which one with no such files does,
  the hook asks services.gradle.org for the digest of the same release, and vfox
  verifies the mirror's zip against that. Tencent Cloud's mirror has no `.sha256` for
  8.7 or 9.8.2, and with release 0.1.1 an install of either ended in the warning. The
  hook leaves the digest out only where that fails too: the mirror was the server
  asked for, and a network that needs one may block services.gradle.org, so it is no
  reason to stop. For the mirror itself the hook fails for any status but 200 and 404,
  and for a 200 that holds no digest, and does not ask services.gradle.org in its
  place. Release 0.1.1 returned nothing for those statuses, and vfox printed `no
  installable runtime provided`.
- `latest` is not handled by the plugin: vfox core takes the first entry of
  `Available` (`Using latest version: 9.8.2`), so the order that `lib/util.lua`
  gives the list is what `latest` means. vfox keeps the result of `Available` for 12
  hours (`vfox config cache.availableHookDuration`).
- `PreUse` returns nothing, and vfox matches what was typed against the installed
  releases itself, by the start of a number: `gradle@8` selects the newest 8.x
  installed, and `gradle@8.1` does not select 8.14.
- `EnvKeys` gets `ctx.path`, which is the link `~/.vfox/sdks/gradle` that vfox
  keeps pointed at the release in use, so `GRADLE_HOME` has the same value whichever
  release is selected. It sets `GRADLE_HOME` and `PATH`, nothing like `JAVA_HOME`.
- The zip holds one directory, `gradle-<version>`, and vfox finds it by itself:
  `PostInstall` has nothing to do. `bin/gradle` keeps its execute bit through the
  unpacking.
- vfox removes a leading `v` from what the user types before the hooks see it.

## The mirror

`VFOX_GRADLE_MIRRORS` is read in `PreInstall` with `os.getenv`, with slashes at the
end of the value left out. Without it the URL is `util.DownloadInfoUrl`. The
checksum is asked for at the same URL and `.sha256`, and where the mirror answers 404
the hook asks `util.DownloadInfoUrl` for it once more, so a mirror may serve the zips
alone. `Available` never uses the mirror. [mirror.md](mirror.md) is the user's side of
it.

## Tests

The hook tests run offline under `vfox plugin test`, which vfox 1.0.13 and later
has. It finds every `tests/**/*_test.lua` and runs each file in a VM of its own, so
a new test file needs no entry anywhere:

```bash
vfox plugin test .
vfox plugin test . --file tests/pre_install_test.lua
```

Run it from the repository root. The Test Plugin workflow installs the release
pinned in `.github/workflows/test.yml`, and the dev container carries the same one.

A test file calls `test.load()` from `vfox.test` once, and calls the real hooks
through what it returns, as in `plugin:PreInstall({ version = "8.7" })`. `test.load`
takes the platform (`os`, `arch`), the environment variables (`env`) and a function
that answers every HTTP request (`http`). The modules in `lib` can be required
after it. See vfox's [Test and debug a plugin](https://vfox.dev/plugins/create/testing.html).
The context and the result of a hook go through the decoding vfox does, so a hook
that returns a bare string where vfox wants a table fails the test.

- `available_test.lua` reads `tests/fixtures/releases.html` and checks the list
  that comes out: every release, newest first although the page lists them by date,
  one request to gradle.org, and the one error for a status that is not 200 and for
  a request that fails.
- `pre_install_test.lua` answers the request for the sum from a table of URLs, and
  asserts which URLs the hook asked for, in order. It covers the URL with and without a
  mirror, the User-Agent, the forms of the digest file, and every outcome of the
  request: 200, 404, any other status, and a failure of the network. For a mirror's
  404 it covers what services.gradle.org then answers, and that a mirror's other
  failures do not reach it.
- `env_keys_test.lua` and `util_test.lua` cover `EnvKeys` and the comparison of
  versions.

The tests do not see the environment of the machine: `os.getenv` answers for
`VFOX_GRADLE_MIRRORS` from a table in `pre_install_test.lua`, which sets the mirror
for each case, so a mirror in your own shell does not change them. gopher-lua 1.1.1
loses a `local x = nil` that a closure assigns after a `pcall`: the outer scope
still reads `nil`. That is why the state the HTTP function reads is kept in a table
field.

To call one hook against the real servers, vfox 1.0.13 and later has
`vfox plugin run`. It does not register the plugin, `--os` and `--arch` answer for
another platform, `--offline` rejects HTTP, and `VFOX_GRADLE_MIRRORS` applies, so
unset it first if your shell sets it:

```bash
vfox plugin run . Available --json
vfox plugin run . PreInstall --input '{"version":"8.7"}' --json
vfox plugin run . EnvKeys --input '{"path":"C:\\vfox\\gradle-8.7"}' --os windows --arch amd64 --json
```

`vfox --debug <command>` shows what vfox does with a hook, which is how to find an
error it swallows.

The container tests, lint and license headers are in [e2e.md](e2e.md#local-checks).
Lua is formatted with StyLua (`stylua.toml`: 4 spaces, 120 columns), checked by LuaLS
at `Warning` level (`.luarc.json` declares `PLUGIN` and `RUNTIME`), and the
workflows by actionlint. Source files (Lua, Go, YAML, TOML, PowerShell and the Dockerfiles)
carry the license header, Markdown and JSON do not.

## Refreshing the fixture

`tests/fixtures/releases.html` is a copy of blocks of the live page, see
[its README](../tests/fixtures/README.md). When gradle.org changes the markup,
`vfox search gradle` fails the container tests first, because they read the real
page. Replace the blocks with ones of the new page, and change `Available` and the
test together.

## Known gaps

- `Available` reads the HTML of gradle.org/releases, the `<a name="…"></a>` anchor
  of each release. If the markup changes, the hook returns an empty list, which vfox
  keeps for 12 hours, and `latest` finds nothing. `https://services.gradle.org/versions/all`
  is a JSON listing of 534 entries on 2026-11-03 (releases, release candidates,
  snapshots and nightlies, with `version`, `snapshot`, `nightly`, `rcFor`,
  `downloadUrl` and `checksumUrl`) that does not depend on the markup and would list
  the release candidates.
- Only the binary-only distribution (`-bin`) is installed, not the complete one
  (`-all`). Snapshots and nightlies, which Gradle serves from `distributions-snapshots`,
  are out of reach.
- The digest of a mirror that has a `.sha256` comes from the same server as the zip,
  so it guards against a damaged download, not against a mirror that serves a pair
  that fits. A mirror with none is held to the digest of services.gradle.org, which is
  stricter, and services.gradle.org is not asked where the mirror has one: asking it
  first would hold every mirror to it, and need it on the networks that use a mirror
  because it is slow or blocked.
- vfox saves the body of a download that is answered with anything but 404 as the
  archive, the page of a 403 for one, and reports `Checksum error`
  ([vfox#746](https://github.com/version-fox/vfox/issues/746)). That is vfox's, not
  the plugin's, and the `User-Agent` above is what keeps the plugin clear of the one
  case that was met.
- The container tests cover Linux and Windows containers, amd64 and arm64. macOS has
  no job, and the Windows suite leaves out the checks that use the mirror stand-in, see
  [e2e.md](e2e.md#what-the-suite-leaves-out).

## Releasing

A maintainer publishes from **Actions → Plugin → Run workflow** on the default
branch, entering a stable plugin version without the `v` prefix. The shared
workflow, [plugin-manifest-action](https://github.com/version-fox/plugin-manifest-action),
updates `metadata.lua`, creates the version commit and the tag, and publishes the
ZIP and the manifest in this repository. No local tag or extra release token is
needed. Pull requests run the checks only; PR titles no longer trigger publication.

Pushing a version tag publishes too, when `PLUGIN.version` already matches the tag.
If publication fails, re-run the original failed job to resume it. The workflow
follows the shared `@v1` release tool, and updating the tool does not release this
plugin. The shared workflow's documentation has the package contract and the
requirements of a first rollout. Afterwards `plugins/gradle.json` in
[vfox-plugins](https://github.com/version-fox/vfox-plugins) shows the version that
`vfox add gradle` serves.

### After a release

While `main` is ahead of the last release, the documentation marks what is newer
with "Unreleased" ("未发布" in Chinese): the entries sit under an "Unreleased"
heading at the top of [changes.md](changes.md), a page that describes the new
behavior adds a remark that starts with "Unreleased: release X.Y.Z" and tells what
the last release does, and the README has a paragraph that explains the mark and
points at [changes.md](changes.md) and
[install-from-source.md](install-from-source.md). After a release, move the entries
in [changes.md](changes.md) under the new version, with its date, and take the
remarks and the README paragraph out, in both languages:
`grep -rn -i -e unreleased -e 未发布 docs README*` (the hits in this section stay).
Also search for the number of the previous release: a few sentences compare against
it without saying "Unreleased", some of them without the number ("before this", "used
to"), and a few point at a remark that is going out, such as "see above".

## Writing the docs

English pages are in `docs/`, the Chinese ones in `docs/zh-CN/` under the same names
(the Chinese README is `README_CN.md`), and each page starts with a link to the other
language. A new page goes into the Documentation list of both READMEs. Pages that
quote data give the day it was taken (the mirror list, the number of releases, the
redirects of a download), and nothing checks them. CI does not lint Markdown, so run
the commands you add, and the outputs in a page are the ones they printed. When a
change in the plugin makes a page wrong, change the page and its translation in the
same pull request. A link to `page.md#heading` in a Chinese page uses the heading of
the Chinese page, whose address is not the English one.
