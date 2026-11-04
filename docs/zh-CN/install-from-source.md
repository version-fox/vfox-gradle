# 从源码安装

[中文](install-from-source.md) | [English](../install-from-source.md)

`vfox add gradle` 安装的是最新发布版。想在下一个版本发布之前试用 `main`，或者试用你正在改的内容，可以从源码构建插件。插件就是 `metadata.lua` 加上 `hooks` 和 `lib` 两个目录，vfox 可以从它们打成的 zip 添加插件。

## Ubuntu 26.04

在 Bash 中执行：

```bash
sudo apt install --assume-yes git zip
git clone --depth 1 https://github.com/version-fox/vfox-gradle.git
cd ./vfox-gradle/
zip -qr ./gradle.zip metadata.lua hooks lib
vfox add gradle --source ./gradle.zip
rm ./gradle.zip
```

macOS 的做法相同，用系统自带的 `git` 和 `zip` 即可。

## Windows 11

假设已经装好了 PowerShell 7。在 PowerShell 7 中执行：

```powershell
winget install --id Git.Git --source winget --exact
git clone --depth 1 https://github.com/version-fox/vfox-gradle.git
cd ./vfox-gradle/
tar -a -cf ./gradle.zip metadata.lua hooks lib
vfox add gradle --source ./gradle.zip
Remove-Item ./gradle.zip
```

## 验证

```bash
vfox install gradle@8.7
vfox use --global gradle@8.7
gradle --version
```

`gradle --version` 需要 JDK，见 README 里的 [Java](../../README_CN.md#java)。`vfox info gradle` 打印的是 `metadata.lua` 里的版本号，在下一个版本发布之前，它一直是上一个发布版的版本号。

## 已经添加过 gradle 时

`vfox add` 会拒绝，提示 `plugin named gradle already exists`。你可以替换这个插件，也可以把源码构建的版本和它并排添加。

要替换，先执行 `vfox remove gradle`，它会把通过这个插件装上的各个版本一并删掉：vfox 会在询问之前先告诉你（`-y` 可以跳过询问）。之后再重新安装它们。

要两个都留着，给新的起一个别的名字：

```bash
vfox add gradle --source ./gradle.zip --alias gradle-dev
vfox install gradle-dev@8.7
vfox remove -y gradle-dev            # 只删除 gradle-dev 和它装的内容
```

别名有自己的已安装版本列表，`vfox list` 会把两者分开显示，但 `GRADLE_HOME` 指向的链接 `~/.vfox/sdks/gradle` 对两者是同一个：vfox 把它指向你最后选中的那个版本，不管它来自哪个插件。同一个作用域里，只从其中一个选版本。

## 更新

拉取代码，重新打包 zip，再添加一次。用本名添加的插件必须先删除，而删除会连同已安装的版本一起带走，所以经常更新时，用别名更省事：

```bash
vfox remove -y gradle-dev
vfox add gradle --source ./gradle.zip --alias gradle-dev
```

`vfox update gradle` 会拿 `metadata.lua` 里的版本号和注册表里的比较，两者相等时只打印 `gradle is already the latest version`，所以在发布一个比它更新的版本之前，它不会去动源码构建的插件。

要参与插件的开发，见 [development.md](development.md)。
