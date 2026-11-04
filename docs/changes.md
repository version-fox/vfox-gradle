# Changes

[中文](zh-CN/changes.md) | [English](changes.md)

What changed in each release, as a user notices it. GitHub's
[release pages](https://github.com/version-fox/vfox-gradle/releases) list the
releases. The newest release at the time of writing is 0.1.1, and `main` is ahead
of it by everything under "Unreleased".
[install-from-source.md](install-from-source.md) gets you those changes now.

## Unreleased

- `VFOX_GRADLE_MIRRORS` works with a value that ends in a slash, as the README
  wrote it. Release 0.1.1 asks for `<mirror>//gradle-8.7-bin.zip`, which a mirror on
  nginx takes for the same file and others answer 404. See [mirror.md](mirror.md).
- Huawei Cloud's mirror works. Release 0.1.1 leaves the download to vfox, which asks
  with the `User-Agent` of Go's HTTP client, `Go-http-client/1.1`, and Huawei Cloud
  answers that with a 403 and a page of HTML in place of the zip. vfox saves the page
  and the install ends in `Checksum error`. Now the download is made as
  `vfox/<vfox version> vfox-gradle/<plugin version>`, like the requests of the plugin
  itself. See [mirror.md](mirror.md#what-a-mirror-has-to-serve) and
  [vfox#746](https://github.com/version-fox/vfox/issues/746).
- A `.sha256` file that holds more than the digest alone works: the format of
  `sha256sum` (`<digest>  <file>`), a newline after the digest, capitals. Release
  0.1.1 gives vfox the text as it is, and vfox compares it as it is, so a good
  download ends in `Checksum error`. A 200 that holds no digest, such as the page of a
  portal, stops the install with `no SHA-256 digest in <address>`.
- A mirror, or a firewall in front of one, that answers the request for the sum with
  something else than 200 or 404 stops the install with `checksum request failed:
  HTTP <status> from <address>`. Release 0.1.1 prints only `no installable runtime
  provided`. See [troubleshooting.md](troubleshooting.md).
- The notes printed by `vfox add gradle` and `vfox info gradle` say that Gradle needs
  a JDK and link to the README.

## 0.1.1 (2024-04-01)

The description of the plugin, which `vfox info gradle` prints, reads "Gradle runtime
environment." in place of "gradle". The rest is the release workflow.

## 0.1.0 (2024-03-27)

The first release. `vfox search gradle` lists the releases of gradle.org,
`vfox install` downloads a release from services.gradle.org, or from the mirror that
`VFOX_GRADLE_MIRRORS` names, and verifies its SHA-256 sum, and `vfox use` sets
`GRADLE_HOME` and `PATH`.
