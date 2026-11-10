# 变更记录

[中文](changes.md) | [English](../changes.md)

每个版本改了什么，从用户的角度来写。GitHub 的[发布页](https://github.com/version-fox/vfox-gradle/releases)列出了各个版本。

## 未发布

- `vfox link --detect gradle` 会找到 vfox 没有装过的 Gradle 安装，确认后链接进来：SDKMAN!、Homebrew、mise 和 asdf 的候选目录、系统和手动安装（Windows 上包括 Chocolatey、Scoop 和 WinGet），以及 Gradle wrapper 下载好的发行包（只收录下载完整的）。需要 vfox 1.1.0 或更高版本（带来了 `Detect` 钩子），旧版 vfox 会忽略这个钩子文件。见 README 和 [development.md](development.md)。
- 另一个 `gradle` 盖住 vfox 选中的版本时，vfox 1.1.0 及更高版本会连同插件的提示一起打印：SDKMAN!、Homebrew、mise、asdf、Chocolatey、Scoop、WinGet 或手动安装，以及怎样把 vfox 放到前面。旧版 vfox 在这里不打印任何内容。见 [troubleshooting.md](troubleshooting.md#另一个-gradle-盖住了-vfox-选中的版本)。
- 安装包在原地被换掉或损坏时，`vfox use` 和 `vfox doctor` 会警告：`Fingerprint` 钩子在每次安装或链接后记下 launcher jar。需要 vfox 1.1.0 或更高版本，旧版 vfox 会忽略这个钩子文件。
- 在 wrapper 项目目录里，装过 wrapper 固定版本的情况下 `gradle` 会跟随它的 `distributionUrl`（`ParseLegacyFile`；`.vfox.toml` 里写的版本优先）。见 [versions.md](versions.md#wrapper-项目)。
- 钩子测试跑在 vfox 1.1.0 上：Test Plugin 工作流和开发容器固定的都是 1.1.0（带来了 `Detect` 和 `Fingerprint` 钩子）。`detect_test.lua` 和 `fingerprint_test.lua` 在 1.0.13 上经直接加载钩子也能过。

## 0.1.2（2026-11-04）

- `VFOX_GRADLE_MIRRORS` 的值可以以斜杠结尾，README 以前就是这样写的。0.1.1 版请求的是 `<镜像>//gradle-8.7-bin.zip`，nginx 上的镜像会把它当成同一个文件，不这样做的镜像则回应 404。见 [mirror.md](mirror.md)。
- 华为云的镜像可以用了。0.1.1 版把下载交给 vfox，而 vfox 用 Go HTTP 客户端的 `User-Agent`（`Go-http-client/1.1`）发请求，华为云对它回应 403 和一段 HTML，而不是 zip。vfox 把这段页面保存下来，安装于是以 `Checksum error` 结束。现在下载时的 User-Agent 是 `vfox/<vfox 版本> vfox-gradle/<插件版本>`，和插件自己的请求一样。见 [mirror.md](mirror.md#镜像要提供什么)和 [vfox#746](https://github.com/version-fox/vfox/issues/746)。
- 内容不只是摘要的 `.sha256` 文件也可以用了：`sha256sum` 的格式（`<摘要>  <文件名>`）、摘要后面带换行、用大写字母。0.1.1 版把文本原样交给 vfox，而 vfox 也是原样比较，所以一次完好的下载会以 `Checksum error` 结束。状态码是 200、里面却没有摘要的回应（比如门户网站的页面），现在会让安装停下来，并提示 `no SHA-256 digest in <地址>`。
- 镜像（或挡在镜像前面的防火墙）对校验和请求回应的既不是 200 也不是 404 时，安装会停下来，并提示 `checksum request failed: HTTP <状态码> from <地址>`。0.1.1 版只打印 `no installable runtime provided`。见 [troubleshooting.md](troubleshooting.md)。
- 没有 `.sha256` 文件的镜像，现在用 services.gradle.org 上的校验和来校验。0.1.1 版只问镜像，所以这样的镜像会让 vfox 打印 `WARNING: Checksum is not provided, skip verify...`，然后不管下载到的是什么都信任它。腾讯云的镜像就是这样：2023-02-22 之后加入的 zip 都没有 `.sha256`，8.7 和 9.8.2 也在其中。现在镜像上的 zip 必须就是 Gradle 发布的那一个，否则安装以 `Checksum error` 结束。如果 services.gradle.org 也给不出校验和，比如网络挡住了它，安装和以前一样带着警告继续。见 [mirror.md](mirror.md#镜像要提供什么)。
- `vfox add gradle` 和 `vfox info gradle` 打印的提示现在说明 Gradle 需要 JDK，并链接到 README。

其余的内容不在 vfox 安装的插件里：测试、lint 和许可证检查、开发容器，以及中英文文档，其中包括一篇讲 [Java toolchain](java-toolchains.md) 的页面。

## 0.1.1（2024-04-01）

插件的描述（`vfox info gradle` 会打印）由 “gradle” 改为 “Gradle runtime environment.”。其余是发布工作流的改动。

## 0.1.0（2024-03-27）

第一个发布版。`vfox search gradle` 列出 gradle.org 上的版本，`vfox install` 从 services.gradle.org（或 `VFOX_GRADLE_MIRRORS` 指定的镜像）下载版本并校验它的 SHA-256，`vfox use` 设置 `GRADLE_HOME` 和 `PATH`。
