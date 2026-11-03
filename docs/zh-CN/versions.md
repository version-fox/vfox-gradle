# 版本与命名

[中文](versions.md) | [English](../versions.md)

## 怎样写版本

版本就是 `vfox search gradle` 里列出的 Gradle 版本名。插件把它原样放进文件名 `gradle-<版本>-bin.zip` 去下载，所以不是版本的名字，下载时会得到 404：

| 你写的 | 结果 |
| --- | --- |
| `gradle@8.7` | 安装 8.7 |
| `gradle@8.14.3` | 安装 8.14.3 |
| `gradle@9.0.0` | 安装 9.0.0 |
| `gradle@v8.7` | vfox 去掉 `v`，安装 8.7 |
| `gradle@latest` | vfox 取 `vfox search gradle` 列出的第一个版本，也就是最新的：2026-11-03 是 9.8.2 |
| `gradle@8` | `source file not found`：没有叫 8 的版本 |
| `gradle@8.7.0` | `source file not found`：这个版本叫 8.7 |
| `gradle@` | `install requires specifying a version for gradle` |

Gradle 在 8.x 之前把每个系列的第一个版本写成没有第三位的形式（`8.14`、`8.7`、`7.6`），从 9.0.0 起才带上（`9.0.0`、`9.1.0`）。`8.14` 和 `8.14.3` 都是版本，`8.14.0` 却不是。请从列表里抄版本名。

## 搜索

```bash
vfox search gradle
```

```text
Available versions:
 - 9.8.2
 - 9.8.1
 - 9.8.0
 ...
```

插件读取的是页面 [gradle.org/releases](https://gradle.org/releases/)，它列有 174 个版本，从 0.7 到 9.8.2（2026-11-03）。页面按日期排列，所以 8.14.6 排在 9.8.2 和 9.8.1 之间，插件会按版本号把它们从新到旧重新排序。缺少的位数按 0 算：8.14 和 8.14.0 视为相等。第一项就是 `latest` 的含义。

已安装的版本会标上 `(installed)`。在交互式终端里，搜索结果可以直接选一个并安装。vfox 会把结果缓存 12 小时，所以 gradle.org 一分钟前才列出的版本可能还看不到：`vfox config cache.availableHookDuration 0` 可以关闭缓存。搜索不经过[镜像](mirror.md)：版本列表永远来自 gradle.org。

## 候选版本

页面上只列正式版本。候选版本（RC）不会出现在搜索里，也永远不是 `latest`，但只要 Gradle 还提供下载，就可以按名字安装：

```bash
vfox install gradle@9.0.0-rc-1
```

这个版本在 2026-11-03 装上了，并且和其他版本一样通过了校验和检查。快照和每夜构建装不上：Gradle 把它们放在 `distributions-snapshots` 下，而插件只认 `distributions`。

## 只有二进制发行包

插件安装的是 `gradle-<版本>-bin.zip`，也就是版本页上标着 “binary-only” 的二进制发行包；旁边还有一个带文档和源码的 “complete” 版本，插件不提供。

## 安装后的名字

安装后的名字就是版本号：`vfox install gradle@latest` 装出来的是 9.8.2，名字是 `9.8.2`，不是 `latest`。`vfox list gradle` 列出这些名字，每个版本一行 `->`，按文本顺序而不是数字顺序排列（`8.7` 排在 `8.14` 前面）。

`vfox uninstall` 必须写全名字。和 `vfox use` 不同，它不接受版本的开头：装着 8.7 时，`vfox uninstall gradle@8` 得到的是 `gradle@8 is not installed`。

## `vfox use` 会选中什么

```bash
vfox use gradle@8.7              # 当前 Shell
vfox use --project gradle@8.7    # 当前目录
vfox use --global gradle@8.7     # 之后新开的所有 Shell
```

和安装不同，`vfox use` 接受版本的开头，并在已安装的版本里查找。装着 8.7、8.14、8.14.3 和 9.0.0 时（用 vfox 1.0.13 检查过），`vfox use gradle@8` 选中 8.14.3，也就是最新的 8.x；`gradle@8.14` 选中 8.14 而不是 8.14.3；`gradle@8.1` 什么也找不到，因为它不是它们任何一个版本号的开头。这是 vfox 自己的匹配规则，插件的 `PreUse` 钩子什么也不做。
