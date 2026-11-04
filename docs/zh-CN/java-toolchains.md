# Java toolchain 与 Foojay 插件

[中文](java-toolchains.md) | [English](../java-toolchains.md)

Gradle 构建可以用 `java.toolchain` 写明自己需要的 JDK。Gradle 会用该版本的 JDK 编译和测试，不管它自己运行在哪个 JDK 上；找不到时，只要有设置插件告诉它去哪里下载，它就会下载一个。常用的插件是 [Foojay Toolchains](https://github.com/gradle/foojay-toolchains)，即 `org.gradle.toolchains.foojay-resolver-convention`。这个功能本身见 Gradle 的文档 [Toolchains for JVM projects](https://docs.gradle.org/current/userguide/toolchains.html)。

vfox 插件不参与其中。它设置 `GRADLE_HOME` 和 `PATH`，而 Gradle 下载的 JDK 放在 Gradle 用户目录下的 `jdks` 里，也就是 `~/.gradle/jdks`，vfox 不会去那里找。所以带有 Foojay 插件的构建，在 vfox 安装的 Gradle 上不需要插件做任何事。本页讲的是 vfox 同时安装 JDK 时容易出错的地方。

本页的内容都在 Linux（amd64）上、在单独的主目录里运行过，用的是 vfox 1.0.13、Gradle 9.8.2 和 [vfox-java](https://github.com/version-fox/vfox-java) 0.6.5（Temurin 17.0.21 和 21.0.13）。输出就是命令在 2026-11-04 打印的那些，主目录写成 `~`。没有运行过的内容列在最后。

## 推荐做法

- **让构建自给自足。** 用 `java.toolchain` 写明需要的 JDK，在 `settings.gradle.kts` 里加上 Foojay 插件（Gradle 9 要用 1.0.0 或更高版本），再用 wrapper 固定 Gradle 版本。构建在没有 vfox 的机器上也应该能通过，所以不要让它依赖 vfox 里装了什么。Gradle 自己的文档也是这个建议：用 toolchain，`JAVA_HOME` 只作机器的默认 JDK（Gradle 9.8.2 的文档，2026-11-04）。
- **vfox 用来选运行 Gradle 的 JDK**，选一个你的 Gradle 版本和 Foojay 插件都接受的较新的 LTS（插件 1.0.0 需要 Java 17 或更高），再用来管理没有 wrapper 的项目所用的 Gradle。不要为了迎合某个 toolchain 去改 `JAVA_HOME`。
- **让 Gradle 自己下载它需要的 JDK。** 一个 JDK 只下载一次，所有项目共用，Temurin 17.0.21 在磁盘上约 500 MB。
- **只有代价太高时**（网络慢或被挡、磁盘紧张），才让 Gradle 去用 vfox 装好的 JDK：用 Gradle 文档承诺的 `org.gradle.java.installations.paths`，或者 `~/.jdks` 里的链接，见[下文](#让-gradle-用-vfox-装的-jdk)。

## 两个 JDK

一个 Gradle 构建涉及两个 JDK，而 `vfox use java@…` 只能选第一个：

- **运行 Gradle 的 JDK**。构建脚本和插件（包括 Foojay 插件）都运行在它上面。它是 `JAVA_HOME`，或者 `PATH` 里的 `java`，见 README 里的 [Java](../../README_CN.md#java)。（构建也可以用 Daemon JVM criteria，即 `gradle/gradle-daemon-jvm.properties`，给 daemon 指定自己的 JDK，它的优先级高于 `JAVA_HOME`，见 Gradle 的 [daemon 文档](https://docs.gradle.org/current/userguide/gradle_daemon.html)。本页不涉及。）
- **构建使用的 JDK**，即 toolchain。编译和测试项目的是它。构建写明版本，Gradle 找一个匹配的 JDK，或者下载一个。

一个要 Java 17 的构建，带着 Foojay 插件，再加一个把两者都打印出来的任务：

```kotlin
// settings.gradle.kts
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "demo"
```

```kotlin
// build.gradle.kts
plugins {
    java
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

tasks.register("jvms") {
    val compiler = javaToolchains.compilerFor(java.toolchain)
    doLast {
        println("Gradle runs on:   " + System.getProperty("java.home"))
        println("javac comes from: " + compiler.get().metadata.installationPath)
    }
}
```

选中 `gradle@9.8.2` 和 `java@21-tem`（`vfox use --global`），同时也装了 `java@17-tem`：

```bash
gradle --version
gradle jvms
```

```text
Gradle 9.8.2
Launcher JVM:  21.0.13 (Eclipse Adoptium 21.0.13+9-LTS)
Daemon JVM:    ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem (no Daemon JVM specified, using current Java home)
...
Gradle runs on:   ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
javac comes from: ~/.gradle/jdks/eclipse_adoptium-17-amd64-linux.2
```

第一条命令的输出缩短成了要紧的几行。Gradle 运行在 21 上，编译用的是它下载到 `~/.gradle/jdks` 的 17，尽管 `java@17-tem` 已经装好了。一次下载是 185 MB，Gradle 把压缩包留在旁边，解压后是 319 MB（Temurin 17.0.21）。之后的构建会找到解压好的 JDK，不会再下载。删除 `~/.gradle/jdks` 就是把它们删掉，下一个需要 JDK 的构建会再下载。

### Foojay 插件与 vfox 选中的 Gradle

Foojay 插件运行在 vfox 选中的 Gradle 里、运行 Gradle 的那个 JDK 上，所以这两个选择决定哪个版本的插件能用。它的 [README](https://github.com/gradle/foojay-toolchains) 写道（2026-11-04）：1.0.0 及以后需要 Java 17 或更高、Gradle 7.6 或更高，更早的版本需要 Gradle 7.6 到 8.14.x。选中 Gradle 9.8.2 时，固定使用 0.10.0 的构建，一旦需要一个没装的 JDK 就会失败：

```text
> Class org.gradle.jvm.toolchain.JvmVendorSpec does not have member field 'org.gradle.jvm.toolchain.JvmVendorSpec IBM_SEMERU'
```

把构建改用 1.0.0，它是 2026-11-04 的最新版本。这些要求里只有这个失败运行过，1.0.0 需要的 Java 17 没有运行过。

## Gradle 不会去 vfox 的目录里找

下载之前，Gradle 会在固定的几个位置找一个匹配的已安装 JDK。它的文档列出了这些位置（2026-11-04）：Linux、macOS 和 Windows 的常见目录、`JAVA_HOME`、版本管理工具 Asdf-vm、Jabba 和 SDKMAN!、Maven 的 toolchain 规格，以及 IntelliJ IDEA 安装的 JDK，见[自动探测](https://docs.gradle.org/current/userguide/toolchains.html#sec:auto_detection)。vfox 不在其中，Gradle 也不会加上它：对 vfox 的请求（[gradle/gradle#29195](https://github.com/gradle/gradle/issues/29195)）在 2024-06 被关闭为 not planned，回复是 Gradle 不想再增加内置的来源，而是想做一个让第三方贡献来源的机制（[gradle/gradle#29508](https://github.com/gradle/gradle/issues/29508)，2026-11-04 仍是 open）。vfox 装的 JDK 里，Gradle 只找得到它自己运行所用的那个，也就是正在使用的那个。使用 21、装了 17 时，`javaToolchains` 任务只列出 21：

```bash
gradle -q javaToolchains
```

```text
 + Options
     | Auto-detection:     Enabled
     | Auto-download:      Enabled

 + Eclipse Temurin JDK 21 (21.0.13+9-LTS)
     | Location:           ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
     | Language Version:   21
     | Vendor:             Eclipse Temurin
     | Architecture:       amd64
     | Is JDK:             true
     | Detected by:        Current JVM
```

`vfox use --global java@17-tem` 之后，它只列出 17。所以上面的构建下载了自己的 17。`settings.gradle.kts` 里没有 Foojay 插件时，同样的构建会直接失败：

```text
> Cannot find a Java installation on your machine (...) matching: {languageVersion=17, vendor=any vendor, implementation=vendor-specific, nativeImageCapable=false}. Toolchain download repositories have not been configured.
```

`(...)` 代表操作系统和 CPU。JDK 明明装着，Gradle 却不知道它在哪里。

## 让 Gradle 用 vfox 装的 JDK

不做这一步构建也能运行，只是每个不是正在使用的版本都要下载一次。想复用 vfox 装好的，就告诉 Gradle 它们在哪里，有两种办法。装了或卸载了 JDK 之后，两种办法都要重新做。

### `org.gradle.java.installations.paths`

Gradle 的这个属性是一个用逗号分隔的 JDK 目录列表，也是 Gradle 文档给它没有探测到的 JDK 准备的接口，见[自定义 toolchain 位置](https://docs.gradle.org/current/userguide/toolchains.html#sec:custom_loc)。把它写进 Gradle 用户目录的 `gradle.properties`，即 `~/.gradle/gradle.properties`（设置了 `$GRADLE_USER_HOME` 时在那里），这样它对每个构建都有效，也不需要任何仓库带着它。目录是 `~/.vfox/cache/java/v-<版本>/java-<版本>`，见 vfox-java 文档里的 [JDK 在哪里](https://github.com/version-fox/vfox-java/blob/main/docs/zh-CN/troubleshooting.md#jdk-在哪里)。下面的命令打印出包含 vfox 装的所有 JDK 的那一行：

```bash
echo "org.gradle.java.installations.paths=$(ls -d ~/.vfox/cache/java/v-*/java-* | paste -sd, -)"
```

```text
org.gradle.java.installations.paths=/home/me/.vfox/cache/java/v-17.0.21+9-tem/java-17.0.21+9-tem,/home/me/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
```

（`/home/me` 代表你的主目录。）这一行写进文件、`~/.gradle/jdks` 删掉之后，`gradle -q javaToolchains` 会把 17 也列出来，写成 `Detected by: Gradle property 'org.gradle.java.installations.paths'`，`gradle jvms` 打印：

```text
Gradle runs on:   ~/.vfox/cache/java/v-21.0.13+9-tem/java-21.0.13+9-tem
javac comes from: ~/.vfox/cache/java/v-17.0.21+9-tem/java-17.0.21+9-tem
```

什么也没有下载，`~/.gradle/jdks` 也没有生成。路径必须是绝对路径：属性里写 `~` 时，没有找到那个 17，构建又下载了一个。

### `~/.jdks` 里的链接

Gradle 也会取 `~/.jdks` 里的 JDK，那是 IntelliJ IDEA 的下载目录。所以 [vfox-java 文档](https://github.com/version-fox/vfox-java/blob/main/docs/zh-CN/troubleshooting.md#jdk-在哪里)为 IDEA 建的那些链接对 Gradle 同样有效，不用再做别的：

```bash
mkdir -p ~/.jdks
for d in ~/.vfox/cache/java/v-*/java-*; do ln -sfn "$d" ~/.jdks/"$(basename "$d")"; done
```

有了这些链接，`gradle -q javaToolchains` 把 17 列为 `Detected by: IntelliJ`，`gradle jvms` 打印的还是上面那两行：它用 vfox 的 17 编译，什么也不下载。卸载了的 JDK 留下的链接要删掉。

## 没有运行过的内容

Windows 和 macOS。9.8.2 以外的 Gradle。Temurin 以外的 JDK。Daemon JVM criteria。Foojay 插件 1.0.0 需要的 Java 17，那是它的 README 的说法。
