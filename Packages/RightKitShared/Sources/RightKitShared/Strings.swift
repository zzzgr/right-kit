import Foundation

/// Every piece of user-visible text, Chinese first with an English fallback.
///
/// No `.strings` files on purpose: two languages, one file, and the compiler
/// catches a missing case. If a third language is ever needed, this is the single
/// place that has to change.
public enum Strings {
    private static var zh: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }

    private static func s(_ chinese: String, _ english: String) -> String {
        zh ? chinese : english
    }

    // MARK: - App

    public static var appName: String { s("右键助手", "RightKit") }
    public static var tagline: String {
        s("为 Finder 右键菜单添加常用操作", "Useful actions in your Finder right-click menu")
    }

    // MARK: - Actions

    public static var openInTerminal: String { s("在终端中打开", "Open in Terminal") }
    public static var openInEditor: String { s("在编辑器中打开", "Open in Editor") }
    public static func openIn(_ appName: String) -> String {
        s("在 \(appName) 中打开", "Open in \(appName)")
    }
    public static var newFile: String { s("新建文件", "New File") }
    public static var newFolder: String { s("新建文件夹", "New Folder") }
    public static var copyPath: String { s("复制路径", "Copy Path") }

    public static var defaultFileName: String { s("未命名.txt", "Untitled.txt") }
    public static var defaultFolderName: String { s("新建文件夹", "New Folder") }

    // MARK: - Errors

    public static var terminalKind: String { s("终端", "terminal") }
    public static var editorKind: String { s("编辑器", "editor") }

    public static var errorNoTarget: String {
        s("无法确定要操作的位置", "Could not tell which folder to use")
    }
    public static func errorAppNotFound(_ kind: String) -> String {
        s("没有找到可用的\(kind)，请在设置中选择一个", "No \(kind) found — pick one in Settings")
    }
    public static func errorLaunchFailed(_ appName: String, _ reason: String) -> String {
        s("无法启动 \(appName)：\(reason)", "Could not launch \(appName): \(reason)")
    }
    public static func errorCreateFailed(_ name: String, _ reason: String) -> String {
        s("创建「\(name)」失败：\(reason)", "Could not create “\(name)”: \(reason)")
    }
    public static func errorAccessDenied(_ folderName: String) -> String {
        s(
            "macOS 阻止了对「\(folderName)」的访问。点此在隐私设置中允许「右键助手」。",
            "macOS blocked access to “\(folderName)”. Click to allow RightKit in Privacy settings."
        )
    }
    public static var errorPasteboard: String {
        s("无法写入剪贴板", "Could not write to the clipboard")
    }

    // MARK: - Setup

    public static var setupWindowTitle: String { s("设置向导", "Setup") }

    public static var stepLocationTitle: String {
        s("把 App 放进「应用程序」文件夹", "Move RightKit to Applications")
    }
    public static func stepLocationDetail(_ folderName: String) -> String {
        s(
            "当前在「\(folderName)」。放进「应用程序」并重新打开，Finder 扩展才能稳定注册。",
            "Currently in “\(folderName)”. Move it to Applications and reopen so the Finder extension registers reliably."
        )
    }
    public static var stepLocationDetailDiskImage: String {
        s(
            "现在是从磁盘映像运行的。请把「右键助手」拖到「应用程序」，再从那里打开。",
            "You are running from the disk image. Drag RightKit to Applications and open it from there."
        )
    }
    public static var stepLocationAction: String { s("在 Finder 中显示", "Show in Finder") }

    public static var stepExtensionTitle: String { s("启用 Finder 扩展", "Enable the Finder extension") }
    public static var stepExtensionDetail: String {
        s(
            "在「系统设置 → 通用 → 登录项与扩展 → Finder 扩展」中勾选「右键助手」，这里会自动打勾。",
            "Tick “RightKit” in System Settings → General → Login Items & Extensions → Finder Extensions. This ticks itself once enabled."
        )
    }
    public static var stepExtensionAction: String { s("打开系统设置", "Open System Settings") }

    public static var stepVerifyTitle: String { s("在 Finder 中右键试试", "Try it in Finder") }
    public static var stepVerifyDetail: String {
        s(
            "在任意文件夹里右键，选择「右键助手」。菜单打开过一次后，这里会自动打勾。",
            "Right-click any folder and choose “RightKit”. This ticks itself the first time the menu opens."
        )
    }
    public static var stepVerifyDone: String {
        s("已在 Finder 中用过一次", "Confirmed working in Finder")
    }

    public static var setupReady: String {
        s("一切就绪，在 Finder 中右键即可使用。", "All set — right-click anywhere in Finder.")
    }
    public static var setupPrivacyHint: String {
        s(
            "首次在桌面 / 下载 / 文稿中新建文件时，macOS 会请求文件访问权限，点「允许」即可。",
            "The first time you create a file on the Desktop, Downloads or Documents, macOS asks for file access — click Allow."
        )
    }
    public static var setupFinish: String { s("开始使用", "Start Using") }
    public static var setupLater: String { s("以后再说", "Later") }

    // MARK: - Settings

    public static var sectionMenu: String { s("右键菜单", "Right-Click Menu") }
    public static var sectionMenuFooter: String {
        s(
            "关掉全部项目，「右键助手」就不会出现在 Finder 菜单里。",
            "Turn everything off and RightKit disappears from the Finder menu."
        )
    }
    public static var sectionStatus: String { s("状态", "Status") }
    public static var sectionAbout: String { s("关于", "About") }

    public static var extensionRowTitle: String { s("Finder 扩展", "Finder extension") }
    public static var statusEnabled: String { s("已启用", "Enabled") }
    public static var statusDisabled: String { s("未启用", "Not enabled") }
    public static var statusWorking: String { s("正常工作", "Working") }
    public static var openExtensionSettings: String { s("打开系统设置", "Open System Settings") }

    public static var setupRowTitle: String { s("设置向导", "Setup guide") }
    public static var reopenSetup: String { s("重新打开", "Reopen") }

    public static var launchAtLoginTitle: String { s("登录时启动", "Launch at login") }
    public static var launchAtLoginNeedsApproval: String {
        s(
            "macOS 还没允许「右键助手」在后台运行，请在「登录项」里打开它。",
            "macOS has not yet allowed RightKit to run in the background — turn it on under Login Items."
        )
    }
    public static var launchAtLoginFailed: String {
        s("无法修改登录项，请稍后再试。", "Could not change the login item — try again later.")
    }
    public static var openLoginItems: String { s("打开登录项", "Open Login Items") }

    public static var autoLabel: String { s("自动", "Automatic") }
    public static func autoLabel(_ appName: String) -> String {
        s("自动（\(appName)）", "Automatic (\(appName))")
    }
    public static func notDetectedHint(_ kind: String) -> String {
        s("未检测到可用的\(kind)，此项不会出现在菜单中", "No \(kind) detected — this item stays hidden")
    }

    public static var versionTitle: String { s("版本", "Version") }
    public static var authorTitle: String { s("作者", "Author") }

    // MARK: - Menu bar

    public static var menuSettings: String { s("设置…", "Settings…") }
    public static var menuQuit: String { s("退出右键助手", "Quit RightKit") }
    public static var menuExtensionDisabled: String {
        s("Finder 扩展未启用", "Finder extension not enabled")
    }
}
