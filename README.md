# 右键助手 (RightKit)

给 Finder 右键菜单加上顺手的几件事。装完即用，没有需要配置的东西。

**[下载最新 DMG 安装包](https://github.com/zzzgr/right-kit/releases/latest)**

支持 macOS 13 及以上版本，同时支持 Apple 芯片和 Intel Mac。

```
右键任意文件 / 文件夹  →  右键助手 ▸  在 Ghostty 中打开
                                    在 Cursor 中打开
                                    新建文件
                                    新建文件夹
                                    复制路径
```

## 安装

1. 从 Releases 下载 `.dmg` 文件，打开后将 `RightKit` 拖进「应用程序」。
2. 从「应用程序」打开 RightKit，按向导启用 Finder 扩展。
3. 在 Finder 中右键文件或文件夹，选择「右键助手」。

当前发布的安装包已包含应用签名，无需自行签名、编译或安装 Xcode，但尚未经过
Apple 公证。如果 macOS 阻止首次打开，请前往「系统设置 → 隐私与安全性」，
找到 RightKit 并点击「仍要打开」。

请从「应用程序」运行，不要直接从 DMG 中运行。安装包及校验文件见 Releases。

## 产品原则

**一、零权限**
除了 macOS 强制要求的「启用 Finder 扩展」开关，不需要任何授权。终端通过
LaunchServices 打开（Terminal / iTerm2 / Ghostty 都把文件夹当作可打开的文档），
因此**不需要「自动化」权限**，不用 AppleScript，也没有「允许控制 Terminal」这一步。

**二、设置向导会验证，而不是假设**
`FIFinderSyncController.isExtensionEnabled` 只反映系统开关，不代表真的能用。所以
扩展每次被 Finder 加载、每次构建菜单，都会往 App Group 里留下时间戳；主 App 读到它，
才把最后一步打勾。这一个时间戳同时证明三件事：扩展活着、菜单真的弹出过、两个进程的
App Group 确实是通的。

**三、只显示还没做完的事**
做完的步骤收成一行 ✓，说明文字和按钮一起消失；App 已经在「应用程序」里时，
安装位置那一步根本不出现。没有硬门槛——检测可能出错，把用户关在一个走不出去的
窗口里，比在菜单栏留个警告更糟。

**四、成功安静，失败有声**
成功没有任何提示（终端窗口、新建的文件、剪贴板本身就是反馈）。失败弹一条通知，
说清原因；能修的（比如 macOS 拦了文件访问）点通知直接跳到对应的隐私设置面板。

**五、菜单里只有能用的东西**
没装编辑器，就没有「在编辑器中打开」这一项——不做灰掉的占位。菜单项名字会写明
真正会打开哪个 App（「在 Ghostty 中打开」），图标就是那个 App 的图标。

## 界面

只有三处，全部列在这里：

| 界面 | 出现时机 |
|------|---------|
| 设置向导 | 首次启动；之后从菜单栏警告或设置里重开 |
| 设置窗口 | 用户主动打开（⌘,） |
| 菜单栏下拉 | 常驻：设置… / 退出；扩展被关掉时多一行 ⚠ |

设置窗口是一整屏、没有 Tab：每一行就是一个菜单项，右边紧跟着它会打开哪个 App。

## 支持的 App

| | |
|---|---|
| 终端 | Terminal · iTerm2 · Ghostty |
| 编辑器 | VS Code（含 Insiders）· Cursor · Zed · Sublime Text |

「自动」= 按上表顺序取第一个装了的。选中的 App 被卸载后自动回落到「自动」。
加一个 App 只需要在 `LaunchApps.swift` 里加一个 case。

## 开发

需要 macOS 13+、完整 Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
./Scripts/generate-project.sh     # project.yml → RightKit.xcodeproj（后者不入库）
open RightKit.xcodeproj           # scheme RightKit，先在 Signing 里选 Team

cd Packages/RightKitShared && swift test   # 域层单测，不需要 Xcode
```

**要真正试用，别用 ⌘R**：从 DerivedData（或磁盘映像）运行的 Finder 扩展会把自己
注册到一个随时会消失的路径上，pluginkit 之后可能一直返回那个旧副本。

```bash
./Scripts/install-local.sh        # 构建 → 签名 → 装进 /Applications → 打开
```

然后在「系统设置 → 通用 → 登录项与扩展 → Finder 扩展」里勾上「右键助手」。

签名是**构建后**再做的（`Scripts/sign-app.sh`）：让 Xcode 在构建时签名会因为 App Group
entitlement 而要求 provisioning profile，进而要求 Xcode 里登录 Apple 账号；对着已构建
好的 bundle 签名只需要钥匙串里有证书。用 `Apple Development` 证书就够本机测试。

## 分发

```bash
./Scripts/release.sh              # Developer ID 签名 + 公证 + staple（app 与 dmg 都要）
```

产物 `dist/RightKit-<版本>.dmg`：别人下载后双击、拖进「应用程序」即可，没有 Gatekeeper 警告。

若使用 Apple Development 证书，可以构建未公证的安装包：

```bash
LOCAL=1 ./Scripts/release.sh      # dist/RightKit-<版本>-dev.dmg
```

接收者无需自行签名，但首次打开可能需要按上面的安装说明，在系统设置中确认。
要避免这一步，必须使用 Developer ID 签名并完成 Apple 公证。
不能改用 ad-hoc 签名，因为没有 TeamIdentifier 的签名会让 pluginkit 拒绝注册 Finder 扩展。

## 结构

```
Apps/RightKit/                  菜单栏 App：设置向导 / 设置窗口 / 执行 handoff
Extensions/RightKitFinderSync/  Finder 扩展：只管建菜单，其余交给主 App
Packages/RightKitShared/        域层（动作、偏好、心跳、文案）+ 单测
Scripts/                        工程生成 / 图标 / 本地安装 / 发布
Design/                         图标源文件（generate-icons.py 的输入）
project.yml                     target、签名、版本号的唯一来源
```

架构细节与踩过的坑见 [CLAUDE.md](CLAUDE.md)。

## 排查

右键菜单没出现：

```bash
pluginkit -mAvvv -p com.apple.FinderSync | grep -A2 rightkit   # Path 应指向 /Applications
```

如果 `Path` 指向 `/Volumes/…` 或 DerivedData，就是注册到了旧副本：
删掉那个副本，跑 `./Scripts/install-local.sh`，再在系统设置里重新勾一次。
