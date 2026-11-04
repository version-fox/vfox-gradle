# 开发

[中文](development.md) | [English](../development.md)

## 目录结构

```text
metadata.lua                    插件名、版本和提示
hooks/available.lua             vfox search：gradle.org/releases 上的版本
hooks/pre_install.lua           vfox install：zip（或镜像）的地址、它的 SHA-256 和 User-Agent
hooks/env_keys.lua              GRADLE_HOME 和 PATH
hooks/pre_use.lua               什么也不做，由 vfox 把输入的内容和已安装的版本匹配
hooks/post_install.lua          什么也不做
lib/util.lua                    两个地址、版本比较和下载用的请求头
tests/*_test.lua                离线的钩子测试，由 vfox plugin test 运行
tests/fixtures/releases.html    gradle.org/releases 的一份节选，Available 的测试会读取它
tests/e2e/                      容器测试，见 e2e.md
Injection.lua                   vfox 注入内容的类型提示，从不加载
README.md, docs/                文档；README_CN.md 和 docs/zh-CN/ 是中文版
.devcontainer/                  Linux 开发容器，见 e2e.md
.github/workflows/              test、lint、license、e2e 和 publish
opencode.jsonc                  让 OpenCode 代理会话在本仓库里不经询问就能执行 git push、gh pr create 和 gh pr comment
```

vfox 加载 `metadata.lua`，命令需要时调用相应的钩子，并向钩子提供全局变量 `PLUGIN` 和 `RUNTIME`（`osType`、`archType`、`version`）以及模块 `http` 和 `json`。`osType` 和 `archType` 就是 vfox 二进制的 Go `GOOS` 和 `GOARCH`。`lib/util.lua` 用 `require("util")` 加载。

## 一条命令会调用什么

| 你执行 | 调用的钩子 |
| --- | --- |
| `vfox search gradle` | `Available` |
| `vfox install gradle@8.7` | `PreInstall` 返回地址、摘要和 User-Agent。vfox 下载、校验并解压，然后调用 `PostInstall` |
| `vfox install gradle@latest` | vfox 调用 `Available`，取它的第一项，然后同上 |
| `vfox use gradle@8.7` | `PreUse` 什么也不返回，由 vfox 把名字和已安装的版本匹配。`EnvKeys` 提供变量 |
| `vfox uninstall gradle@8.7` | 无，名字必须写全 |

几个花了不少时间才弄清楚的约定：

- `PreInstall` 返回 `version`、`url`、`sha256` 和 `headers`。`version` 是安装后的名字，钩子按输入原样返回它。摘要那个键的名字就是算法，vfox 用这个算法对下载的文件求哈希，再把十六进制摘要和拿到的文本原样比较：小写，前后什么也没有，否则无论下载的内容如何，安装都会因 `Checksum error` 失败。所以钩子要从读到的文件里把摘要取出来（镜像可能是按 `sha256sum` 的格式写的），并转成小写。
- 下载是 vfox 自己发起的，除非 `headers` 另有说明，否则自称 `Go-http-client/1.1`。拒绝 Go 默认名字、回应 403 和一段 HTML 的镜像（华为云的就是，2026-11-03），那段页面会被当作 zip 保存下来，安装以 `Checksum error` 结束。钩子在 `headers` 里设置了 `User-Agent`，用的是 vfox 为钩子发出的请求使用的字符串（`util:download_headers()`）。
- 没有摘要时 vfox 只是警告（`Checksum is not provided`），然后继续下载，而且它只会拿钩子给它的摘要去校验下载。所以镜像对 `.sha256` 回应 404（没有这类文件的镜像就是这样）时，钩子会向 services.gradle.org 要同一个版本的摘要，vfox 再用它校验镜像上的 zip。腾讯云的镜像没有 8.7 和 9.8.2 的 `.sha256`，用 0.1.1 版装它们都以那条警告收场。只有这一步也落空时，钩子才不给摘要：被问的服务器是镜像，而需要镜像的网络可能挡住了 services.gradle.org，这不是停下安装的理由。对镜像本身，钩子在 200 和 404 以外的状态码、以及没有摘要的 200 时报错，并且不会改去问 services.gradle.org。0.1.1 版对这些状态码什么也不返回，vfox 就只打印 `no installable runtime provided`。
- `latest` 不由插件处理：vfox 核心取 `Available` 的第一项（`Using latest version: 9.8.2`），所以 `lib/util.lua` 给列表排的顺序，就是 `latest` 的含义。vfox 把 `Available` 的结果缓存 12 小时（`vfox config cache.availableHookDuration`）。
- `PreUse` 什么也不返回，由 vfox 自己把输入的内容和已安装的版本匹配，按版本号的开头匹配：`gradle@8` 选中已安装的最新 8.x，`gradle@8.1` 选不中 8.14。
- `EnvKeys` 拿到的 `ctx.path` 是链接 `~/.vfox/sdks/gradle`，vfox 一直让它指向正在使用的版本，所以无论选中哪个版本，`GRADLE_HOME` 的值都一样。它设置 `GRADLE_HOME` 和 `PATH`，没有 `JAVA_HOME` 之类的东西。
- zip 里只有一个目录 `gradle-<版本>`，vfox 自己能找到它：`PostInstall` 无事可做。`bin/gradle` 的可执行权限在解压后依然保留。
- vfox 会在钩子看到用户输入之前，去掉开头的 `v`。

## 镜像

`VFOX_GRADLE_MIRRORS` 在 `PreInstall` 里用 `os.getenv` 读取，值末尾的斜杠会被去掉。没有设置时，地址是 `util.DownloadInfoUrl`。校验和从同一个地址加 `.sha256` 读取，镜像回应 404 时，钩子会再向 `util.DownloadInfoUrl` 要一次，所以镜像可以只提供 zip。`Available` 从不使用镜像。[mirror.md](mirror.md) 是从用户角度写的说明。

## 测试

钩子测试在 `vfox plugin test` 下离线运行，vfox 1.0.13 及更高版本才有这个命令。它会找出每个 `tests/**/*_test.lua`，每个文件在各自的虚拟机里运行，所以新增测试文件不需要在任何地方登记：

```bash
vfox plugin test .
vfox plugin test . --file tests/pre_install_test.lua
```

请在仓库根目录运行。Test Plugin 工作流安装的是 `.github/workflows/test.yml` 里固定的版本，开发容器带的也是同一个。

测试文件只调用一次 `vfox.test` 的 `test.load()`，并通过它返回的对象调用真正的钩子，比如 `plugin:PreInstall({ version = "8.7" })`。`test.load` 接受平台（`os`、`arch`）、环境变量（`env`）和一个回答所有 HTTP 请求的函数（`http`）。之后就可以 require `lib` 里的模块。见 vfox 的[测试和调试插件](https://vfox.dev/zh-hans/plugins/create/testing.html)。钩子的上下文和返回值都会经过 vfox 的解码，所以在 vfox 要求返回 table 的地方返回了字符串的钩子，会让测试失败。

- `available_test.lua` 读取 `tests/fixtures/releases.html`，检查得到的列表：每个版本都在，尽管页面按日期排列，结果仍从新到旧；只向 gradle.org 发一次请求；状态码不是 200 或者请求失败时，报同一条错误。
- `pre_install_test.lua` 用一张按地址索引的表来回答校验和请求，并按顺序断言钩子请求了哪些地址。它覆盖有镜像和没有镜像时的地址、User-Agent、摘要文件的各种写法，以及请求的每一种结果：200、404、其他状态码和网络失败。对镜像的 404，它还覆盖 services.gradle.org 随后可能给出的各种回应，以及镜像的其他失败不会走到这一步。
- `env_keys_test.lua` 和 `util_test.lua` 覆盖 `EnvKeys` 和版本比较。

测试看不到所在机器的环境：`os.getenv` 对 `VFOX_GRADLE_MIRRORS` 的回答来自 `pre_install_test.lua` 里的一张表，它为每个用例设置镜像，所以你自己 Shell 里的镜像不会影响测试。gopher-lua 1.1.1 会丢失被闭包在 `pcall` 之后赋值的 `local x = nil`：外层作用域读到的仍是 `nil`。这就是 HTTP 函数读取的状态保存在表字段里的原因。

想用真实的服务器调用某一个钩子，vfox 1.0.13 及更高版本有 `vfox plugin run`。它不会注册插件，`--os` 和 `--arch` 可以代表另一个平台，`--offline` 会拒绝 HTTP，`VFOX_GRADLE_MIRRORS` 同样生效，所以如果你的 Shell 里设置了它，请先取消设置：

```bash
vfox plugin run . Available --json
vfox plugin run . PreInstall --input '{"version":"8.7"}' --json
vfox plugin run . EnvKeys --input '{"path":"C:\\vfox\\gradle-8.7"}' --os windows --arch amd64 --json
```

`vfox --debug <命令>` 会显示 vfox 对钩子做了什么，被它吞掉的错误就靠这个找出来。

容器测试、lint 和许可证头见 [e2e.md](e2e.md#本地检查)。Lua 用 StyLua 格式化（`stylua.toml`：4 个空格，120 列），用 LuaLS 在 `Warning` 级别检查（`.luarc.json` 声明了 `PLUGIN` 和 `RUNTIME`），工作流用 actionlint 检查。源文件（Lua、Go、YAML、TOML、PowerShell 和 Dockerfile）带许可证头，Markdown 和 JSON 不带。

## 更新夹具

`tests/fixtures/releases.html` 是在线页面中几个区块的副本，见[它的 README](../../tests/fixtures/README.md)。gradle.org 改了页面的标记之后，容器测试里的 `vfox search gradle` 会最先失败，因为它读的是真实页面。请把这些区块换成新页面的区块，并同时修改 `Available` 和测试。

## 已知的缺口

- `Available` 读取的是 gradle.org/releases 的 HTML，也就是每个版本开头的 `<a name="…"></a>` 锚点。如果标记变了，钩子会返回空列表，vfox 会把它缓存 12 小时，`latest` 也找不到任何东西。`https://services.gradle.org/versions/all` 是一份 JSON 列表，2026-11-03 有 534 项（正式版本、候选版本、快照和每夜构建，带有 `version`、`snapshot`、`nightly`、`rcFor`、`downloadUrl` 和 `checksumUrl`），不依赖页面标记，也能列出候选版本。
- 只安装 binary-only 发行包（`-bin`），不安装 complete 版本（`-all`）。快照和每夜构建由 Gradle 放在 `distributions-snapshots` 下，装不上。
- 有 `.sha256` 的镜像，摘要和 zip 来自同一台服务器，所以它防的是下载损坏，防不住镜像同时提供一对互相吻合的文件。没有 `.sha256` 的镜像则由 services.gradle.org 的摘要来约束，更严格。镜像有 `.sha256` 时不会去问 services.gradle.org：先问它，就会让每个镜像都受它约束，也会让那些因为它太慢或被挡住才用镜像的网络依赖它。
- 下载的回应只要不是 404，vfox 就把回应的内容当作压缩包保存下来，比如 403 的页面，然后报告 `Checksum error`（[vfox#746](https://github.com/version-fox/vfox/issues/746)）。这是 vfox 的问题，不是插件的；上面的 `User-Agent` 让插件避开了遇到过的那一种情形。
- 容器测试覆盖 Linux 和 Windows 容器，包括 amd64 和 arm64。macOS 没有对应的任务，Windows 套件也没有包含用到镜像替身的检查，见 [e2e.md](e2e.md#套件没有覆盖什么)。

## 发布

维护者在默认分支上从 **Actions → Plugin → Run workflow** 发布，输入不带 `v` 前缀的稳定版插件版本号。共用的工作流 [plugin-manifest-action](https://github.com/version-fox/plugin-manifest-action) 会更新 `metadata.lua`，创建版本提交和标签，并在本仓库发布 ZIP 和清单。不需要本地打标签，也不需要额外的发布令牌。拉取请求只运行检查，PR 标题不再触发发布。

推送版本标签同样会发布，前提是 `PLUGIN.version` 已经与标签一致。如果发布失败，重新运行最初失败的那个作业即可继续。工作流跟随共用的 `@v1` 发布工具，更新这个工具不会发布本插件。共用工作流的文档里有包的约定和首次启用的要求。之后，[vfox-plugins](https://github.com/version-fox/vfox-plugins) 里的 `plugins/gradle.json` 会显示 `vfox add gradle` 提供的版本。

### 发布之后

`main` 比最新发布版更新期间，文档用“未发布”（英文是“Unreleased”）标记新的内容：条目放在 [changes.md](changes.md) 顶部的“未发布”标题下；描述新行为的页面加一条以“未发布：X.Y.Z 版”开头的说明，写明最新发布版的行为；README 里有一段解释这个标记，并指向 [changes.md](changes.md) 和 [install-from-source.md](install-from-source.md)。发布之后，把 [changes.md](changes.md) 里的条目移到新版本下面，写上发布日期，并把这些说明和 README 里的那一段去掉，两种语言都要处理：`grep -rn -i -e unreleased -e 未发布 docs README*`（本节里的命中要保留）。还要搜索上一个发布版的版本号：有几句话拿它做了对比，却没有写“未发布”，有的连版本号也没写（“在这之前”“以前”），还有几处指向即将删掉的说明，比如“见上文”。

## 编写文档

英文页面在 `docs/`，中文页面在 `docs/zh-CN/`，文件名相同（中文 README 是 `README_CN.md`），每个页面开头都有指向另一种语言的链接。新页面要加进两个 README 的文档列表。引用数据的页面会写明取数据的日期（镜像列表、版本数量、一次下载的重定向），没有任何东西会检查它们。CI 不检查 Markdown，所以你加的命令都要自己运行，页面里的输出就是它们打印的内容。插件的改动让某个页面不再正确时，在同一个拉取请求里同时修改这个页面和它的译文。中文页面里指向 `page.md#标题` 的链接用的是中文页面的标题，它的地址和英文页面的不一样。
