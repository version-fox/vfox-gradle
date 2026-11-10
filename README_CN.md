# vfox-gradle

[中文](README_CN.md) | [English](README.md)

[vfox](https://vfox.dev/) 的 [Gradle](https://gradle.org/) 插件。

它安装 Gradle 在 [services.gradle.org](https://services.gradle.org/distributions/)（或其[镜像](docs/zh-CN/mirror.md)）上发布的二进制发行包，并用 Gradle 在旁边发布的 SHA-256 校验和检查每一次下载。`vfox search gradle` 列出的是 [gradle.org/releases](https://gradle.org/releases/) 上的版本。

## 安装

先安装 [vfox](https://github.com/version-fox/vfox)，然后安装插件和某个 Gradle 版本，并选中它：

```bash
vfox add gradle
vfox install gradle@8.7
vfox use --global gradle@8.7
gradle --version
```

`gradle --version` 会显示当前选中的版本。要让 `gradle` 出现在 `PATH` 里，需要先把 vfox 挂载到 Shell，见 vfox 的[快速入门](https://vfox.dev/zh-hans/guides/quick-start.html)。`vfox use` 还可以用 `--project`（当前目录）和 `--session`（当前 Shell，默认）限定更小的范围。

`vfox search gradle` 会从新到旧列出各个版本，在交互式终端里还可以直接选一个并安装。

## Java

Gradle 运行在 JVM 上，所以要先装好 JDK。没有 JDK 时，`gradle` 会停在 `ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.`。JDK 同样可以用 vfox 装，用 [java 插件](https://github.com/version-fox/vfox-java)：

```bash
vfox add java
vfox install java@21-tem
vfox use --global java@21-tem
```

每个 Gradle 版本能在哪些 Java 上运行，见 Gradle 的[兼容性矩阵](https://docs.gradle.org/current/userguide/compatibility.html)：2026-11-03 时，9.8.2 需要 Java 17 到 27，8.14 系列可以在 Java 8 到 24 上运行。插件设置 `GRADLE_HOME` 和 `PATH`，`JAVA_HOME` 留给你自己设置。

构建用 `java.toolchain` 向 Gradle 要它自己的 JDK、再让 Foojay 插件去下载的做法，在 vfox 安装的 Gradle 上照常工作，插件不参与其中。[docs/zh-CN/java-toolchains.md](docs/zh-CN/java-toolchains.md) 区分了运行 Gradle 的 JDK 和构建使用的 JDK，说明了 Gradle 为什么看不到 vfox 装的其他 JDK，以及怎样让它用上。

带有 Gradle Wrapper（`./gradlew`）的项目会自己下载它指定的 Gradle。在项目根目录，`gradle` 会跟随 wrapper 的 `distributionUrl`（装过那个版本的情况下），所以构建用的是同一个 Gradle；`.vfox.toml` 里写的版本优先。详见[docs/zh-CN/versions.md](docs/zh-CN/versions.md#wrapper-项目)。`./gradlew` 自己永远跑它下载的那个。

## 版本与命名

版本就是 `vfox search gradle` 里列出的版本名：`8.7`、`8.14.3`、`9.0.0`。Gradle 在 8.x 之前把每个系列的第一个版本写成没有第三位的形式（`8.7`，不是 `8.7.0`），从 9.0.0 起才带上，所以请从列表里抄版本名。`latest` 是最新版本。只写大版本号（`gradle@8`）不是一个版本，无法安装。安装后的名字就是版本号，`vfox uninstall gradle@8.7` 必须写全。详见 [docs/zh-CN/versions.md](docs/zh-CN/versions.md)，其中还讲了候选版本（RC）、`vfox use gradle@8` 会选中哪个版本，以及 wrapper 项目。

## 镜像

设置 `VFOX_GRADLE_MIRRORS`，就可以从 `services.gradle.org/distributions` 的镜像下载，例如华为云的：

```bash
export VFOX_GRADLE_MIRRORS=https://repo.huaweicloud.com/gradle
vfox install gradle@8.7
```

注意名字末尾的 S。镜像要提供什么样的目录结构、检查过哪些镜像，以及 PowerShell 的写法，见 [docs/zh-CN/mirror.md](docs/zh-CN/mirror.md)。

## 已有的安装

未发布：vfox 1.1.0 及更高版本，插件 0.1.3 及更高版本。见[docs/zh-CN/changes.md](docs/zh-CN/changes.md) 和 [docs/zh-CN/install-from-source.md](docs/zh-CN/install-from-source.md)。

机器上已经有、但不是 vfox 装的 Gradle，可以链接进来，不用再下载。SDKMAN!、Homebrew、mise、asdf、系统和手动安装（Windows 上包括 Chocolatey、Scoop 和 WinGet），以及 Gradle wrapper 下载好的发行包，都能被找到：

```bash
vfox link --detect gradle
```

vfox 会列出找到的，确认后才链接。链接进来的版本和装的版本用法一样，只是 `vfox uninstall` 只删链接，文件留在原地。搜了哪些地方，见[docs/zh-CN/development.md](docs/zh-CN/development.md)；wrapper 项目怎么跟随版本，见[docs/zh-CN/versions.md](docs/zh-CN/versions.md#wrapper-项目)。

## 平台

Gradle 的二进制发行包是同一个 zip，各个系统通用（`bin/gradle` 和 `bin/gradle.bat`），插件本身没有针对任何系统的代码。[E2E 测试](docs/zh-CN/e2e.md)运行在 Linux 上，包括 amd64 和 arm64；Windows 和 macOS 没有在 CI 里测试。

## 文档

**使用插件**

- [版本与命名](docs/zh-CN/versions.md)：怎样写版本、`latest`、候选版本，以及 `vfox use` 会选中什么
- [镜像](docs/zh-CN/mirror.md)：`VFOX_GRADLE_MIRRORS`、镜像要提供什么，以及检查过的镜像
- [Java toolchain](docs/zh-CN/java-toolchains.md)：Foojay 插件、运行 Gradle 的 JDK 与构建用的 JDK，以及让 Gradle 使用 vfox 装的 JDK
- [问题排查](docs/zh-CN/troubleshooting.md)：插件和 vfox 的各种提示、代理设置和 Gradle 的位置
- [变更记录](docs/zh-CN/changes.md)：每个版本改了什么

**参与开发**

- [从源码安装](docs/zh-CN/install-from-source.md)：在下一个版本发布之前用上 `main`
- [开发](docs/zh-CN/development.md)：插件的工作方式、修改方法和发布流程
- [E2E 测试](docs/zh-CN/e2e.md)：开发容器和容器测试

## 致谢

- [Gradle](https://gradle.org/)，插件安装用的版本列表、发行包和 SHA-256 校验和都来自它
