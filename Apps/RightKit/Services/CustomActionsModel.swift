import AppKit
import Combine
import RightKitShared

struct CustomActionRun: Identifiable {
    enum Source { case manual, finder }

    let id: UUID
    let actionID: UUID
    let title: String
    let source: Source
    let startedAt: Date
    let inputPaths: [String]
    var snapshot = ScriptRunSnapshot()
    var isFinished = false

    var sourceTitle: String { source == .manual ? Strings.Custom.testRun : Strings.Custom.finderRun }
}

@MainActor
final class CustomActionsModel: ObservableObject {
    static let shared = CustomActionsModel()

    @Published private(set) var actions: [CustomAction] = []
    @Published var draft: CustomAction?
    @Published var error: String?
    @Published private(set) var catalogError: String?
    @Published private(set) var notice: String?
    @Published private(set) var samples: [URL] = []
    @Published private(set) var runs: [CustomActionRun] = []
    @Published var selectedRunID: UUID?
    @Published var editorTab: CustomActionsTab = .configuration
    @Published var importRequest: ActionImportRequest?
    private var importTask: Task<Void, Never>?
    private var importLoader: (@MainActor () async throws -> PackageImportPreview)?
    @Published private var handles: [UUID: ScriptRunHandle] = [:]

    private var store: CustomActionStore?
    private let secretStore = ScriptSecretStore()
    private var testDirectory: URL?
    private var imageCache: [String: NSImage] = [:]
    private var quitCompletion: (() -> Void)?
    private var isQuitting = false

    private init() { reload() }

    func importDirectURL(_ url: URL, marketURL: URL? = nil, sha256: String? = nil) {
        beginImport { try await MarketService.shared.previewDirect(url, marketURL: marketURL, sha256: sha256) }
    }

    func previewMarketEntry(_ entry: MarketEntry) {
        beginImport { try await MarketService.shared.preview(entry) }
    }

    func handleMarketLink(_ url: URL) {
        do {
            let link = try MarketLink.parse(url)
            switch link.kind {
            case .importAction: importDirectURL(link.url, marketURL: link.marketURL, sha256: link.sha256)
            case .market: openMarketURL(link.url)
            }
        } catch {
            if url.host?.lowercased() == "market" {
                AppNavigation.shared.show(.market)
                MarketService.shared.error = error.localizedDescription
            } else { presentImportFailure(error.localizedDescription) }
        }
    }

    var canRetryImport: Bool { importLoader != nil }

    func retryImport() {
        guard let loader = importLoader else { return }
        beginImport(loader)
    }

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importLoader = nil
        importRequest = nil
    }

    private func presentImportFailure(_ message: String) {
        cancelImport()
        importRequest = ActionImportRequest(state: .failed(message))
    }

    private func beginImport(_ loader: @escaping @MainActor () async throws -> PackageImportPreview) {
        importTask?.cancel()
        importLoader = loader
        let request = ActionImportRequest(state: .loading)
        importRequest = request
        importTask = Task { @MainActor [weak self] in
            do {
                let preview = try await loader()
                try Task.checkCancellation()
                guard self?.importRequest?.id == request.id else { return }
                self?.importRequest?.state = .ready(preview)
            } catch {
                guard !Task.isCancelled, self?.importRequest?.id == request.id else { return }
                self?.importRequest?.state = .failed(error.localizedDescription)
            }
        }
    }

    func installedAction(for preview: PackageImportPreview) -> CustomAction? {
        actions.first { ActionPackageUpdate.matches($0.packageMetadata, packageID: preview.package.id, source: preview.source,
                                                    marketURL: preview.marketURL, sourceURL: preview.sourceURL) }
    }

    func installedAction(for entry: MarketEntry) -> CustomAction? {
        actions.first { ActionPackageUpdate.matches($0.packageMetadata, packageID: entry.item.id, source: .market,
                                                    marketURL: entry.source.url, sourceURL: entry.item.packageURL) }
    }

    func openMarketURL(_ url: URL) {
        AppNavigation.shared.show(.market)
        Task { await MarketService.shared.configure(url.absoluteString) }
    }

    func copyPackage() {
        guard let action = draft, let store else { return }
        do {
            let packageID = action.packageMetadata?.id ?? "local.\(action.id.uuidString.lowercased())"
            let iconData: Data?
            if case .image(let name) = action.icon, let url = store.iconURL(named: name) { iconData = try Data(contentsOf: url) } else { iconData = nil }
            let package = try ActionPackageExporter.make(from: action, iconData: iconData, packageID: packageID, version: action.packageMetadata?.version ?? "1.0.0", summary: action.packageMetadata?.summary)
            let data = try package.encodedData()
            NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .string)
            notice = Strings.Custom.copiedPackage
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func stage(_ package: ActionPackage, source: CustomAction.PackageMetadata.Source, sourceURL: URL? = nil,
               marketURL: URL? = nil, sha256: String? = nil, preferLocal: Bool = true, asCopy: Bool = false) throws -> Bool {
        try package.checkCompatibility()
        guard canEdit, resolveUnsavedChanges() else { return false }
        guard let store else { throw CustomActionError.message(Strings.Custom.sharedContainerUnavailable) }
        let previous = asCopy ? nil : actions.first {
            ActionPackageUpdate.matches($0.packageMetadata, packageID: package.id, source: source, marketURL: marketURL, sourceURL: sourceURL)
        }
        if let previous, previous.packageMetadata?.version == package.version {
            draft = previous; editorTab = .configuration
            AppNavigation.shared.show(.actions)
            return true
        }
        guard previous != nil || actions.count < 100 else { throw CustomActionError.message(Strings.Custom.invalidCatalog) }
        let icon: CustomActionIcon
        switch package.action.icon {
        case .symbol(let name): icon = .symbol(name)
        case .png(let data): icon = .image(try store.addIcon(png: data))
        }
        var imported = try package.makeCustomAction(icon: icon)
        if let previous {
            let localIconData: Data?
            if case .image(let name) = previous.icon, let url = store.iconURL(named: name) {
                localIconData = try? Data(contentsOf: url)
            } else { localIconData = nil }
            imported = ActionPackageUpdate.merge(imported, with: previous, package: package, preferLocal: preferLocal, localIconData: localIconData)
        }
        var metadata = CustomAction.PackageMetadata(id: package.id, version: package.version, source: source, sourceURL: sourceURL,
                                                    marketURL: marketURL, sha256: sha256, summary: package.summary, requirements: package.requirements)
        metadata.baseline = package
        metadata.description = package.description
        metadata.tags = package.tags
        metadata.directoryPrompt = package.action.workingDirectory.prompt
        metadata.environmentHints = Dictionary(uniqueKeysWithValues: package.action.environment.compactMap { variable in
            variable.hint.map { (variable.name, $0) }
        })
        metadata.tracksUpdates = !asCopy
        imported.packageMetadata = metadata
        draft = imported
        editorTab = .configuration
        AppNavigation.shared.show(.actions)
        selectedRunID = nil
        error = nil
        notice = Strings.Custom.importedPackage(package.action.title, package.version)
        cleanUnusedIcons()
        if let marketURL { Task { await MarketService.shared.configureIfNeeded(marketURL.absoluteString) } }
        return true
    }

    var isDirty: Bool {
        guard let draft else { return false }
        return actions.first(where: { $0.id == draft.id }) != draft
    }

    var activeCount: Int { handles.count }
    var canEdit: Bool { catalogError == nil && !isQuitting }
    var currentRun: CustomActionRun? { runs.first { $0.id == selectedRunID } }
    var selectedIndex: Int? { actions.firstIndex { $0.id == draft?.id } }

    func showRuns() {
        editorTab = .test
        selectedRunID = runs.first(where: { !$0.isFinished })?.id ?? selectedRunID ?? runs.first?.id
        AppNavigation.shared.show(.actions)
    }

    func reload() {
        guard !isDirty else { return }
        do {
            let store = try CustomActionStore.sharedStore()
            let actions = try store.load()
            self.store = store
            self.actions = actions
            draft = actions.first(where: { $0.id == draft?.id }) ?? actions.first
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    func select(_ id: UUID?) {
        guard id != draft?.id, resolveUnsavedChanges() else { return }
        draft = actions.first { $0.id == id }
        selectedRunID = runs.first { $0.actionID == id }?.id
        clearFeedback()
        cleanUnusedIcons()
    }

    func create() {
        guard canEdit, resolveUnsavedChanges() else { return }
        guard actions.count < 100 else { error = Strings.Custom.invalidCatalog; return }
        draft = CustomAction()
        editorTab = .configuration
        selectedRunID = nil
        clearFeedback()
        cleanUnusedIcons()
    }

    func duplicate() {
        guard actions.count < 100, resolveUnsavedChanges(), let current = draft else { return }
        var copy = actions.first(where: { $0.id == current.id }) ?? current
        copy.id = UUID()
        copy.packageMetadata?.tracksUpdates = false
        copy.title = String(copy.title.prefix(70)) + Strings.Custom.copySuffix
        for index in copy.environment.indices {
            copy.environment[index].id = UUID()
            if copy.environment[index].isSecret { copy.environment[index].value = "" }
        }
        draft = copy
        selectedRunID = nil
        clearFeedback()
        if copy.environment.contains(where: \.isSecret) { notice = Strings.Custom.duplicateSecretsHint }
    }

    @discardableResult
    func save() -> Bool {
        guard canEdit, let store, var candidate = draft else { return false }
        let previous = actions.first { $0.id == candidate.id }
        var newSecrets: [UUID] = []
        do {
            candidate.title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            candidate.group = candidate.group.trimmingCharacters(in: .whitespacesAndNewlines)
            try candidate.validate()
            for index in candidate.environment.indices {
                let variable = candidate.environment[index]
                if variable.isSecret && !variable.value.isEmpty {
                    let newID = UUID()
                    try secretStore.write(variable.value, actionID: candidate.id, variableID: newID,
                                          label: "\(candidate.title) · \(variable.name)")
                    newSecrets.append(newID)
                    candidate.environment[index].id = newID
                    candidate.environment[index].value = ""
                }
            }
            var updated = actions
            if let index = updated.firstIndex(where: { $0.id == candidate.id }) { updated[index] = candidate }
            else { updated.append(candidate) }
            try store.save(updated)
            actions = updated
            draft = candidate
            clearFeedback()
        } catch {
            for id in newSecrets { try? secretStore.delete(actionID: candidate.id, variableID: id) }
            self.error = error.localizedDescription
            return false
        }
        // The atomic catalog now references the new keys. Obsolete keys can be
        // removed without invalidating an already saved action if writing failed.
        if let previous {
            let kept = Set(candidate.environment.filter(\.isSecret).map(\.id))
            for variable in previous.environment where variable.isSecret && !kept.contains(variable.id) {
                do { try secretStore.delete(actionID: previous.id, variableID: variable.id) }
                catch { self.error = error.localizedDescription }
            }
        }
        cleanUnusedIcons()
        return true
    }

    func discard() {
        guard let id = draft?.id else { return }
        draft = actions.first { $0.id == id } ?? actions.first
        clearFeedback()
        cleanUnusedIcons()
    }

    func delete() {
        guard let current = draft, canEdit, let store else { return }
        let alert = NSAlert()
        alert.messageText = Strings.Custom.deleteTitle
        alert.informativeText = Strings.Custom.deleteDetail
        alert.addButton(withTitle: Strings.Custom.delete)
        alert.addButton(withTitle: Strings.Custom.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let previous = actions.first { $0.id == current.id }
            let updated = actions.filter { $0.id != current.id }
            try store.save(updated)
            actions = updated
            draft = updated.first
            clearFeedback()
            if let previous {
                for variable in previous.environment where variable.isSecret {
                    try secretStore.delete(actionID: previous.id, variableID: variable.id)
                }
            }
            cleanUnusedIcons()
        } catch { self.error = error.localizedDescription }
    }

    func move(_ offset: Int) {
        guard let index = selectedIndex else { return }
        let destination = index + offset
        guard actions.indices.contains(destination) else { return }
        move(from: IndexSet(integer: index), to: destination > index ? destination + 1 : destination)
    }

    /// Drag-and-drop reorder from the list. Uses `List.onMove` semantics: `destination`
    /// is the index *before* removal, exactly as SwiftUI hands it over.
    func move(from source: IndexSet, to destination: Int) {
        guard resolveUnsavedChanges(), let store else { return }
        var updated = actions
        updated.move(fromOffsets: source, toOffset: destination)
        guard updated != actions else { return }
        do {
            try store.save(updated)
            actions = updated
            clearFeedback()
        } catch { self.error = error.localizedDescription }
    }

    /// Flip enabled state straight from the list without opening the editor. A
    /// dirty draft for the same action is kept in sync so the toggle never fights it.
    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard canEdit, let store, let index = actions.firstIndex(where: { $0.id == id }) else { return }
        var updated = actions
        updated[index].isEnabled = enabled
        do {
            try store.save(updated)
            actions = updated
            if draft?.id == id { draft?.isEnabled = enabled }
        } catch { self.error = error.localizedDescription }
    }

    /// Closing the editor keeps its draft in memory. Switching actions or quitting
    /// explicitly resolves it so an accidental click cannot lose a script.
    func resolveUnsavedChanges() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = Strings.Custom.unsavedTitle
        alert.informativeText = draft?.title ?? ""
        alert.addButton(withTitle: Strings.Custom.save)
        alert.addButton(withTitle: Strings.Custom.discard)
        alert.addButton(withTitle: Strings.Custom.cancel)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: discard(); return true
        default: return false
        }
    }

    func chooseSamples() {
        let panel = NSOpenPanel()
        panel.title = Strings.Custom.chooseSamples
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            samples = panel.urls
            testDirectory = panel.directoryURL
        }
    }

    func removeSample(_ url: URL) { samples.removeAll { $0 == url } }

    func chooseScript() {
        let panel = NSOpenPanel()
        panel.title = Strings.Custom.chooseScript
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { draft?.scriptPath = url.path }
    }

    func chooseInterpreter() {
        let panel = NSOpenPanel()
        panel.title = Strings.Custom.interpreter
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        // A venv's python is commonly a symlink. Preserve that selected path so
        // Python can find the adjacent pyvenv.cfg instead of using the base env.
        panel.resolvesAliases = false
        if panel.runModal() == .OK, let url = panel.url { draft?.interpreterPath = url.path }
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = Strings.Custom.workingDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { draft?.customWorkingDirectory = url.path }
    }

    func image(for icon: CustomActionIcon) -> NSImage {
        switch icon {
        case .symbol(let name):
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!
        case .image(let name):
            if let cached = imageCache[name] { return cached }
            if let url = store?.iconURL(named: name), let image = NSImage(contentsOf: url) {
                // Action icons are line art: draw them as templates so they take the
                // same ink as SF Symbols and match the market and Finder menu.
                image.isTemplate = true
                imageCache[name] = image
                return image
            }
            return NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!
        }
    }

    func testDraft() {
        guard let draft else { return }
        clearFeedback()
        start(draft, context: ActionContext(targets: samples, container: testDirectory), source: .manual)
    }

    func runFinderRequest(_ url: URL) {
        do {
            let store = try CustomActionStore.sharedStore()
            let request = try CustomActionRequest.consume(url, from: store)
            guard let action = try store.load().first(where: { $0.id == request.actionID }), action.isEnabled else {
                throw CustomActionError.message(Strings.Custom.actionUnavailable)
            }
            start(action, context: request.context, source: .finder)
        } catch {
            self.error = error.localizedDescription
            Notifier.reportCustom(title: Strings.Custom.title, message: error.localizedDescription)
        }
    }

    private func start(_ action: CustomAction, context: ActionContext, source: CustomActionRun.Source) {
        guard !isQuitting else { return }
        guard handles.count < 3 else {
            error = Strings.Custom.tooManyRuns
            if source == .finder { Notifier.reportCustom(title: action.title, message: Strings.Custom.tooManyRuns) }
            return
        }
        let id = UUID()
        runs.insert(CustomActionRun(id: id, actionID: action.id, title: action.title, source: source,
                                    startedAt: Date(), inputPaths: context.targets.map(\.path)), at: 0)
        selectedRunID = id
        trimHistory()
        do {
            try action.validate(forExecution: true)
            guard action.rules.matches(context) else { throw CustomActionError.message(Strings.Custom.invalidSelection) }
            guard context.targets.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw CustomActionError.message(Strings.Custom.missingInput)
            }
            var secrets: [UUID: String] = [:]
            for variable in action.environment where variable.isSecret && variable.value.isEmpty {
                secrets[variable.id] = try secretStore.read(actionID: action.id, variableID: variable.id)
            }
            handles[id] = ScriptRunner.start(action: action, in: context, secrets: secrets, onUpdate: { [weak self] snapshot in
                Task { @MainActor in self?.update(id, snapshot: snapshot, finished: false) }
            }, completion: { [weak self] snapshot in
                Task { @MainActor in self?.update(id, snapshot: snapshot, finished: true) }
            })
        } catch {
            var snapshot = ScriptRunSnapshot()
            snapshot.state = .failed
            snapshot.error = error.localizedDescription
            update(id, snapshot: snapshot, finished: true)
        }
    }

    private func update(_ id: UUID, snapshot: ScriptRunSnapshot, finished: Bool) {
        guard let index = runs.firstIndex(where: { $0.id == id }), !runs[index].isFinished else { return }
        runs[index].snapshot = snapshot
        runs[index].isFinished = finished
        if finished {
            handles.removeValue(forKey: id)
            if runs[index].source == .finder && [.failed, .timedOut].contains(snapshot.state) {
                let reason = snapshot.error ?? snapshot.exitCode.map(Strings.Custom.exitCode) ?? snapshot.state.title
                Notifier.reportCustom(title: runs[index].title, message: reason + "\n" + Strings.Custom.seeLogs)
            }
            if handles.isEmpty, let completion = quitCompletion {
                quitCompletion = nil
                completion()
            }
        }
    }

    func stop(_ id: UUID) { handles[id]?.cancel() }

    func cancelForQuit(completion: @escaping () -> Void) {
        isQuitting = true
        guard !handles.isEmpty else { completion(); return }
        quitCompletion = completion
        for handle in handles.values { handle.cancel() }
    }

    func copyLog() {
        guard let run = currentRun else { return }
        let result = run.snapshot
        let log = [run.title, run.sourceTitle, result.state.title,
                   result.exitCode.map(Strings.Custom.exitCode) ?? "", Strings.Custom.duration(result.duration),
                   result.error ?? "", "\n\(Strings.Custom.stdout)\n", result.stdout,
                   result.stdoutTruncated ? Strings.Custom.truncated : "",
                   "\n\(Strings.Custom.stderr)\n", result.stderr,
                   result.stderrTruncated ? Strings.Custom.truncated : ""].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log, forType: .string)
    }

    private func trimHistory() {
        while runs.count > 20, let index = runs.lastIndex(where: \.isFinished) { runs.remove(at: index) }
    }

    private func clearFeedback() { error = nil; notice = nil }

    private func cleanUnusedIcons() {
        guard let store else { return }
        let used = Set((actions + [draft].compactMap { $0 }).compactMap { action -> String? in
            if case .image(let name) = action.icon { return name }
            return nil
        })
        let files = (try? FileManager.default.contentsOfDirectory(at: store.iconsDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where store.iconURL(named: file.lastPathComponent) != nil && !used.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            imageCache.removeValue(forKey: file.lastPathComponent)
        }
    }
}
