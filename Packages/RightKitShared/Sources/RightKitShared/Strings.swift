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

    // MARK: - Dates

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// `2026-01-01`, in the local time zone.
    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// `2026-01-01 00:00:00`, in the local time zone.
    public static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

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
    public static var sectionStatus: String { s("状态", "Status") }
    public static var sectionAbout: String { s("关于", "About") }
    public static var appearance: String { s("外观", "Appearance") }
    public static var appearanceSystem: String { s("跟随系统", "System") }
    public static var appearanceLight: String { s("明亮", "Light") }
    public static var appearanceDark: String { s("黑暗", "Dark") }

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

    // MARK: - Main window

    public static var sectionGeneral: String { s("通用", "General") }
    public static var menuPreview: String { s("菜单预览", "Menu Preview") }
    public static var menuPreviewEmpty: String {
        s(
            "没有启用任何菜单项，右键菜单中不会出现「右键助手」。",
            "No menu items are enabled, so RightKit stays out of the Finder menu."
        )
    }
    public static var extensionWorkingDetail: String {
        s("扩展已启用，并且已经在 Finder 中弹出过菜单。", "Enabled, and the menu has already opened in Finder.")
    }
    public static var extensionEnabledDetail: String {
        s(
            "扩展已启用。在 Finder 中右键任意文件并选择「右键助手」即可验证。",
            "Enabled. Right-click any file in Finder and choose RightKit to verify."
        )
    }
    public static var extensionDisabledDetail: String {
        s(
            "在「系统设置 → 通用 → 登录项与扩展 → Finder 扩展」中勾选「右键助手」。",
            "Tick RightKit in System Settings → General → Login Items & Extensions → Finder Extensions."
        )
    }
    public static var githubLink: String { s("GitHub 项目", "GitHub Project") }
    public static var guideLink: String { s("自定义动作指南", "Custom Actions Guide") }
    public static var marketWebsite: String { s("市场网页", "Market Website") }
    public static var releasesLink: String { s("下载最新版本", "Latest Release") }
    public static var supportedApps: String { s("支持的 App", "Supported Apps") }

    // MARK: - Menu bar

    public static var menuSettings: String { s("设置…", "Settings…") }
    public static var menuOpenActions: String { s("我的动作…", "My Actions…") }
    public static var menuOpenMarket: String { s("动作市场…", "Action Market…") }
    public static var menuQuit: String { s("退出右键助手", "Quit RightKit") }
    public static var menuExtensionDisabled: String {
        s("Finder 扩展未启用", "Finder extension not enabled")
    }
    public static var menuStatusWorking: String { s("右键菜单正常", "Menu is working") }

    // MARK: - Custom actions

    public enum Custom {
        private static func t(_ zh: String, _ en: String) -> String { Strings.s(zh, en) }
        public static var title: String { t("自定义动作", "Custom Actions") }
        public static var open: String { t("打开…", "Open…") }
        public static var searchActions: String { t("搜索动作", "Search Actions") }
        public static var emptyActionsTitle: String { t("还没有自定义动作", "No Custom Actions Yet") }
        public static var emptyActionsDetail: String {
            t("把 Python 或 Shell 脚本放进右键菜单，或从动作市场导入现成的动作。",
              "Put a Python or Shell script in the right-click menu, or import a ready-made action from the market.")
        }
        public static var browseMarket: String { t("浏览动作市场", "Browse the Market") }
        public static var noMatchingActions: String { t("没有匹配的动作", "No matching actions") }
        public static var selectActionTitle: String { t("选择一个动作", "Select an Action") }
        public static var selectActionDetail: String {
            t("在左侧选择动作查看设置、脚本和测试结果。", "Pick an action on the left to see its settings, script and test runs.")
        }
        public static var fromMarket: String { t("来自市场", "From market") }
        public static var separateCopy: String { t("独立副本", "Separate copy") }
        public static func actionCount(_ count: Int) -> String { t("\(count) 个动作", "\(count) actions") }
        public static var viewDetails: String { t("查看详情", "View Details") }
        public static var runningTasks: String { t("运行中的任务", "Running Tasks") }
        public static var moreActions: String { t("更多操作", "More") }
        public static var testFiles: String { t("测试文件", "Test Files") }
        public static var noTestFiles: String {
            t("选择几个文件或文件夹作为输入，脚本会像在 Finder 中一样运行。",
              "Choose a few files or folders as input. The script runs exactly as it would from Finder.")
        }
        public static var newAction: String { t("新建动作", "New Action") }
        public static var untitled: String { t("未命名动作", "Untitled Action") }
        public static var duplicate: String { t("复制动作", "Duplicate Action") }
        public static var copySuffix: String { t(" 副本", " Copy") }
        public static var duplicateSecretsHint: String { t("副本中的密钥需要重新填写。", "Enter secret values again for this copy.") }
        public static var seeLogs: String { t("在「自定义动作 → 手动测试」中查看运行日志。", "View run logs in Custom Actions → Manual Test.") }
        public static var retry: String { t("重新读取", "Reload") }
        public static var remove: String { t("移除", "Remove") }
        public static var dismiss: String { t("关闭提示", "Dismiss") }
        public static var externalScriptHint: String { t("每次运行读取此文件的最新内容；请在你常用的编辑器中修改。", "Each run reads the latest file contents. Edit it in your usual editor.") }
        public static var historyHint: String { t("保留本次打开应用期间最近 20 条记录", "Keeps the 20 most recent runs during this app session") }
        public static var sampleMismatch: String { t("当前测试项目不符合此动作的显示条件。", "These test items do not match this action's rules.") }
        public static func activeTasks(_ count: Int) -> String { t("\(count) 个任务运行中", "\(count) tasks running") }
        public static func progress(_ completed: Int, _ total: Int) -> String { t("已执行 \(completed) / \(total) 次", "\(completed) / \(total) invocations") }
        public static var delete: String { t("删除", "Delete") }
        public static var deleteTitle: String { t("删除这个自定义动作？", "Delete this custom action?") }
        public static var deleteDetail: String { t("会移除菜单项和保存的密钥，外部脚本文件不会被删除。", "Removes the menu item and saved secrets. External script files are kept.") }
        public static var cancel: String { t("取消", "Cancel") }
        public static var save: String { t("保存", "Save") }
        public static var unsaved: String { t("未保存", "Unsaved") }
        public static var discard: String { t("放弃更改", "Discard Changes") }
        public static var unsavedTitle: String { t("保存当前动作的更改？", "Save changes to this action?") }
        public static var name: String { t("名称", "Name") }
        public static var group: String { t("菜单分组", "Menu group") }
        public static var groupHint: String { t("可选", "Optional") }
        public static var enabled: String { t("在 Finder 菜单中启用", "Enable in the Finder menu") }
        public static var disabled: String { t("已停用", "Disabled") }
        public static var icon: String { t("图标", "Icon") }
        public static var moveUp: String { t("上移", "Move Up") }
        public static var moveDown: String { t("下移", "Move Down") }
        public static var menuOrder: String { t("菜单排序", "Menu Order") }
        public static var configuration: String { t("动作设置", "Action Settings") }
        public static var rules: String { t("显示条件", "Show When") }
        public static var target: String { t("适用对象", "Targets") }
        public static var both: String { t("文件和文件夹", "Files and folders") }
        public static var files: String { t("文件", "Files") }
        public static var folders: String { t("文件夹", "Folders") }
        public static var fileType: String { t("文件类型", "File type") }
        public static var allTypes: String { t("所有类型", "All types") }
        public static var images: String { t("图片", "Images") }
        public static var extensions: String { t("指定扩展名", "Extensions") }
        public static var extensionsHint: String { t("例如 jpg, png, webp", "For example: jpg, png, webp") }
        public static var selection: String { t("选择数量", "Selection") }
        public static var anySelection: String { t("单选或多选", "One or more items") }
        public static var single: String { t("仅单选", "One item only") }
        public static var multiple: String { t("仅多选", "Multiple items only") }
        public static var script: String { t("脚本", "Script") }
        public static var language: String { t("运行环境", "Runtime") }
        public static var source: String { t("脚本来源", "Script source") }
        public static var inline: String { t("在这里编写", "Write here") }
        public static var externalFile: String { t("外部脚本文件", "External script file") }
        public static var chooseScript: String { t("选择脚本…", "Choose Script…") }
        public static var interpreter: String { t("Python 解释器", "Python interpreter") }
        public static var interpreterHint: String { t("自动选择", "Automatic") }
        public static var choose: String { t("选择…", "Choose…") }
        public static var execution: String { t("执行设置", "Execution") }
        public static var batchMode: String { t("多选时", "With multiple items") }
        public static var together: String { t("全部交给脚本执行一次", "Pass all items in one invocation") }
        public static var individually: String { t("逐个执行", "Run once per item") }
        public static var workingDirectory: String { t("工作目录", "Working directory") }
        public static var selectionDirectory: String { t("选中的文件夹 / 文件所在目录", "Selected folder / file's parent") }
        public static var finderDirectory: String { t("Finder 当前目录", "Current Finder directory") }
        public static var customDirectory: String { t("指定目录", "Custom directory") }
        public static var timeout: String { t("任务超时（秒）", "Task timeout (seconds)") }
        public static var environment: String { t("环境变量", "Environment Variables") }
        public static var addVariable: String { t("添加变量", "Add Variable") }
        public static var variableName: String { t("变量名", "Name") }
        public static var variableValue: String { t("变量值", "Value") }
        public static var secret: String { t("密钥", "Secret") }
        public static var secretHint: String { t("密钥存入钥匙串；留空可保留已保存的值。", "Secrets are stored in Keychain. Leave blank to keep a saved value.") }
        public static var secretPlaceholder: String { t("留空保留已保存值", "Leave blank to keep saved value") }
        public static var test: String { t("手动测试", "Manual Test") }
        public static var testDraft: String { t("运行当前草稿", "Run Current Draft") }
        public static var chooseSamples: String { t("选择测试文件或文件夹…", "Choose Test Files or Folders…") }
        public static var testNotice: String { t("测试会真实执行当前脚本，包括修改文件或上传。测试草稿不会自动更新右键菜单。", "Testing really runs the current script, including file changes or uploads. It does not save the draft to the Finder menu.") }
        public static var stop: String { t("停止", "Stop") }
        public static var output: String { t("运行输出", "Run Output") }
        public static var stdout: String { t("标准输出", "Standard Output") }
        public static var stderr: String { t("错误输出", "Standard Error") }
        public static var emptyOutput: String { t("暂无输出", "No output") }
        public static var copyLog: String { t("复制日志", "Copy Log") }
        public static var recentRuns: String { t("运行记录", "Run History") }
        public static var previousPage: String { t("上一页", "Previous Page") }
        public static var nextPage: String { t("下一页", "Next Page") }
        public static var pageSize: String { t("每页条数", "Page Size") }
        public static var iconLibrary: String { t("图标库…", "Icon Library…") }
        public static var searchIcons: String { t("搜索图标", "Search Icons") }
        public static var iconCategory: String { t("图标分类", "Icon Category") }
        public static var noIcons: String { t("没有匹配的图标", "No matching icons") }
        public static func iconCategoryName(_ category: String) -> String {
            switch category {
            case "all": return t("全部", "All")
            case "files": return t("文件", "Files")
            case "images": return t("图片", "Images")
            case "office": return t("办公", "Office")
            case "development": return t("开发", "Dev")
            case "network": return t("网络", "Network")
            default: return t("工具", "Tools")
            }
        }
        public static func iconName(_ symbol: String) -> String {
            switch symbol {
            case "folder": return t("文件夹", "Folder")
            case "folder.badge.plus": return t("新建文件夹", "New Folder")
            case "doc": return t("文件", "File")
            case "doc.badge.plus": return t("新建文件", "New File")
            case "doc.on.doc": return t("复制文件", "Copy Files")
            case "doc.zipper": return t("压缩文件", "ZIP File")
            case "archivebox": return t("归档", "Archive")
            case "tray.full": return t("收集文件", "Collect Files")
            case "tag": return t("标签", "Tag")
            case "pencil": return t("重命名与编辑", "Rename and Edit")
            case "line.3.horizontal.decrease.circle": return t("筛选", "Filter")
            case "list.bullet": return t("文件清单", "File List")
            case "photo": return t("图片", "Image")
            case "photo.on.rectangle": return t("批量图片", "Image Collection")
            case "crop": return t("裁剪", "Crop")
            case "scissors": return t("切分", "Split")
            case "arrow.up.left.and.arrow.down.right": return t("放大尺寸", "Resize Up")
            case "arrow.down.right.and.arrow.up.left": return t("缩小与压缩", "Shrink and Compress")
            case "rectangle.split.2x2": return t("图片切格", "Image Grid")
            case "rectangle.split.1x2": return t("图片拼接", "Stitch Images")
            case "rotate.right": return t("旋转", "Rotate")
            case "paintbrush": return t("绘制与标注", "Draw and Annotate")
            case "drop": return t("水印", "Watermark")
            case "wand.and.stars": return t("图片优化", "Enhance Image")
            case "doc.richtext": return t("PDF 与文档", "PDF and Documents")
            case "doc.text": return t("文本文件", "Text File")
            case "text.viewfinder": return t("识别文字 OCR", "Recognize Text OCR")
            case "textformat": return t("文本格式", "Text Format")
            case "tablecells": return t("表格", "Spreadsheet")
            case "chart.bar": return t("数据统计", "Statistics")
            case "list.bullet.clipboard": return t("剪贴板", "Clipboard")
            case "calendar": return t("日历", "Calendar")
            case "envelope": return t("邮件", "Email")
            case "printer": return t("打印", "Print")
            case "terminal": return t("终端脚本", "Terminal Script")
            case "curlybraces": return t("JSON 数据", "JSON Data")
            case "chevron.left.forwardslash.chevron.right": return t("代码", "Code")
            case "hammer": return t("构建", "Build")
            case "wrench.and.screwdriver": return t("开发工具", "Developer Tools")
            case "gearshape": return t("配置", "Configuration")
            case "ant": return t("调试", "Debug")
            case "shippingbox": return t("软件包", "Package")
            case "externaldrive": return t("磁盘与备份", "Disk and Backup")
            case "flowchart": return t("工作流", "Workflow")
            case "globe": return t("网页", "Website")
            case "link": return t("链接", "Link")
            case "cloud": return t("云存储 OSS", "Cloud Storage OSS")
            case "icloud.and.arrow.up": return t("上传到云端", "Cloud Upload")
            case "icloud.and.arrow.down": return t("从云端下载", "Cloud Download")
            case "arrow.up.doc": return t("上传文件", "Upload File")
            case "arrow.down.doc": return t("下载文件", "Download File")
            case "arrow.triangle.2.circlepath": return t("同步与转换", "Sync and Convert")
            case "network": return t("网络请求", "Network Request")
            case "server.rack": return t("服务器", "Server")
            case "magnifyingglass": return t("搜索", "Search")
            case "bolt": return t("快捷操作", "Quick Action")
            case "play.circle": return t("执行", "Run")
            case "checkmark.seal": return t("文件校验", "Verify File")
            case "lock.shield": return t("加密与保护", "Encrypt and Protect")
            case "key": return t("密钥", "Key")
            case "trash": return t("清理", "Clean Up")
            case "clock": return t("定时", "Schedule")
            case "square.grid.2x2": return t("分类整理", "Organize")
            case "qrcode": return t("二维码", "QR Code")
            default: return symbol
            }
        }
        public static func perPage(_ count: Int) -> String { t("\(count) 条 / 页", "\(count) per page") }
        public static func pagePosition(_ page: Int, _ total: Int) -> String { t("第 \(page) / \(total) 页", "Page \(page) of \(total)") }
        public static var noRuns: String { t("还没有运行记录", "No runs yet") }
        public static var selectRun: String { t("选择运行记录", "Select a run") }
        public static var running: String { t("运行中", "Running") }
        public static var succeeded: String { t("已完成", "Completed") }
        public static var failed: String { t("运行失败", "Failed") }
        public static var cancelled: String { t("已停止", "Stopped") }
        public static var timedOut: String { t("已超时", "Timed Out") }
        public static var testRun: String { t("手动测试", "Manual test") }
        public static var finderRun: String { t("Finder 运行", "Finder run") }
        public static var emptyTitle: String { t("暂无动作", "No actions") }
        public static var pythonEnvironmentHelp: String { t("留空时优先使用 VIRTUAL_ENV 或 ~/.venvs/rightkit，再查找本机 Python。依赖需安装在对应环境中。", "When left blank, uses VIRTUAL_ENV or ~/.venvs/rightkit before searching local Python installations. Install dependencies in the selected environment.") }
        public static var invalidTitle: String { t("填写动作名称（最多 80 个字符），分组名称最多 60 个字符。", "Enter an action name (up to 80 characters); group names may have up to 60.") }
        public static var invalidTimeout: String { t("超时应为 1 到 3600 秒。", "Timeout must be between 1 and 3600 seconds.") }
        public static var invalidExtensions: String { t("至少填写一个文件扩展名。", "Enter at least one file extension.") }
        public static var absoluteInterpreter: String { t("解释器需要填写完整路径，例如 /opt/homebrew/bin/python3。", "Use an absolute interpreter path, such as /opt/homebrew/bin/python3.") }
        public static var invalidDirectory: String { t("工作目录不存在或不是文件夹，请重新选择。", "The working directory is missing or is not a folder. Choose another directory.") }
        public static var invalidEnvironment: String { t("变量名只能含字母、数字和下划线，不能以数字开头、重复或使用 RIGHTKIT_ 前缀。", "Variable names must use letters, digits or underscores; they cannot start with a digit, repeat, or use the RIGHTKIT_ prefix.") }
        public static var invalidEnvironmentValue: String { t("环境变量不能包含空字符，单个值不能超过 16 KB。", "Environment values cannot contain null characters or exceed 16 KB each.") }
        public static var configurationTooLarge: String { t("配置过大。单个脚本最多 256 KB，每个动作最多 64 个环境变量。", "Configuration is too large. Scripts may use up to 256 KB and actions up to 64 environment variables.") }
        public static var emptyScript: String { t("先编写脚本或选择外部脚本文件。", "Write a script or choose an external script file first.") }
        public static var invalidScriptPath: String { t("请选择存在的脚本文件，并使用完整路径。", "Choose an existing script file using its absolute path.") }
        public static var invalidConfiguration: String { t("配置包含无法传给脚本的字符。", "Configuration contains characters that cannot be passed to the script.") }
        public static var sharedContainerUnavailable: String { t("无法打开共享设置目录，请重新安装 RightKit。", "The shared settings directory is unavailable. Reinstall RightKit.") }
        public static var unsupportedCatalog: String { t("无法读取这个版本的动作配置，原文件已保留。", "This action catalog version cannot be read. The original file has been kept.") }
        public static var invalidCatalog: String { t("动作 ID 不能重复，最多支持 100 个动作。", "Action IDs must be unique. Up to 100 actions are supported.") }
        public static var invalidIcon: String { t("无法读取图标，请选择有效的图片文件。", "The icon could not be read. Choose a valid image file.") }
        public static var invalidSelection: String { t("所选项目不符合动作条件，或包含无法使用的路径。", "The selected items do not match this action or contain unusable paths.") }
        public static var invalidRequest: String { t("无效的脚本运行请求。请从 Finder 菜单或测试面板运行。", "Invalid script request. Run from the Finder menu or test panel.") }
        public static var invalidPackage: String { t("这不是有效的 RightKit 动作包。", "This is not a valid RightKit action package.") }
        public static var expiredRequest: String { t("运行请求已过期或已处理，请重新选择菜单项。", "This request expired or was already handled. Select the menu item again.") }
        public static var actionUnavailable: String { t("动作已被删除或停用，请检查自定义动作设置。", "This action was removed or disabled. Check Custom Actions.") }
        public static var missingPython: String { t("没有找到 Python。请选择已安装的 Python 或虚拟环境解释器。", "Python was not found. Choose an installed Python or virtual-environment interpreter.") }
        public static var missingInterpreter: String { t("解释器不存在或不能执行，请检查路径。", "The interpreter is missing or is not executable. Check its path.") }
        public static var missingInput: String { t("所选文件或文件夹已经不存在。", "A selected file or folder no longer exists.") }
        public static var tooManyRuns: String { t("最多同时运行 3 个任务，请等待或停止现有任务。", "Up to 3 tasks may run at once. Wait for or stop an existing task.") }
        public static var truncated: String { t("输出较长，仅保留前 256 KB。", "Output was truncated to the first 256 KB.") }
        public static func items(_ count: Int) -> String { t("\(count) 个项目", "\(count) items") }
        public static func exitCode(_ code: Int32) -> String { t("退出码 \(code)", "Exit code \(code)") }
        public static func duration(_ seconds: Double) -> String { String(format: t("%.1f 秒", "%.1f s"), seconds) }
        public static func missingSecret(_ name: String) -> String { t("请为环境变量 \(name) 填写密钥。", "Enter a secret for environment variable \(name).") }
        public static func launchError(_ reason: String) -> String { t("无法运行脚本：\(reason)", "Could not run the script: \(reason)") }
        public static func keychainError(_ reason: String) -> String { t("无法访问保存的密钥：\(reason)", "Could not access the saved secret: \(reason)") }
        public static func importedPackage(_ title: String, _ version: String) -> String { t("已导入「\(title)」v\(version)，请检查配置后保存。", "Imported “\(title)” v\(version). Review it, then save.") }
        public static var copiedPackage: String { t("动作已复制，可粘贴到市场编辑器。", "Action copied. Paste it into the market editor.") }
        public static var copyAction: String { t("复制动作包", "Copy Action Package") }
        public static var checkUpdates: String { t("检查市场更新", "Check Market Updates") }
        public static var allLanguages: String { t("全部语言", "All Languages") }
        public static var updatesOnly: String { t("仅看可更新", "Updates Only") }
        public static var noMarketResults: String { t("没有符合条件的动作。", "No actions match these filters.") }
        public static var marketEmptyTitle: String { t("配置动作市场", "Set Up Your Market") }
        public static var marketNoResultsTitle: String { t("暂无动作", "No Actions") }
        public static var importFailed: String { t("无法打开这个动作", "Unable to Open This Action") }
        public static var invalidMarketCatalog: String { t("市场返回的目录格式无效，请检查市场地址。", "The market returned an invalid catalog. Check its address.") }
        public static var invalidMarketURL: String { t("请输入完整的 HTTP 或 HTTPS 市场地址。", "Enter a complete HTTP or HTTPS market URL.") }
        public static var invalidMarketLink: String { t("这个 RightKit 链接无效，请从动作详情页重新打开。", "This RightKit link is invalid. Open it again from the action page.") }
        public static var marketHTTPSRequired: String { t("当前连接要求使用 HTTPS 地址。", "This connection requires an HTTPS URL.") }
        public static var marketUnavailable: String { t("无法连接市场，请检查地址和网络。", "Unable to connect to the market. Check its address and your network.") }
        public static var marketHashMismatch: String { t("下载文件校验失败，请刷新市场后重试。", "The downloaded file failed verification. Refresh the market and try again.") }
        public static var marketIncompatible: String { t("这个动作需要更新版本的 RightKit。", "This action requires a newer version of RightKit.") }
        public static var installed: String { t("已安装", "Installed") }
        public static var updateAvailable: String { t("可更新", "Update Available") }
        public static var actionDescription: String { t("动作说明", "Description") }
        public static var markdownTaskDone: String { t("已完成", "Completed") }
        public static var markdownTaskPending: String { t("未完成", "Not Completed") }
        public static var sourceCode: String { t("源代码", "Source") }
        public static var versionHistory: String { t("历史版本", "Versions") }
        public static var noVersionHistory: String { t("此来源未提供版本记录。", "This source does not provide version history.") }
        public static var loadMoreVersions: String { t("加载更早版本", "Load Earlier Versions") }
        public static var viewOnMarket: String { t("打开网页详情", "View on Market") }
        public static var preserveLocalEdits: String { t("发生冲突时保留本地改动", "Keep Local Edits When They Conflict") }
        public static var localConfigurationKept: String { t("保留本机解释器、目录路径和仍在使用的密钥配置。", "Your interpreter, directory path, and compatible secret settings are kept.") }
        public static var updateAsDraft: String { t("更新为草稿", "Update as Draft") }
        public static var importCopy: String { t("导入独立副本", "Import Separate Copy") }
        public static var openInstalled: String { t("打开已安装动作", "Open Installed Action") }
        public static var runRequirements: String { t("运行依赖", "Requirements") }
        public static var noRequirements: String { t("无额外依赖", "No Additional Requirements") }
        public static var configurationNeeded: String { t("需要在本机填写", "Configure on This Mac") }
        public static func installedVersion(_ version: String) -> String { t("已安装 v\(version)", "Installed v\(version)") }
        public static func olderVersion(_ installed: String, _ incoming: String) -> String { t("已安装 v\(installed)，当前选择的是较早的 v\(incoming)。", "Version \(installed) is installed; you selected the older version \(incoming).") }
        public static var market: String { t("动作市场", "Action Market") }
        public static var myActions: String { t("我的动作", "My Actions") }
        public static var refreshMarket: String { t("刷新", "Refresh") }
        public static var marketSettings: String { t("市场设置", "Market Settings") }
        public static var marketLink: String { t("市场地址", "Market URL") }
        public static var marketLinkHint: String { t("只需配置一个市场，支持 HTTP 和 HTTPS，可填写首页或目录地址。", "Configure one market using an HTTP or HTTPS homepage or catalog URL.") }
        public static var clearMarket: String { t("清除配置", "Clear Market") }
        public static var marketSaved: String { t("已保存，动作列表已更新。", "Saved. The action list is up to date.") }
        public static var marketVerifying: String { t("验证中…", "Verifying…") }
        public static var marketSourceMissing: String { t("市场配置已更改，请重新打开市场设置。", "The market configuration changed. Reopen Market Settings.") }
        public static func marketActionCount(_ count: Int) -> String { t("\(count) 个动作", "\(count) actions") }
        public static func marketLastRefreshed(_ date: String) -> String { t("上次刷新：\(date)", "Last refreshed: \(date)") }
        public static var clearSearch: String { t("清空搜索", "Clear Search") }
        public static var clearFilters: String { t("清除筛选", "Clear Filters") }
        public static var close: String { t("关闭", "Close") }
        public static var marketURL: String { t("输入市场网址", "Enter a market URL") }
        public static var marketSearch: String { t("搜索动作…", "Search actions…") }
        public static var marketEmpty: String { t("在「市场设置」中填写一个地址，或在网页点击「添加到 RightKit」。", "Enter a URL in Market Settings, or choose “Add to RightKit” on the website.") }
        public static var marketOffline: String { t("离线，显示上次成功缓存", "Offline — showing the last successful cache") }
        public static var importAction: String { t("导入为草稿", "Import as Draft") }
        public static var downloading: String { t("读取动作…", "Loading action…") }
    }
}
