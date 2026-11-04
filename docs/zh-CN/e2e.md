# E2E

[中文](e2e.md) | [English](../e2e.md)

离线的 Lua 钩子测试（`tests/*_test.lua`，由 `vfox plugin test` 运行）在 **Test Plugin** 工作流里运行。端到端套件在 Linux 容器里针对真实的 vfox 和真实的 gradle.org 运行，覆盖 amd64 和 arm64；每个 vfox 渠道（`latest` 和 `main`）都有自己的一次性容器。CI 直接在标准 runner 上运行这套测试（Docker 加 `actions/setup-go` 提供的 Go）。本地则由仓库的开发容器复现这一环境。

下面的章节说明怎样运行这套测试，页末的[套件验证什么](#套件验证什么)列出它检查的全部内容。

## 开发容器

`.devcontainer/` 提供一个 Linux 开发环境，在四种宿主平台上都能用：

| 宿主 | 开发容器的运行方式 |
| --------------------- | ---------------------------------------------- |
| Linux amd64 / arm64 | 原生运行 |
| Windows amd64 / arm64 | Docker Desktop 的 Linux 容器模式（WSL 2） |

它带有 Go 1.27.1（CI 安装的版本）、Docker CLI、stylua、lua-language-server、actionlint、许可证工具，以及运行离线钩子测试的 vfox，版本都与 `.github/workflows/lint.yml`、`license.yml` 和 `test.yml` 里固定的一致，并挂载宿主的 Docker daemon socket。套件随后通过 testcontainers 连接这个 daemon（Docker-out-of-Docker），启动的目标容器和原生 CI runner 启动的完全相同；这里刻意不用 Docker-in-Docker，这样镜像缓存和网络都还是宿主的。镜像不需要工作区里的文件，所以构建上下文保持在 `.devcontainer/`；`postCreateCommand` 会预热 `tests/e2e` 的 Go 模块缓存，第一次运行测试时就不必停下来下载。

用任何支持 Dev Containers 规范的工具都可以打开它：在 VS Code/Cursor 里执行 **Dev Containers: Reopen in Container**，或者用 CLI：

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

`TESTCONTAINERS_RYUK_DISABLED=true` 是预先设好的：Ryuk 会在宿主 daemon 上发布一个端口，并等待套件回连，而 Docker-out-of-Docker 的容器做不到这一点。套件改为通过 `t.Cleanup` 显式终止每个容器；运行被强行中断后遗留的容器，名称都以 `vfox-gradle-e2e-` 开头，可以按这个前缀清理。使用 rootless Docker 的用户，请在打开容器之前先在宿主上 `export DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"`。在 Windows 宿主上，把检出的代码放在 WSL 2 里（例如 `\\wsl$` 下）能让文件和 bind mount 访问保持快速；放在 Windows 文件系统上也能用。

## 环境变量

| 变量 | 默认值 | 含义 |
| -------------------- | ------------- | ------------------------------------------------------------------ |
| `VFOX_VERSION` | `latest main` | 用空格分隔的 vfox 渠道（`latest`、`main`） |
| `GRADLE_VERSION` | `9.0.0` | 从 services.gradle.org 安装的版本，写法与插件一致 |
| `E2E_MAX_JOBS` | `3` | 每台宿主并行的容器数 |
| `E2E_RETRY_ATTEMPTS` | `3` | 每个涉及网络的 exec 的尝试次数（线性退避 10 秒） |

套件还会经由它的镜像替身安装第二个版本 `8.7`，再经由另一个替身安装第三个版本 `1.12`，所以 `GRADLE_VERSION` 不能是这两个版本。`GRADLE_VERSION` 和 `8.7` 要能在镜像自带的 Java 21 上运行（Gradle 8.5 及以后，以及 9.x）；`1.12` 只安装，不运行。你自己 Shell 里的 `VFOX_GRADLE_MIRRORS` 留在宿主上：容器拿到的只是套件给它的环境。

## Linux（Ubuntu 26.04）

在开发容器里，从仓库根目录执行：

```bash
cd tests/e2e
go test -v -timeout 55m -run TestE2E ./linux
```

迭代时可以用环境变量缩小范围：

```bash
VFOX_VERSION=latest E2E_MAX_JOBS=1 go test -v -timeout 55m -run TestE2E ./linux
```

在原生宿主上，同一条命令也能用，只需要两个前提：Docker Engine（rootful 或 rootless）和 Go 1.27.1，CI 里装的就是这两样。使用 rootless Docker 的用户要把 Docker 客户端指向自己的 socket（`export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"`）；开发容器挂载的 socket 已经替你处理了这种情况。

2026-11-03，一个组合用了 113 秒，整个运行（包括构建镜像）用了 175 秒。当时两次安装各下载 134 MB；第三次安装 1.12 又多下载 42 MB。

## 本地检查

在开发容器里执行，下面所有工具都已预装，版本和工作流使用的一致；也可以在宿主上装好同样的工具。

```bash
# Go 和 Lua 检查（.github/workflows/lint.yml）。
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
# 离线的钩子测试（.github/workflows/test.yml）。
vfox plugin test .
```

```bash
# 许可证头（.github/workflows/license.yml）。
license-eye header check
license-eye header fix
```

在只有 Docker 的宿主上，许可证检查和工作流检查改用容器运行（和 CI 用的镜像相同）：

```bash
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header check
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header fix
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
```

## 套件验证什么

每个组合运行同一套流程（每个 vfox 渠道一个长期运行的容器，由 Go 通过类似 `docker exec` 的调用来驱动）。目标镜像带着 Ubuntu 的一个 JDK，因为 Gradle 需要它，但不带 Gradle：`gradle` 只能来自 vfox 安装的内容。

1. vfox 从所要求的渠道安装——最新发布版（`latest`）或从源码构建（`main`）——并且从当前检出的代码注册本地的 `gradle` 插件。然后 `vfox info gradle` 打印的提示必须链接到 README，那里说明了怎样使用镜像，以及 Gradle 需要 JDK。
2. `vfox search gradle` 针对在线的 gradle.org/releases 运行 `Available` 钩子，必须列出套件要安装的两个版本，每个版本只出现一次，并且从新到旧排列，尽管页面是按日期排列的。2026-11-03 它列出了 174 个版本。如果 gradle.org 改了页面的标记，就是在这里暴露出来。
3. 没有这个名字的版本都会失败，提示 `source file not found`，并且什么也没有装上：`99.0`，以及 `8.7.0` 和 `8.14.0`（Gradle 不写第三位）。
4. 用 `VFOX_GRADLE_MIRRORS=https://invalid.example.invalid/` 经由一个不存在的镜像安装会失败，并且错误里写着 `https://invalid.example.invalid/gradle-9.0.0-bin.zip.sha256`：插件读取了这个变量，并且把以斜杠结尾的值和文件名用一个斜杠连起来。0.1.1 版请求的是 `…/gradle//gradle-9.0.0-bin.zip.sha256`。
5. `gradle@latest` 是搜索列出的第一个版本（2026-11-03 是 9.8.2）。安装请求发给那个不存在的镜像，所以 vfox 打印 `Using latest version: 9.8.2`，并在请求它的校验和时失败，不会下载任何东西。
6. 对校验和回应 567 的镜像（网关可能这样），会让安装停下来，并提示 `checksum request failed: HTTP 567 from http://127.0.0.1:8081/gradle-9.0.0-bin.zip.sha256`。0.1.1 版只打印 `no installable runtime provided`。
7. 固定的版本从 services.gradle.org 安装，名字就是它。vfox 必须打印 `Verifying checksum <摘要>...`，摘要是 64 位十六进制数字，而不是 `WARNING: Checksum is not provided, skip verify...`，并且摘要必须是 Gradle 为这个版本发布的那个。vfox 把摘要和它下载到的文件的哈希比较，对不上就让安装失败，所以安装成功就证明摘要是这个文件的。之后 `vfox search gradle` 会把这个版本标上 `(installed)`。
8. `vfox use --global` 之后，新开的、已激活 vfox 的 Shell 里就是这个 Gradle：`gradle --version` 报告这个版本，`GRADLE_HOME`（`~/.vfox/sdks/gradle`）解析到 `~/.vfox/cache/gradle/v-9.0.0/gradle-9.0.0`，`gradle` 是其中的 `bin/gradle`，`vfox current gradle` 报告它，带一个任务的构建能跑起来。最后这一项说明解压出来的发行包作为一个整体可以工作：启动脚本保留了可执行权限，`lib/` 下的库和编译脚本的 Groovy 都能加载。
9. 第二个版本 8.7 经由 `tests/e2e/linux/mirror` 里的镜像替身安装，替身监听容器的回环地址，并向 services.gradle.org 取它要提供的文件。它的行为和真实安装遇到过的镜像一样，所以这次安装证明了 0.1.1 版做不对的三件事。值以斜杠结尾，而替身对带第二个斜杠的路径回应 404。它对 Go 默认的 `User-Agent` 回应 403 和一段 HTML，就像华为云的镜像那样，而 vfox 下载时用的正是这个名字，除非插件另外指定：vfox 把页面当作 zip 保存下来，以 `Checksum error` 结束。它的 `.sha256` 按 `sha256sum` 的写法，`<摘要>  <文件名>` 加一个换行，而 vfox 是原样比较文本的。替身的日志里必须有对 `.sha256` 和对 zip 的 `GET`，都回应 200，并且 vfox 校验所用的摘要必须是 Gradle 发布的那个，同第 7 条。
10. `vfox use` 在两个版本之间切换：每次 `gradle --version`、`GRADLE_HOME` 和 `gradle` 都跟着变（第 8 条）。`vfox list gradle` 列出两个，`vfox uninstall gradle@8.7` 之后另一个仍然可用。
11. 第三个版本 1.12 经由第二个替身安装，这个替身提供 zip，对每个 `.sha256` 都回应 404：一个不保存校验和的镜像，腾讯云的镜像对 8.0.1 之后的版本就是这样。替身的日志里必须有对 `.sha256` 的 `GET`（回应 404）和对 zip 的 `GET`（回应 200）。vfox 仍然必须打印 `Verifying checksum <摘要>...`，而不是 `WARNING: Checksum is not provided, skip verify...`，并且摘要必须是 Gradle 发布的那个，同第 7 条：插件从 services.gradle.org 取得它，vfox 把它和从镜像下载到的 zip 的哈希比较。0.1.1 版不给 vfox 摘要，安装以那条警告收场。这个版本只有 42 MB，也不会运行。

矩阵是两个 vfox 渠道，`latest` 和 `main`，在 runner 具备的每种架构上运行。固定的版本是 `9.0.0`（Gradle 从 9.0.0 起带第三位）、`8.7`（8.x 之前不带）和很小的 `1.12`。旧版本一直可以下载，所以这些固定值不会过时。

## 套件没有覆盖什么

- **Windows 容器和 macOS。** 两者都没有对应的任务。插件本身没有针对任何系统的代码，发行包也是同一个 zip，但 CI 里没有任何东西证明它们能用。Windows 容器套件需要 Windows 宿主，无法在开发容器里运行；可以移植 vfox-java 的 `tests/e2e/windows`。
- **真实的镜像。** 镜像来来去去，所以套件使用自己的替身。手工检查过的镜像见 [mirror.md](mirror.md#检查过的镜像)。
- **代理**，以及 `vfox use` 除 `--global` 之外的作用域。
