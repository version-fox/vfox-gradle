# 问题排查

[中文](troubleshooting.md) | [English](../troubleshooting.md)

## 插件的提示

### `get release info failed.`

`vfox search gradle` 读不到 [gradle.org/releases](https://gradle.org/releases/)：请求失败了，或者页面回应的不是 200。见[网络](#网络)。搜索不经过镜像。

### `HTTP request error: Get "<地址>": ...`

请求 SHA-256 校验和时，还没得到回应就失败了；信息里的地址就是请求的地址：设置了 `VFOX_GRADLE_MIRRORS` 时，它是镜像的地址，见 [mirror.md](mirror.md#确认它生效了)。冒号后面是网络报告的原因。见[网络](#网络)。

### `checksum request failed: HTTP 567 from <地址>`

校验和请求得到了回应，但状态码既不是 200 也不是 404：信息里有状态码，也有地址。是镜像，或者挡在镜像前面的防火墙、门户网站拒绝了这个请求。可以用 `curl` 试这个地址，也可以取消设置 `VFOX_GRADLE_MIRRORS` 改用 services.gradle.org，或者换一个镜像，见 [mirror.md](mirror.md#检查过的镜像)。

未发布：0.1.1 版遇到同样的情况，只打印 `no installable runtime provided` 和 `failed to install gradle`，没有说是哪个请求、什么状态码。想试用 `main`，见 [install-from-source.md](install-from-source.md)。

### `no SHA-256 digest in <地址>`

校验和请求回应了 200，但回应的开头没有 64 位的十六进制摘要：可能是门户网站或防火墙的页面，也可能是被截断的文件。用 `curl` 打开这个地址看看。见 [mirror.md](mirror.md#镜像要提供什么)。这条提示同样是未发布的：0.1.1 版把回应的内容原样当作校验和交给 vfox，安装最终以 `Checksum error` 结束。

## vfox 的提示

### `failed to download gradle@8.7.0 file, err:source file not found`

下载得到了 404：没有这个名字的版本。插件用你输入的版本原样去下载 `gradle-<版本>-bin.zip`，所以请对照 `vfox search gradle` 检查。常见的错误有两个：只写大版本号（`gradle@8`），以及写了 Gradle 不写的第三位（`gradle@8.7.0`，这个版本叫 `8.7`），见 [versions.md](versions.md#怎样写版本)。经由镜像时，镜像回应的 404 也会走到这里：它可能没有这个版本。

### `Checksum error, file: <路径>`

vfox 打印 `Checksum error, file: <路径>`，接着是 `checksum error` 和 `failed to install gradle`，并在解压之前就停了下来，所以什么也没有装上。下载的内容和插件交给 vfox 的 SHA-256 校验和对不上。最常见的原因是下载中断或在路上损坏：重试一次。如果经由镜像时总是这样，可能是镜像提供了另一个文件，或者一段错误页面：vfox 曾把一个 403 的页面当作 zip 保存下来，然后停在这里（0.1.1 版加华为云的镜像，见 [mirror.md](mirror.md#镜像要提供什么)，以及 [vfox#746](https://github.com/version-fox/vfox/issues/746)）。取消设置 `VFOX_GRADLE_MIRRORS`，看看 services.gradle.org 能不能装上。

### `WARNING: Checksum is not provided, skip verify...`

插件没有给 vfox 校验和，所以 vfox 只能信任下载的内容。`.sha256` 请求回应 404 时就是这样，没有这类文件的镜像就会这样，见 [mirror.md](mirror.md#镜像要提供什么)。services.gradle.org 上每个版本都有校验和，vfox 打印的会是 `Verifying checksum <摘要>...`。

### `install requires specifying a version for gradle`

`vfox install gradle@`，`@` 后面什么也没写。请写上版本，或者 `latest`。

### `gradle@8.7 is not installed`

`vfox uninstall` 只认已经安装的，而且要写全名字：`vfox list gradle` 会列出它们。`vfox use` 接受版本的开头，在已安装的版本里查找，但不接受不存在的数字：装着 8.14 时，`gradle@8.1` 什么也找不到。见 [versions.md](versions.md#vfox-use-会选中什么)。

### `vfox requires hook support. Please ensure vfox is properly initialized with 'vfox activate'`

`vfox use` 需要 vfox 已经挂载到你的 Shell。见 vfox 的[快速入门](https://vfox.dev/zh-hans/guides/quick-start.html)。

## Gradle 的提示

### `ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.`

`gradle` 运行在 JVM 上，却没有找到。请安装 JDK 并把它放进 `PATH`，或者设置 `JAVA_HOME`，见 README 里的 [Java](../../README_CN.md#java)。插件不会设置 `JAVA_HOME`。

## 网络

插件从 `gradle.org` 读取版本列表，从 `services.gradle.org` 读取校验和，vfox 也从那里下载 zip。对一个版本来说，这个地址会重定向：校验和重定向到 `downloads.gradle.org`，zip 重定向到 Gradle 在 `github.com` 上的发布，再由 `release-assets.githubusercontent.com` 提供（2026-11-03）。网络挡住其中任何一个主机，安装就会在需要它的那一步失败。想换一个下载地址，见 [mirror.md](mirror.md)。

vfox 自己的代理设置对插件的请求和下载都有效：

```bash
vfox config proxy.enable true
vfox config proxy.url http://127.0.0.1:7890
```

`proxy.enable` 为 `false` 时，通常的 `HTTP_PROXY`、`HTTPS_PROXY` 和 `NO_PROXY` 环境变量依然有效。只支持 `http` 和 `https` 代理。

## 看起来不对，其实没问题

- **`vfox search` 里没有你预期的版本。** vfox 会缓存搜索结果 12 小时。`vfox config cache.availableHookDuration 0` 可以关闭缓存。也可能是 gradle.org 还没有列出这个版本。候选版本永远不会被列出，见 [versions.md](versions.md#候选版本)。
- **`gradle@latest` 不是 gradle.org 上宣布的最新的东西。** `latest` 是 `vfox search gradle` 列出的第一个版本，而候选版本不在列表里。
- **项目用的 Gradle 不是你选中的那个。** 带有 Gradle Wrapper（`./gradlew`）的项目会下载它指定的 Gradle，`gradle` 命令根本没有参与。
- **`gradle --version` 显示的不是你选中的 Gradle。** 不带 `--global` 或 `--project` 的 `vfox use` 只对当前 Shell 有效，而且 `PATH` 里更靠前的目录里的 `gradle` 会胜出。`vfox current gradle` 会显示 vfox 选中的是什么，什么也没选时显示 `no current version of gradle`。

## Gradle 在哪里

`GRADLE_HOME` 是一个链接，由 `vfox use` 指向你选的版本：`--global` 时是 `~/.vfox/sdks/gradle`，它下面的 `bin` 在 `PATH` 里。各个版本本身在 `~/.vfox/cache/gradle/v-<版本>/gradle-<版本>`（E2E 测试里是 `/root/.vfox/cache/gradle/v-9.0.0/gradle-9.0.0`）。需要 Gradle 安装目录、又希望跟随全局选择的 IDE 或构建工具，可以直接指向前者。`~/.vfox` 是 `$VFOX_HOME` 的默认值。设置了它之后，各个版本和链接放在哪里，以及 `storage.sdkPath`，见 vfox 的[配置文档](https://vfox.dev/zh-hans/guides/configuration.html)。

## 报告问题

请到 [version-fox/vfox-gradle](https://github.com/version-fox/vfox-gradle/issues) 提 issue，附上 `vfox --version` 和 `vfox info gradle` 的输出、操作系统和 CPU、你执行的命令以及它打印的全部内容。`vfox --debug <命令>` 会打印更多信息。
