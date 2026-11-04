# Mirror

[中文](zh-CN/mirror.md) | [English](mirror.md)

The plugin downloads a release from `https://services.gradle.org/distributions`,
which sends it on to the releases of Gradle on GitHub, and reads the SHA-256 sum
from the same address. Set `VFOX_GRADLE_MIRRORS` to use a mirror that keeps the
same files. Mind the S: the name is plural.

```bash
export VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle
vfox install gradle@8.7
```

The value is the address that `gradle-<version>-bin.zip` sits under. The plugin
puts a `/`, the file name and, for the sum, `.sha256` after it. For 8.7:

| `VFOX_GRADLE_MIRRORS` | vfox downloads | and reads the sum from |
| --- | --- | --- |
| not set | `https://services.gradle.org/distributions/gradle-8.7-bin.zip` | the same address and `.sha256` |
| `https://repo.huaweicloud.com/gradle` | `https://repo.huaweicloud.com/gradle/gradle-8.7-bin.zip` | the same address and `.sha256`, or services.gradle.org if the mirror has none |

Slashes at the end of the value are left out, so `https://repo.huaweicloud.com/gradle/`
asks for the same files.

An empty value is the same as unset.

## Setting it

The variable is read from the environment of the process that runs vfox, so set
it where your shell does:

```bash
# bash, zsh: in ~/.bashrc or ~/.zshrc
export VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle

# fish
set -Ux VFOX_GRADLE_MIRRORS https://repo.huaweicloud.com/gradle

# for one command
VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle vfox install gradle@8.7
```

```powershell
# PowerShell: this session only
$env:VFOX_GRADLE_MIRRORS = "https://repo.huaweicloud.com/gradle"

# PowerShell: for the user, in the shells you open later
[Environment]::SetEnvironmentVariable("VFOX_GRADLE_MIRRORS", "https://repo.huaweicloud.com/gradle", "User")
```

## What a mirror has to serve

The files of `services.gradle.org/distributions`, under its own address. The zip is
the one that has to be there; the `.sha256` may be left out, see below:

```text
<mirror>/gradle-8.7-bin.zip.sha256
<mirror>/gradle-8.7-bin.zip
```

- The `.sha256` holds the digest, 64 hexadecimal digits. Gradle's own holds
  nothing else. A file written by `sha256sum` (`<digest>  <file>`), one with a
  newline after the digest and one in capitals work as well: the plugin takes the
  digest out and lower-cases it. A 200 that holds no digest, such as the page of a
  portal, stops the install with `no SHA-256 digest in <address>`. vfox compares
  the digest with the hash of what it downloaded, and a mirror whose zip differs
  from its digest ends in `Checksum error`. The digest comes from the mirror as
  well, so it guards against a damaged download, not against a mirror that serves
  a zip and a digest that fit each other. Use a mirror you trust. A mirror with no
  `.sha256` is held to the digest of services.gradle.org instead, see below.
- A mirror with no `.sha256` files, one that answers 404, still installs, and the
  zip is still verified: the plugin reads the digest from
  `https://services.gradle.org/distributions/gradle-8.7-bin.zip.sha256` instead,
  and vfox compares it with the hash of the zip of the mirror. A zip that is not the
  one Gradle published ends in `Checksum error`. The mirror is asked first and
  services.gradle.org only after its 404, so a mirror that has the `.sha256` does not
  need services.gradle.org at all. If services.gradle.org gives no digest either, as
  on a network that blocks it, or with an answer that is not a 200 that holds one, the
  plugin gives vfox none: vfox prints `Verifying checksum ...` and `WARNING: Checksum
  is not provided, skip verify...` and trusts the download. A network that drops the
  traffic to services.gradle.org makes the install wait first, see
  [troubleshooting.md](troubleshooting.md#warning-checksum-is-not-provided-skip-verify).
- Any other answer for the `.sha256`, such as the 403, 500 or 567 of a gateway or
  a firewall, stops the install and names the address, as in
  `checksum request failed: HTTP 567 from https://mirror.example/gradle/gradle-8.7-bin.zip.sha256`.
  services.gradle.org is not asked in its place.
- The download is made as `vfox/<vfox version> vfox-gradle/<plugin version>`.
- Redirects are followed.
- The list comes from gradle.org, not from the mirror: `vfox search gradle` and
  `gradle@latest` see the releases of [gradle.org/releases](https://gradle.org/releases/).
  A release the mirror does not carry fails at the download with
  `source file not found`.

## Mirrors that were checked

Checked on 2026-11-03 by installing with `vfox install gradle@…` from one
network. The list records that and endorses nothing. A mirror can change or go
away without the plugin knowing, and one can answer another network differently.

| Mirror | `VFOX_GRADLE_MIRRORS` | Result |
| --- | --- | --- |
| Huawei Cloud | `https://repo.huaweicloud.com/gradle`, or `https://mirrors.huaweicloud.com/gradle` | installed 8.7 from each and verified it. With release 0.1.1: `Checksum error`, see [changes.md](changes.md) |
| Nanjing University | `https://mirror.nju.edu.cn/gradle` | installed 8.7 and 9.0.0 and verified them |
| CERNET | `https://mirrors.cernet.edu.cn/gradle` | the joint site of the campus mirrors. It redirects each request to one of them, here to Nanjing University's, and vfox follows. Installed 8.7 and verified it |

Each keeps a `.sha256` next to the zip with the same digest as services.gradle.org.

Tencent Cloud's (`https://mirrors.cloud.tencent.com/gradle`) keeps the zips and not
the sums. Its file listing of 2026-11-04 has 536 `-bin.zip`: the 342 listed on or
before 2023-02-22 have a `.sha256`, and the 194 listed after it have none, 53 stable
releases among them, 8.7 and 9.8.2 included. `gradle-9.8.2-bin.zip` is there
(151,620,138 bytes, the size of Gradle's own) and its `.sha256` answers 404. It fits
the layout, and the sum comes from services.gradle.org. No install was made through
the real mirror: it answered 567 to the network this page was written on, and the
listing was read from another one. The E2E tests use a stand-in that behaves like it,
see [e2e.md](e2e.md#what-the-suite-verifies).

Some mirrors that people mention do not fit:

- Alibaba Cloud (`https://mirrors.aliyun.com/gradle/distributions`) keeps each zip
  in a directory of its release, `v8.7.0/gradle-8.7-bin.zip` for 8.7, and has no
  `.sha256`. `VFOX_GRADLE_MIRRORS` names the directory that holds the zips, so
  there is nothing to point it at, and `gradle@8.7` ends in `source file not found`.
- Shanghai Jiao Tong University (SJTUG) has two addresses, and neither fits.
  `https://mirror.sjtu.edu.cn/gradle/distributions` answers 200 and a page of HTML
  (`No route for …`) for the zip and for the `.sha256`, so the install stops with
  `no SHA-256 digest in …`. The object storage behind it, on `s3.jcloud.sjtu.edu.cn`,
  answers 403 and not 404 for the `.sha256` it does not have, so the install stops
  with `checksum request failed: HTTP 403`.
- Tsinghua University (`https://mirrors.tuna.tsinghua.edu.cn/gradle`), Beijing
  Foreign Studies University (`https://mirrors.bfsu.edu.cn/gradle`) and USTC
  (`https://mirrors.ustc.edu.cn/gradle`) answered 404: they have nothing at that
  address.

## Checking that it applies

A mirror that does not answer fails instead of falling back to
services.gradle.org, which is how you can tell the variable is read. The error
names the address it asked for:

```bash
VFOX_GRADLE_MIRRORS=https://example.invalid/gradle vfox install gradle@8.7
```

```text
plugin [PreInstall] method error: …/hooks/pre_install.lua:…: HTTP request error: Get "https://example.invalid/gradle/gradle-8.7-bin.zip.sha256": EOF
…
failed to install gradle
```

What follows the colon depends on the network (`EOF`, `no such host`). The search
does not go through the mirror, and vfox keeps its result for 12 hours.

A proxy is a different setting, and covers the mirror as well, see
[troubleshooting.md](troubleshooting.md#network).
