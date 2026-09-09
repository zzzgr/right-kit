# 右键助手 (RightKit)

给 Finder 右键菜单加上顺手的几件事。内置动作装完即用，也可以把自己的 Python / Shell 脚本放进右键菜单。

**[下载最新 DMG 安装包](https://github.com/zzzgr/right-kit/releases/latest)**

支持 macOS 13 及以上版本，同时支持 Apple 芯片和 Intel Mac。

```
右键任意文件 / 文件夹  →  右键助手 ▸  在 Ghostty 中打开
                                    在 Cursor 中打开
                                    新建文件
                                    新建文件夹
                                    复制路径
                                    你的自定义动作
```

从菜单栏打开「设置…」，在「自定义动作」旁点击「打开…」，新建空白动作，设置名称、图标、分组、显示条件和脚本，
选择测试文件查看真实输出，确认后保存到 Finder。支持 Python 虚拟环境、外部脚本、环境变量和钥匙串密钥。
完整用法见 [自定义动作指南](Docs/CustomActions.md)。
源码中的 1.2.0 已接入动作市场：从网页打开动作，检查说明、源码和升级日志，再导入为草稿；
也可以订阅市场、检查更新和复制动作包。使用与联调见 [市场与导入指南](Docs/MarketIntegration.md)。

## 安装

1. 从 Releases 下载 `.dmg` 文件，打开后将 `RightKit` 拖进「应用程序」。
2. 从「应用程序」打开 RightKit，按向导启用 Finder 扩展。
3. 在 Finder 中右键文件或文件夹，选择「右键助手」。

当前发布的安装包已包含应用签名，无需自行签名、编译或安装 Xcode，但尚未经过
Apple 公证。如果 macOS 阻止首次打开，请前往「系统设置 → 隐私与安全性」，
找到 RightKit 并点击「仍要打开」。

请从「应用程序」运行，不要直接从 DMG 中运行。安装包及校验文件见 Releases。

## 产品原则

**一、不预先索取权限**
内置功能除了 macOS 强制要求的「启用 Finder 扩展」开关，不要求额外授权步骤。终端通过
LaunchServices 打开（Terminal / iTerm2 / Ghostty 都把文件夹当作可打开的文档），
因此**不需要「自动化」权限**，不用 AppleScript，也没有「允许控制 Terminal」这一步。
自定义脚本访问受系统保护的目录或其他资源时，仍受 macOS 权限约束；仅明确运行含密钥的动作时读取钥匙串。

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

主要界面：

| 界面 | 出现时机 |
|------|---------|
| 设置向导 | 首次启动；之后从菜单栏警告或设置里重开 |
| 设置窗口 | 用户主动打开（⌘,） |
| 自定义动作窗口 | 从设置打开；编辑、测试脚本、浏览市场、检查更新；运行记录位于手动测试中 |
| 菜单栏下拉 | 设置… / 退出；扩展关闭时显示 ⚠ |

设置窗口是一整屏、没有 Tab：每一行就是一个菜单项，右边紧跟着它会打开哪个 App。
自定义动作使用独立的可缩放窗口，最小内容尺寸为 960 × 650，顶部居中的 Tab 切换「我的动作」和「动作市场」。「我的动作」左侧管理菜单项，右侧显示所选动作的设置、脚本和手动测试；未选择动作时右侧留空。左侧底部依次放置新建 / 复制 / 删除、单行分页和菜单排序。
切换到「动作市场」会展示完整宽度的市场列表，可以搜索动作、刷新和筛选可更新版本，点击动作在弹窗中查看详情。在右上角「市场设置」中配置一个市场地址，支持 HTTP 和 HTTPS，包括局域网地址。更换地址会先验证，成功后替换当前市场。导入先进入草稿，保存后才进入 Finder 菜单。
设置窗口提供跟随系统、明亮和黑暗三种外观，控件使用原生蓝色强调色；我的动作列表底部通过「菜单排序」调整动作顺序，也可使用 ⌘⌥↑ / ⌘⌥↓。
动作图标保留原色，市场和编辑控件采用紧凑尺寸。动作详情及升级日志可直接阅读 Markdown 标题、列表、代码块和参数表格。
市场和我的动作默认每页 20 条，可通过紧凑下拉框切换为 50 / 100 条；市场按页请求，搜索与筛选覆盖所有已发布动作。图标区只显示当前图标和「图标库」入口；图标库提供文件、图片、办公、开发、网络和工具六类共 64 个内置图标，支持搜索。市场导入的自定义图标继续显示，也可从图标库替换。

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
Apps/RightKit/                  菜单栏 App：设置向导 / 设置 / 自定义动作与日志 / 执行 handoff
Extensions/RightKitFinderSync/  Finder 扩展：只管建菜单，其余交给主 App
Packages/RightKitShared/        域层（动作、脚本执行、偏好、心跳、文案）+ 单测
Docs/                           自定义动作、市场导入与联调指南
plan/                           动作市场与配置导入的设计记录
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
