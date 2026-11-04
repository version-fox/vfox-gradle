# E2E

[中文](e2e.md) | [English](../e2e.md)

离线的 Lua 钩子测试（`tests/*_test.lua`，由 `vfox plugin test` 运行）在 **Test Plugin** 工作流里运行。端到端套件在容器里针对真实的 vfox 和真实的 gradle.org 运行，覆盖 Linux 和 Windows，各有 amd64 和 arm64；每个 vfox 渠道（`latest` 和 `main`）都有自己的一次性容器。CI 直接在标准 runner 上运行这套测试（Docker 加 `actions/setup-go` 提供的 Go）。本地则由仓库的开发容器在 Linux 上复现这一环境；Windows 上改用 Docker Compose runner 镜像，因为开发容器无法承载 Windows 容器镜像（见下文）。

下面的章节说明怎样运行这套测试，页末的[套件验证什么](#套件验证什么)列出它检查的全部内容。

## 开发容器

`.devcontainer/` 提供一个 Linux 开发环境，在四种宿主平台上都能用：

| 宿主 | 开发容器的运行方式 |
| --------------------- | ---------------------------------------------- |
| Linux amd64 / arm64 | 原生运行 |
| Windows amd64 / arm64 | Docker Desktop 的 Linux 容器模式（WSL 2） |

它带有 Go 1.27.1（CI 安装的版本）、Docker CLI、stylua、lua-language-server、actionlint、许可证工具，以及运行离线钩子测试的 vfox，版本都与 `.github/workflows/lint.yml`、`license.yml` 和 `test.yml` 里固定的一致，并挂载宿主的 Docker daemon socket。Linux 套件随后通过 testcontainers 连接这个 daemon（Docker-out-of-Docker），启动的目标容器和原生 CI runner 启动的完全相同；这里刻意不用 Docker-in-Docker，这样镜像缓存和网络都还是宿主的。镜像不需要工作区里的文件，所以构建上下文保持在 `.devcontainer/`；`postCreateCommand` 会预热 `tests/e2e` 的 Go 模块缓存，第一次运行测试时就不必停下来下载。

用任何支持 Dev Containers 规范的工具都可以打开它：在 VS Code/Cursor 里执行 **Dev Containers: Reopen in Container**，或者用 CLI：

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
```

`TESTCONTAINERS_RYUK_DISABLED=true` 是预先设好的：Ryuk 会在宿主 daemon 上发布一个端口，并等待套件回连，而 Docker-out-of-Docker 的容器做不到这一点。套件改为通过 `t.Cleanup` 显式终止每个容器；运行被强行中断后遗留的容器，名称都以 `vfox-gradle-e2e-` 开头，可以按这个前缀清理。使用 rootless Docker 的用户，请在打开容器之前先在宿主上 `export DOCKER_SOCK="$XDG_RUNTIME_DIR/docker.sock"`。在 Windows 宿主上，把检出的代码放在 WSL 2 里（例如 `\\wsl$` 下）能让文件和 bind mount 访问保持快速；放在 Windows 文件系统上也能用。

Windows 容器的覆盖（`tests/e2e/windows`）无法在开发容器里运行：Dev Containers 规范不支持 Windows 容器镜像（[vscode-remote-release#445](https://github.com/microsoft/vscode-remote-release/issues/445)），而且 Windows 容器只能跑在 Windows daemon 上。这套测试仍然使用 Windows 宿主上的 Docker Compose runner，见下面的 [Windows 11](#windows-11)。

## 环境变量

| 变量 | 默认值 | 含义 |
| -------------------- | ---------------------------------- | ------------------------------------------------------------------ |
| `VFOX_VERSION` | `latest main` | 用空格分隔的 vfox 渠道（`latest`、`main`） |
| `GRADLE_VERSION` | `9.0.0`（Linux），`9.2.0`（Windows） | 从 services.gradle.org 安装的版本，写法与插件一致 |
| `E2E_MAX_JOBS` | `3`（Linux），`2`（Windows） | 每台宿主并行的容器数 |
| `E2E_RETRY_ATTEMPTS` | `3` | 每个涉及网络的 exec 的尝试次数（线性退避 10 秒） |

Linux 套件还会经由它的镜像替身安装第二个版本 `8.7`，再经由另一个替身安装第三个版本 `1.12`，所以在那里 `GRADLE_VERSION` 不能是这两个版本。`GRADLE_VERSION` 和 `8.7` 要能在镜像自带的 Java 21 上运行（Gradle 8.5 及以后，以及 9.x）；`1.12` 只安装，不运行。Windows 套件把 `9.2.1` 作为第二个版本，也从 services.gradle.org 安装，所以在那里 `GRADLE_VERSION` 不能是它；两者都要能在它的镜像自带的 Java 21 上运行，而在 arm64 上这意味着 9.2.0 或更新（见 [Windows 11](#windows-11)）。你自己 Shell 里的 `VFOX_GRADLE_MIRRORS` 留在宿主上：容器拿到的只是套件给它的环境。

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

## Windows 11

Windows 容器无法跨架构模拟，所以 ARM64 套件需要 ARM64 宿主（Copilot+ PC 或 `windows-11-arm` CI runner）。

这套测试没有开发容器，因为 Dev Containers 规范拒绝 Windows 容器镜像（见[开发容器](#开发容器)），所以它仍使用 Docker Compose runner。runner 镜像（`Dockerfile-runner`：标准的 servercore 加固定版本的 Go，它同时用来构建 vfox `main`）通过挂载的命名管道驱动宿主 daemon；对宿主的要求是 Windows 容器模式的 Docker，加上 Compose v5 插件（每台机器安装一次，见下文）。Go 从不接触宿主，所以不会与 vfox 管理的工具链冲突。

如 vfox-java 所发现的，`windows-11-arm` runner 没有 Windows Hypervisor Platform 功能，所以无法使用 Hyper-V 隔离；进程隔离只需要 Containers 功能。

CI 跳过了 runner 镜像：在 vfox-java 里，在 `windows-11-arm` 上解压它里面的 Go 就花了两分半，而 `actions/setup-go` 已经提供了同样的 Go。CI 直接在 runner 上运行 `go test ./windows`，设置 `E2E_MAX_JOBS=3`。运行之前，`use-local-disk.ps1` 先把 Docker 的数据根目录、Go 的缓存和临时目录，从 runner 上网络挂载的 C: 盘挪到本地磁盘：`windows-latest` 用 D:，`windows-11-arm` 用未格式化的 NVMe 磁盘（脚本会先把它格式化）。镜像层和容器文件是一个个文件写入的，所以在 vfox-java 里，C: 上光拉取 servercore 就花了五分钟。这个脚本只允许在 GitHub Actions 里运行。

镜像（`tests/e2e/windows/Dockerfile`）是标准的 servercore、驱动每次 exec 的 PowerShell 7，以及 Temurin 21，它们都由 `bootstrap-tools.ps1` 从 zip 解压。JDK 要对照 Adoptium 发布的 SHA-256 检查。它是 `jdk-21.0.12.1+1`，2026-11-04 两种架构都有 zip 的最新版本：21.0.13+9 的 x64 zip 已经发布，aarch64 的还没有。镜像里和 Linux 一样没有 Gradle：`gradle` 只能来自 vfox 安装的内容。

套件安装的是 `9.2.0` 和 `9.2.1`，Linux 套件装的是 `9.0.0` 和 `8.7`。Gradle 会加载 native-platform 的一个库，用于控制台、文件系统和 Windows 注册表，而这个库的 Windows on ARM64 构建是随 9.2.0 来的：8.7、9.0.0 和 9.1.0 的 `lib` 目录里没有 `native-platform-windows-aarch64`，9.2.0 的里面有两个（2026-11-04）。Gradle 决定不把它回移到 8.x（[gradle/gradle#35396](https://github.com/gradle/gradle/issues/35396)、[#21703](https://github.com/gradle/gradle/issues/21703)）。所以两个任务都取第一个在两种架构上都能原生运行的版本，以及它的下一个版本。

每个组合运行时，`VFOX_HOME` 都设为带空格的路径（`C:\Users\John Doe\.vfox`），以复现 [vfox-flutter#33](https://github.com/version-fox/vfox-flutter/issues/33)。vfox 从 1.0.13 起支持这样的路径（[vfox#712](https://github.com/version-fox/vfox/pull/712)），所以 `latest` 发布版和 `main` 都在这个路径下运行，发行包也解压在它下面。

2026-11-04，这套测试在 CI 里的第一次运行（[vfox-gradle#7](https://github.com/version-fox/vfox-gradle/pull/7)）中，一个组合在 `windows-latest` 上用了 56 秒和 58 秒（先 `latest`，后 `main`），在 `windows-11-arm` 上用了 90 秒和 86 秒。`go test` 这一步分别用了 3 分 48 秒和 5 分 46 秒，其中包括构建镜像：拉取 servercore 用了 2 分 4 秒和 3 分 10 秒，`bootstrap-tools.ps1` 用了 18 秒和 47 秒。整个任务分别用了 4 分 26 秒和 9 分 9 秒；后者包含 1 分 57 秒用于 Docker 引擎，因为缓存里还没有，`install-docker-arm64.ps1` 从源码构建了它。一个组合的两次安装各下载 136 MB。

同一天对同样的代码重跑了一次（上面多了一个文档提交），`windows-latest` 慢了一些：每个组合 90 秒和 86 秒，`go test` 这一步 5 分 27 秒，整个任务 6 分 22 秒。`windows-11-arm` 差不多，94 秒和 90 秒，`go test` 这一步 6 分 3 秒，但 Docker 引擎 12 秒就从缓存里恢复了，所以整个任务用了 7 分 38 秒。两次运行都没有重试过任何东西。同一份代码在两次运行之间有这么大的差异，估计时要留有余量。

### x64

下面所有命令都在 PowerShell 7 中运行。如果还没有安装，请先装上（这一条引导命令可以在自带的 Windows PowerShell 里运行）：

```powershell
winget install --id Microsoft.PowerShell --source winget --exact
```

1. 在 PowerShell 7 中执行：

```powershell
winget install --id Git.Git --source winget --exact
# 按需配置 Git。

curl.exe -fsSL `
    "https://raw.githubusercontent.com/microsoft/Windows-Containers/Main/helpful_tools/Install-DockerCE/install-docker-ce.ps1" `
    -o ./install-docker-ce.ps1
```

2. 以管理员身份在 PowerShell 7 中执行：

```powershell
./install-docker-ce.ps1
```

3. 在 PowerShell 7 中执行：

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.docker\cli-plugins" | Out-Null

curl.exe -fsSL `
    "https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-windows-x86_64.exe" `
    -o "$env:USERPROFILE\.docker\cli-plugins\docker-compose.exe"

git clone git@github.com:version-fox/vfox-gradle.git
cd ./vfox-gradle/
docker compose -f tests/e2e/windows/compose.amd64.yaml run --rm --build e2e
```

### arm64

下面所有命令都在 PowerShell 7 中运行。如果还没有安装，请先装上（这一条引导命令可以在自带的 Windows PowerShell 里运行）：

```powershell
winget install --id Microsoft.PowerShell --source winget --exact
```

1. 在 PowerShell 7 中执行：

```powershell
winget install --id Git.Git --source winget --exact
# 按需配置 Git。
winget install --id GoLang.Go --source winget --exact
git clone git@github.com:version-fox/vfox-gradle.git
cd ./vfox-gradle/
pwsh -NoProfile -File .\tests\e2e\windows\install-docker-arm64.ps1
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.docker\cli-plugins" | Out-Null

curl.exe -fsSL `
    "https://github.com/docker/compose/releases/download/v5.5.1/docker-compose-windows-aarch64.exe" `
    -o "$env:USERPROFILE\.docker\cli-plugins\docker-compose.exe"

docker compose -f tests/e2e/windows/compose.arm64.yaml run --rm --build e2e
```

在 arm64 上，构建 Docker 引擎也要用 Go，所以 `install-docker-arm64.ps1` 要在套件之前运行；之后 compose runner 镜像自带固定版本的 Go 来跑测试，宿主上的 Go 不会再被用到。这个脚本会复用它之前构建过的、版本符合的引擎；CI 从以这个脚本为键的缓存里恢复一个。想缩小运行范围，在 compose 命令前加上 `$env:VFOX_VERSION = 'latest'`，和其他平台一样。

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
addlicense -check -f .license.tpl tests/e2e/windows/*.ps1
addlicense -f .license.tpl tests/e2e/windows/*.ps1
```

在只有 Docker 的宿主上，许可证检查和工作流检查改用容器运行（和 CI 用的镜像相同）：

```bash
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header check
docker run --rm -v "$PWD:/work" -w /work apache/skywalking-eyes:0.9.0 header fix
docker run --rm -v "$PWD:/src" ghcr.io/google/addlicense:v1.2.0 -check -f .license.tpl tests/e2e/windows/*.ps1
docker run --rm -v "$PWD:/src" ghcr.io/google/addlicense:v1.2.0 -f .license.tpl tests/e2e/windows/*.ps1
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
```

license-eye 也检查 PowerShell 文件，但无法修复它们，所以 `addlicense` 负责写入它们的头，并在 CI 里检查（原因见 `.licenserc.yaml`）。Windows 套件由和 Linux 套件相同的 Go 检查在任何宿主上编译和 vet；只有运行它才需要 Windows 宿主。

## 套件验证什么

在 Linux 上，每个组合运行同一套流程（每个 vfox 渠道一个长期运行的容器，由 Go 通过类似 `docker exec` 的调用来驱动）。目标镜像带着 Ubuntu 的一个 JDK，因为 Gradle 需要它，但不带 Gradle：`gradle` 只能来自 vfox 安装的内容。[在 Windows 上](#在-windows-上)，流程在可能的地方与此相同。

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

### 在 Windows 上

Windows 套件运行第 1 到 5 条、第 7、8 和 10 条，并有下面这些不同；第 6、9 和 11 条需要镜像替身，所以不在其中（见[套件没有覆盖什么](#套件没有覆盖什么)）。在它们之前，套件先检查镜像里的 `JAVA_HOME` 是一个 JDK 21，所用的命令都是 PowerShell 7 的。

- **第 1 条。** `latest` 是最新发布版的 Windows zip，`vfox_<版本>_windows_x86_64.zip` 或 `vfox_<版本>_windows_aarch64.zip`。`main` 在构建镜像的同时由 runner 用它自己的 Go 构建，再作为 `vfox.exe` 叠加到镜像上：在每个容器里构建，就得先在里面装 Go。插件用 Windows 自带的 `tar -a -cf` 打包，再由 `vfox add gradle --source` 注册。
- **第 7 条和第 10 条。** 固定的版本是 `9.2.0`，第二个版本是 `9.2.1`，都从 services.gradle.org 安装，Linux 上的 8.7 则是经由替身安装的。vfox 校验所用的摘要必须是 Gradle 为每个版本发布的那个。
- **第 8 条。** 在 Windows 上，全局的 `vfox use` 还会把变量写入账户的注册表（`HKCU\Environment`，vfox 1.0.13，`internal/env/registry_windows.go`），这在一次性容器里没有害处，在你自己的机器上就有，所以套件只在容器里运行它。新的 Shell 是 `vfox activate pwsh` 设置的那个，再加上 `vfox env` 的导出。`GRADLE_HOME` 是用户配置目录（套件给每个容器的 slot，所以路径里没有空格）下 `.vfox\sdks` 里的一个链接，是 vfox 用 PowerShell 的 `New-Item -ItemType Junction` 创建的联接点（junction）（vfox 1.0.13，`internal/shared/util/file.go`），它必须解析到 vfox 主目录（带空格的那个）里的 `cache\gradle\v-9.2.0\gradle-9.2.0`。PowerShell 找到的 `gradle` 必须是这个链接里的 `bin\gradle.bat`。钩子把 `/bin` 加在链接的路径后面，所以 `PATH` 里的这一项可能在反斜杠中间夹着一个斜杠。`EnvKeys` 的离线测试默认 Windows 会把这个斜杠当作分隔符；Windows 套件是检查这一点的地方。

矩阵是两个 vfox 渠道，`latest` 和 `main`，在 runner 具备的每种架构上运行。Linux 套件固定的版本是 `9.0.0`（Gradle 从 9.0.0 起带第三位）、`8.7`（8.x 之前不带）和很小的 `1.12`；Windows 套件固定的是 `9.2.0` 和 `9.2.1`（见 [Windows 11](#windows-11)）。旧版本一直可以下载，所以这些固定值不会过时。

## 套件没有覆盖什么

- **macOS。** 没有对应的任务。插件本身没有针对任何系统的代码，发行包也是同一个 zip，但 CI 里没有任何东西证明它在 macOS 上能用。
- **Windows 上的镜像替身。** 第 6、9 和 11 条只在 Linux 上运行。它们针对一个镜像运行插件的 Lua，而这段 Lua 没有针对任何系统的代码。在 Windows 容器里启动替身，需要一个比启动它的 `docker exec` 活得更久的进程，套件还没有这么做过。
- **真实的镜像。** 镜像来来去去，所以套件使用自己的替身。手工检查过的镜像见 [mirror.md](mirror.md#检查过的镜像)。
- **代理**，以及 `vfox use` 除 `--global` 之外的作用域。
