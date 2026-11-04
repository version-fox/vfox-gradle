# 变更记录

[中文](changes.md) | [English](../changes.md)

每个版本改了什么，从用户的角度来写。GitHub 的[发布页](https://github.com/version-fox/vfox-gradle/releases)列出了各个版本。写作时最新的发布版是 0.1.1，`main` 比它多出“未发布”下面的全部内容。[install-from-source.md](install-from-source.md) 能让你现在就用上这些改动。

## 未发布

- `VFOX_GRADLE_MIRRORS` 的值可以以斜杠结尾，README 以前就是这样写的。0.1.1 版请求的是 `<镜像>//gradle-8.7-bin.zip`，nginx 上的镜像会把它当成同一个文件，不这样做的镜像则回应 404。见 [mirror.md](mirror.md)。
- 华为云的镜像可以用了。0.1.1 版把下载交给 vfox，而 vfox 用 Go HTTP 客户端的 `User-Agent`（`Go-http-client/1.1`）发请求，华为云对它回应 403 和一段 HTML，而不是 zip。vfox 把这段页面保存下来，安装于是以 `Checksum error` 结束。现在下载时的 User-Agent 是 `vfox/<vfox 版本> vfox-gradle/<插件版本>`，和插件自己的请求一样。见 [mirror.md](mirror.md#镜像要提供什么)和 [vfox#746](https://github.com/version-fox/vfox/issues/746)。
- 内容不只是摘要的 `.sha256` 文件也可以用了：`sha256sum` 的格式（`<摘要>  <文件名>`）、摘要后面带换行、用大写字母。0.1.1 版把文本原样交给 vfox，而 vfox 也是原样比较，所以一次完好的下载会以 `Checksum error` 结束。状态码是 200、里面却没有摘要的回应（比如门户网站的页面），现在会让安装停下来，并提示 `no SHA-256 digest in <地址>`。
- 镜像（或挡在镜像前面的防火墙）对校验和请求回应的既不是 200 也不是 404 时，安装会停下来，并提示 `checksum request failed: HTTP <状态码> from <地址>`。0.1.1 版只打印 `no installable runtime provided`。见 [troubleshooting.md](troubleshooting.md)。
- 没有 `.sha256` 文件的镜像，现在用 services.gradle.org 上的校验和来校验。0.1.1 版只问镜像，所以这样的镜像会让 vfox 打印 `WARNING: Checksum is not provided, skip verify...`，然后不管下载到的是什么都信任它。腾讯云的镜像就是这样：2023-02-22 之后加入的 zip 都没有 `.sha256`，8.7 和 9.8.2 也在其中。现在镜像上的 zip 必须就是 Gradle 发布的那一个，否则安装以 `Checksum error` 结束。如果 services.gradle.org 也给不出校验和，比如网络挡住了它，安装和以前一样带着警告继续。见 [mirror.md](mirror.md#镜像要提供什么)。
- `vfox add gradle` 和 `vfox info gradle` 打印的提示现在说明 Gradle 需要 JDK，并链接到 README。

## 0.1.1（2024-04-01）

插件的描述（`vfox info gradle` 会打印）由 “gradle” 改为 “Gradle runtime environment.”。其余是发布工作流的改动。

## 0.1.0（2024-03-27）

第一个发布版。`vfox search gradle` 列出 gradle.org 上的版本，`vfox install` 从 services.gradle.org（或 `VFOX_GRADLE_MIRRORS` 指定的镜像）下载版本并校验它的 SHA-256，`vfox use` 设置 `GRADLE_HOME` 和 `PATH`。
