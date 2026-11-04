# 镜像

[中文](mirror.md) | [English](../mirror.md)

插件从 `https://services.gradle.org/distributions` 下载版本，这个地址会再跳转到 Gradle 在 GitHub 上的发布，SHA-256 校验和也从同一个地址读取。想用保存着同样文件的镜像，设置 `VFOX_GRADLE_MIRRORS`。注意末尾的 S：名字是复数。

```bash
export VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle
vfox install gradle@8.7
```

这个值是 `gradle-<版本>-bin.zip` 所在的地址。插件会在后面接上一个 `/`、文件名，读取校验和时再接上 `.sha256`。以 8.7 为例：

| `VFOX_GRADLE_MIRRORS` | vfox 下载 | 校验和从这里读取 |
| --- | --- | --- |
| 未设置 | `https://services.gradle.org/distributions/gradle-8.7-bin.zip` | 同一个地址加 `.sha256` |
| `https://repo.huaweicloud.com/gradle` | `https://repo.huaweicloud.com/gradle/gradle-8.7-bin.zip` | 同一个地址加 `.sha256`；镜像没有时，从 services.gradle.org 读取 |

值末尾的斜杠会被去掉，所以 `https://repo.huaweicloud.com/gradle/` 请求的是同样的文件。

值为空等同于没有设置。

## 怎样设置

这个变量是从运行 vfox 的进程的环境里读取的，所以要按你所用 Shell 设置环境变量的方式来设置它：

```bash
# bash、zsh：写在 ~/.bashrc 或 ~/.zshrc 里
export VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle

# fish
set -Ux VFOX_GRADLE_MIRRORS https://repo.huaweicloud.com/gradle

# 只对一条命令生效
VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle vfox install gradle@8.7
```

```powershell
# PowerShell：只对当前会话有效
$env:VFOX_GRADLE_MIRRORS = "https://repo.huaweicloud.com/gradle"

# PowerShell：对当前用户生效，之后打开的 Shell 里都有
[Environment]::SetEnvironmentVariable("VFOX_GRADLE_MIRRORS", "https://repo.huaweicloud.com/gradle", "User")
```

## 镜像要提供什么

`services.gradle.org/distributions` 上的文件，放在镜像自己的地址下。zip 必须有，`.sha256` 可以没有，见下文：

```text
<mirror>/gradle-8.7-bin.zip.sha256
<mirror>/gradle-8.7-bin.zip
```

- `.sha256` 里是摘要，64 位十六进制数字。Gradle 自己的文件里只有摘要。用 `sha256sum` 写出的文件（`<摘要>  <文件名>`）、摘要后面带换行的文件和用大写字母的文件也都可以：插件会把摘要取出来并转成小写。状态码是 200、里面却没有摘要的回应（比如门户网站的页面），会让安装停下来，并提示 `no SHA-256 digest in <地址>`。vfox 把摘要和它下载到的文件的哈希比较，zip 与摘要对不上的镜像，最终会报 `Checksum error`。摘要同样来自镜像，所以它防的是下载损坏，防不住镜像同时提供一个互相吻合的 zip 和摘要。请使用你信任的镜像。没有 `.sha256` 的镜像则改用 services.gradle.org 的摘要来约束，见下文。
- 没有 `.sha256` 文件的镜像（回应 404）仍然能装，zip 也仍然会被校验：插件改从 `https://services.gradle.org/distributions/gradle-8.7-bin.zip.sha256` 读取摘要，vfox 把它和镜像上那个 zip 的哈希比较。不是 Gradle 发布的那个 zip，会以 `Checksum error` 结束。先问的是镜像，镜像回应 404 之后才问 services.gradle.org，所以有 `.sha256` 的镜像完全不需要 services.gradle.org。如果 services.gradle.org 也给不出摘要，比如网络挡住了它，或者回应不是带着摘要的 200，插件就不给 vfox 摘要：vfox 会打印 `Verifying checksum ...` 和 `WARNING: Checksum is not provided, skip verify...`，然后信任下载的内容。网络若是丢弃发往 services.gradle.org 的流量，安装会先等一会儿，见 [troubleshooting.md](troubleshooting.md#warning-checksum-is-not-provided-skip-verify)。
- 校验和请求的其他回应，比如网关或防火墙给出的 403、500、567，会让安装停下来，并指出地址，例如 `checksum request failed: HTTP 567 from https://mirror.example/gradle/gradle-8.7-bin.zip.sha256`。不会改去问 services.gradle.org。
- 下载时的 User-Agent 是 `vfox/<vfox 版本> vfox-gradle/<插件版本>`。
- 会跟随重定向。
- 版本列表来自 gradle.org，而不是镜像：`vfox search gradle` 和 `gradle@latest` 看到的是 [gradle.org/releases](https://gradle.org/releases/) 上的版本。镜像没有的版本，下载时会以 `source file not found` 失败。

## 检查过的镜像

2026-11-03 在同一个网络里用 `vfox install gradle@…` 实际安装检查过。这份列表只是记录检查结果，不为任何镜像背书。镜像随时可能变化或消失，插件无从得知，换一个网络也可能得到不同的回应。

| 镜像 | `VFOX_GRADLE_MIRRORS` | 结果 |
| --- | --- | --- |
| 华为云 | `https://repo.huaweicloud.com/gradle`，或 `https://mirrors.huaweicloud.com/gradle` | 两个地址都装上了 8.7，校验通过。用 0.1.1 版会得到 `Checksum error`，见[变更记录](changes.md) |
| 南京大学 | `https://mirror.nju.edu.cn/gradle` | 装上了 8.7 和 9.0.0，校验通过 |
| 校园网联合镜像站（CERNET） | `https://mirrors.cernet.edu.cn/gradle` | 它把每个请求重定向到某一所高校的镜像，这次是南京大学的，vfox 会跟随重定向。装上了 8.7，校验通过 |

它们在 zip 旁边都有 `.sha256`，摘要和 services.gradle.org 上的相同。

腾讯云的镜像（`https://mirrors.cloud.tencent.com/gradle`）有 zip，没有校验和。2026-11-04 读取它的文件列表，共有 536 个 `-bin.zip`：列表日期在 2023-02-22 或之前的 342 个有 `.sha256`，之后的 194 个都没有，其中 53 个是正式版，8.7 和 9.8.2 也在内。`gradle-9.8.2-bin.zip` 在列表里（151,620,138 字节，和 Gradle 自己的一样大），它的 `.sha256` 回应 404。它符合目录布局，校验和从 services.gradle.org 取。没有经由真正的镜像安装：它对撰写本页所用的网络回应 567，文件列表是在另一个网络读取的。E2E 测试用一个行为与它相同的替身，见 [e2e.md](e2e.md#套件验证什么)。

有几个常被提到的镜像用不了：

- 阿里云（`https://mirrors.aliyun.com/gradle/distributions`）把每个 zip 放在以版本命名的目录里（8.7 是 `v8.7.0/gradle-8.7-bin.zip`），也没有 `.sha256`。`VFOX_GRADLE_MIRRORS` 指向的是存放 zip 的那个目录，这里没有可指的目录，`gradle@8.7` 会以 `source file not found` 结束。
- 上海交通大学（SJTUG）有两个地址，都用不了。`https://mirror.sjtu.edu.cn/gradle/distributions` 对 zip 和 `.sha256` 都回应 200 和一段 HTML（`No route for …`），所以安装会停在 `no SHA-256 digest in …`。它背后的对象存储（在 `s3.jcloud.sjtu.edu.cn` 上）对它没有的 `.sha256` 回应 403 而不是 404，所以安装会停在 `checksum request failed: HTTP 403`。
- 清华大学（`https://mirrors.tuna.tsinghua.edu.cn/gradle`）、北京外国语大学（`https://mirrors.bfsu.edu.cn/gradle`）和中国科学技术大学（`https://mirrors.ustc.edu.cn/gradle`）回应 404：这个地址下什么也没有。

## 确认它生效了

不可达的镜像会直接失败，而不会回退到 services.gradle.org，由此可以确认变量被读取了。错误信息里会指出请求的地址：

```bash
VFOX_GRADLE_MIRRORS=https://example.invalid/gradle vfox install gradle@8.7
```

```text
plugin [PreInstall] method error: …/hooks/pre_install.lua:…: HTTP request error: Get "https://example.invalid/gradle/gradle-8.7-bin.zip.sha256": EOF
…
failed to install gradle
```

冒号后面是什么取决于网络（`EOF`、`no such host`）。搜索不经过镜像，vfox 会把搜索结果缓存 12 小时。

代理是另一项设置，对镜像同样有效，见 [troubleshooting.md](troubleshooting.md#网络)。
