import AppKit
import RightKitShared
import SwiftUI

enum CustomActionsTab: Hashable { case configuration, script, test }

struct CustomActionsView: View {
    static let minimumWindowSize = NSSize(width: 960, height: 650)

    @EnvironmentObject private var model: CustomActionsModel
    @State private var actionsPage = 1
    @State private var actionsPageSize = MarketQuery.defaultPageSize

    private var sidebarActions: [CustomAction] {
        var actions = model.actions
        if let draft = model.draft, !actions.contains(where: { $0.id == draft.id }) { actions.append(draft) }
        return actions
    }
    private var actionsPagination: MarketPagination {
        MarketPagination(total: sidebarActions.count, page: actionsPage, pageSize: actionsPageSize)
    }
    private var visibleActions: [CustomAction] {
        Array(sidebarActions.dropFirst((actionsPagination.page - 1) * actionsPageSize).prefix(actionsPageSize))
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionTabs
            Divider()
            if model.section == .market {
                VStack(spacing: 0) {
                    if let error = model.error {
                        Text(error).foregroundStyle(.red).textSelection(.enabled).padding(12)
                    }
                    MarketPane()
                }
            } else {
                HSplitView {
                    sidebar.frame(minWidth: 260, idealWidth: 280, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
                    actionDetail.frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .controlSize(.small)
        .frame(minWidth: Self.minimumWindowSize.width, maxWidth: .infinity,
               minHeight: Self.minimumWindowSize.height, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { followSelectedAction() }
        .onChange(of: model.draft?.id) { _ in followSelectedAction() }
        .onChange(of: model.actions.map(\.id)) { _ in followSelectedAction() }
        .onChange(of: actionsPageSize) { _ in followSelectedAction() }
        .sheet(item: $model.importRequest, onDismiss: {
            if model.importRequest == nil { model.cancelImport() }
        }) { request in
            ActionImportSheet(requestID: request.id)
        }
    }

    private var sectionTabs: some View {
        Picker(Strings.Custom.title, selection: $model.section) {
            Text(Strings.Custom.myActions).tag(CustomActionsSection.mine)
            Text(Strings.Custom.market).tag(CustomActionsSection.market)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .font(.system(size: 14, weight: .medium))
        .labelsHidden()
        .frame(width: 340)
        .accessibilityIdentifier("actions.section")
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if model.section == .market && model.activeCount > 0 {
                Button(Strings.Custom.activeTasks(model.activeCount), action: model.showRuns)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(.regularMaterial)
    }

    private var actionDetail: some View {
        VStack(spacing: 0) {
            if let error = model.error, model.draft == nil {
                Text(error).foregroundStyle(.red).textSelection(.enabled).padding(12)
            }
            if let message = model.catalogError {
                catalogFailure(message)
            } else if let draft = model.draft {
                CustomActionEditor(action: Binding(
                    get: { model.draft ?? draft },
                    set: { model.draft = $0 }
                ))
                .id(draft.id)
            } else if !model.runs.isEmpty && model.editorTab == .test {
                CustomActionTestView(action: nil)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: Binding(get: { model.draft?.id }, set: { if let id = $0 { model.select(id) } })) {
                ForEach(visibleActions) { saved in
                    actionRow(model.draft?.id == saved.id ? model.draft ?? saved : saved)
                        .tag(saved.id)
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("actions.list")

            Divider()
            sidebarControls
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    private var sidebarPagination: some View {
        HStack(spacing: 4) {
            Picker(Strings.Custom.pageSize, selection: $actionsPageSize) {
                ForEach(MarketQuery.pageSizes, id: \.self) { size in Text(Strings.Custom.perPage(size)).tag(size) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize()
            .accessibilityIdentifier("actions.pageSize")
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Button { actionsPage = actionsPagination.page - 1 } label: {
                    Image(systemName: "chevron.left").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .disabled(actionsPagination.page <= 1)
                .help(Strings.Custom.previousPage).accessibilityLabel(Strings.Custom.previousPage)
                .accessibilityIdentifier("actions.previousPage")
                Text(Strings.Custom.pagePosition(actionsPagination.page, actionsPagination.totalPages))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    .accessibilityIdentifier("actions.pagePosition")
                Button { actionsPage = actionsPagination.page + 1 } label: {
                    Image(systemName: "chevron.right").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .disabled(actionsPagination.page >= actionsPagination.totalPages)
                .help(Strings.Custom.nextPage).accessibilityLabel(Strings.Custom.nextPage)
                .accessibilityIdentifier("actions.nextPage")
            }
            .buttonStyle(.borderless)
        }
    }

    private func followSelectedAction() {
        if let index = sidebarActions.firstIndex(where: { $0.id == model.draft?.id }) { actionsPage = index / actionsPageSize + 1 }
        else { actionsPage = actionsPagination.page }
    }

    private var sidebarControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                newActionButton.keyboardShortcut("n", modifiers: .command)
                Spacer(minLength: 0)
                Button(action: model.duplicate) { Image(systemName: "doc.on.doc") }
                    .help(Strings.Custom.duplicate).accessibilityLabel(Strings.Custom.duplicate)
                    .disabled(model.draft == nil || !model.canEdit || model.actions.count >= 100)
                Button(action: model.delete) { Image(systemName: "trash") }
                    .help(Strings.Custom.delete).accessibilityLabel(Strings.Custom.delete)
                    .disabled(model.draft == nil || !model.canEdit)
            }
            .buttonStyle(.borderless)
            if !sidebarActions.isEmpty { sidebarPagination }
            ActionOrderControls(selectedIndex: model.selectedIndex, totalCount: model.actions.count,
                                enabled: model.canEdit, onMove: model.move)
            if model.activeCount > 0 {
                Button(Strings.Custom.activeTasks(model.activeCount), action: model.showRuns)
                    .buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(12)
    }

    private func actionRow(_ action: CustomAction) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: model.image(for: action.icon)).resizable().scaledToFit().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title.isEmpty ? Strings.Custom.untitled : action.title).lineLimit(1)
                if !action.isEnabled {
                    Text(Strings.Custom.disabled).font(.caption).foregroundStyle(.secondary)
                } else if !action.group.isEmpty {
                    Text(action.group).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var newActionButton: some View {
        Button(action: model.create) {
            Label(Strings.Custom.newAction, systemImage: "plus")
        }
        .fixedSize()
        .disabled(!model.canEdit || model.actions.count >= 100)
    }

    private func catalogFailure(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).textSelection(.enabled).multilineTextAlignment(.center)
            Button(Strings.Custom.retry, action: model.reload)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct CustomActionEditor: View {
    @EnvironmentObject private var model: CustomActionsModel
    @Binding var action: CustomAction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let metadata = action.packageMetadata {
                HStack {
                    Text("v\(metadata.version)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    if let marketURL = metadata.marketURL, metadata.tracksUpdates != false {
                        Button(Strings.Custom.checkUpdates) { model.openMarketURL(marketURL) }.buttonStyle(.borderless)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 10)
            }
            if let notice = model.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel(Strings.Custom.dismiss)
                }
                .font(.callout).padding(12)
                .background(Color.red.opacity(0.07)).padding(.horizontal, 16).padding(.bottom, 10)
            }
            Picker(Strings.Custom.title, selection: $model.editorTab) {
                Text(Strings.Custom.configuration).tag(CustomActionsTab.configuration)
                Text(Strings.Custom.script).tag(CustomActionsTab.script)
                Text(Strings.Custom.test).tag(CustomActionsTab.test)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)
            .padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            Group {
                switch model.editorTab {
                case .configuration: CustomActionConfiguration(action: $action)
                case .script: CustomActionScriptEditor(action: $action)
                case .test: CustomActionTestView(action: action)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.image(for: action.icon)).resizable().scaledToFit().frame(width: 26, height: 26)
                .frame(width: 40, height: 40)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            Text(action.title.isEmpty ? Strings.Custom.untitled : action.title).font(.title3.weight(.semibold)).lineLimit(1)
            if model.isDirty {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    .help(Strings.Custom.unsaved).accessibilityLabel(Strings.Custom.unsaved)
            }
            Spacer(minLength: 8)
            if model.isDirty {
                Button(Strings.Custom.discard, action: model.discard).buttonStyle(.borderless)
            }
            Button(action: model.copyPackage) { Image(systemName: "square.and.arrow.up") }
                .help(Strings.Custom.copyAction).accessibilityLabel(Strings.Custom.copyAction)
            Button(Strings.Custom.save) { model.save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isDirty || !model.canEdit)
        }
        .padding(16)
    }
}

private struct CustomActionConfiguration: View {
    @EnvironmentObject private var model: CustomActionsModel
    @Binding var action: CustomAction
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField(Strings.Custom.name, text: $action.title).focused($isNameFocused)
                TextField(Strings.Custom.group, text: $action.group, prompt: Text(Strings.Custom.groupHint))
                Toggle(Strings.Custom.enabled, isOn: $action.isEnabled).toggleStyle(.switch).controlSize(.small)
            }
            Section(Strings.Custom.icon) {
                HStack(spacing: 12) {
                    Image(nsImage: model.image(for: action.icon)).resizable().scaledToFit().frame(width: 24, height: 24)
                        .accessibilityLabel(Strings.Custom.icon)
                        .accessibilityIdentifier("actions.currentIcon")
                    Spacer()
                    ActionSymbolPicker(icon: $action.icon)
                }
            }
            Section(Strings.Custom.rules) {
                Picker(Strings.Custom.target, selection: $action.rules.target) {
                    Text(Strings.Custom.both).tag(ActionInputRules.Target.both)
                    Text(Strings.Custom.files).tag(ActionInputRules.Target.files)
                    Text(Strings.Custom.folders).tag(ActionInputRules.Target.folders)
                }
                if action.rules.target != .folders {
                    Picker(Strings.Custom.fileType, selection: $action.rules.fileType) {
                        Text(Strings.Custom.allTypes).tag(ActionInputRules.FileType.any)
                        Text(Strings.Custom.images).tag(ActionInputRules.FileType.images)
                        Text(Strings.Custom.extensions).tag(ActionInputRules.FileType.extensions)
                    }
                    if action.rules.fileType == .extensions {
                        TextField(Strings.Custom.extensions, text: $action.rules.extensions, prompt: Text(Strings.Custom.extensionsHint))
                    }
                }
                Picker(Strings.Custom.selection, selection: $action.rules.selection) {
                    Text(Strings.Custom.anySelection).tag(ActionInputRules.Selection.any)
                    Text(Strings.Custom.single).tag(ActionInputRules.Selection.single)
                    Text(Strings.Custom.multiple).tag(ActionInputRules.Selection.multiple)
                }
            }

            Section(Strings.Custom.execution) {
                Picker(Strings.Custom.batchMode, selection: $action.batchMode) {
                    Text(Strings.Custom.together).tag(ScriptBatchMode.together)
                    Text(Strings.Custom.individually).tag(ScriptBatchMode.individually)
                }
                Picker(Strings.Custom.workingDirectory, selection: $action.workingDirectory) {
                    Text(Strings.Custom.selectionDirectory).tag(ScriptWorkingDirectory.selection)
                    Text(Strings.Custom.finderDirectory).tag(ScriptWorkingDirectory.finder)
                    Text(Strings.Custom.customDirectory).tag(ScriptWorkingDirectory.custom)
                }
                if action.workingDirectory == .custom {
                    HStack {
                        TextField(Strings.Custom.workingDirectory, text: $action.customWorkingDirectory).labelsHidden()
                        Button(Strings.Custom.choose, action: model.chooseDirectory)
                    }
                }
                LabeledContent(Strings.Custom.timeout) {
                    TextField(Strings.Custom.timeout, value: $action.timeoutSeconds, format: .number.grouping(.never))
                        .labelsHidden().frame(width: 80).multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { isNameFocused = action.title.isEmpty }
    }
}

private struct CustomActionScriptEditor: View {
    @EnvironmentObject private var model: CustomActionsModel
    @Binding var action: CustomAction
    @State private var showEnvironment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                Picker(Strings.Custom.language, selection: $action.language) {
                    ForEach(ScriptLanguage.allCases, id: \.self) { language in Text(language.title).tag(language) }
                }.frame(maxWidth: 220)
                Spacer(minLength: 0)
                Picker(Strings.Custom.source, selection: $action.source) {
                    Text(Strings.Custom.inline).tag(ScriptSource.inline)
                    Text(Strings.Custom.externalFile).tag(ScriptSource.file)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 270)
            }
            if action.language == .python {
                HStack {
                    TextField(Strings.Custom.interpreter, text: $action.interpreterPath, prompt: Text(Strings.Custom.interpreterHint))
                        .textFieldStyle(.roundedBorder)
                        .help(Strings.Custom.pythonEnvironmentHelp)
                    Button(Strings.Custom.choose, action: model.chooseInterpreter)
                }
            }
            if action.source == .inline {
                ScriptTextView(text: $action.script)
                    .frame(minHeight: 180, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            } else {
                HStack {
                    TextField(Strings.Custom.externalFile, text: $action.scriptPath)
                        .textFieldStyle(.roundedBorder).help(Strings.Custom.externalScriptHint)
                    Button(Strings.Custom.chooseScript, action: model.chooseScript)
                }
                Spacer(minLength: 20)
            }

            DisclosureGroup(isExpanded: $showEnvironment) {
                environmentEditor
            } label: {
                Text(Strings.Custom.environment + (action.environment.isEmpty ? "" : " (\(action.environment.count))"))
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(20)
        .onAppear { showEnvironment = !action.environment.isEmpty }
    }

    private var environmentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !action.environment.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($action.environment) { $variable in
                            HStack(spacing: 8) {
                                TextField(Strings.Custom.variableName, text: $variable.name)
                                    .font(.system(.body, design: .monospaced)).frame(width: 160)
                                if variable.isSecret {
                                    SecureField(Strings.Custom.secretPlaceholder, text: $variable.value)
                                        .accessibilityLabel(Strings.Custom.variableValue)
                                } else {
                                    TextField(Strings.Custom.variableValue, text: $variable.value)
                                }
                                Toggle(Strings.Custom.secret, isOn: $variable.isSecret)
                                    .toggleStyle(.checkbox).fixedSize().help(Strings.Custom.secretHint)
                                Button { action.environment.removeAll { $0.id == variable.id } } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless).help(Strings.Custom.remove).accessibilityLabel(Strings.Custom.remove)
                            }
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: min(132, CGFloat(action.environment.count) * 34))
            }
            Button(Strings.Custom.addVariable) { action.environment.append(ScriptEnvironmentVariable()) }
                .disabled(action.environment.count >= 64)
        }
        .padding(.top, 8)
    }
}

private struct CustomActionTestView: View {
    @EnvironmentObject private var model: CustomActionsModel
    let action: CustomAction?
    @State private var showStderr = false

    private var matches: Bool { action?.rules.matches(ActionContext(targets: model.samples, container: nil)) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if action != nil {
                testControls
                Divider()
            }
            HStack {
                Picker(Strings.Custom.recentRuns, selection: $model.selectedRunID) {
                    if model.selectedRunID == nil {
                        Text(model.runs.isEmpty ? Strings.Custom.noRuns : Strings.Custom.selectRun).tag(UUID?.none)
                    }
                    ForEach(model.runs) { run in
                        Text("\(run.startedAt.formatted(date: .omitted, time: .standard)) · \(run.title) · \(run.snapshot.state.title)")
                            .tag(UUID?.some(run.id))
                    }
                }
                .help(Strings.Custom.historyHint)
                Spacer(minLength: 4)
                Button(Strings.Custom.copyLog, action: model.copyLog).disabled(model.currentRun == nil)
            }
            if let run = model.currentRun {
                runStatus(run)
                if let error = run.snapshot.error {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
                HStack {
                    Picker(Strings.Custom.output, selection: $showStderr) {
                        Text(Strings.Custom.stdout).tag(false)
                        Text(Strings.Custom.stderr).tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
                    Spacer()
                    if (showStderr ? run.snapshot.stderrTruncated : run.snapshot.stdoutTruncated) {
                        Text(Strings.Custom.truncated).font(.caption).foregroundStyle(.secondary)
                    }
                }
                outputView(showStderr ? run.snapshot.stderr : run.snapshot.stdout)
            } else {
                outputView("")
            }
        }
        .padding(20)
        .onChange(of: model.currentRun?.isFinished) { _ in selectOutputStream() }
        .onChange(of: model.selectedRunID) { _ in selectOutputStream() }
        .onAppear { selectOutputStream() }
    }

    private var testControls: some View {
        Group {
            HStack {
                Button(Strings.Custom.chooseSamples, action: model.chooseSamples)
                Text(Strings.Custom.items(model.samples.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: model.testDraft) { Label(Strings.Custom.testDraft, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).keyboardShortcut("r", modifiers: .command)
                    .help(Strings.Custom.testNotice)
                    .disabled(model.samples.isEmpty || !matches || model.activeCount >= 3)
            }
            if !model.samples.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.samples, id: \.self) { url in
                            HStack {
                                Image(systemName: PathUtilities.isDirectory(url) ? "folder" : "doc").foregroundStyle(.secondary)
                                Text(url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                Spacer(minLength: 0)
                                Button { model.removeSample(url) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                                    .help(Strings.Custom.remove).accessibilityLabel(Strings.Custom.remove + " " + url.lastPathComponent)
                            }
                        }
                    }
                }
                .frame(height: min(90, CGFloat(model.samples.count) * 24))
                if !matches { Text(Strings.Custom.sampleMismatch).font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    private func selectOutputStream() {
        guard let run = model.currentRun else { showStderr = false; return }
        showStderr = run.snapshot.stdout.isEmpty && !run.snapshot.stderr.isEmpty
    }

    private func runStatus(_ run: CustomActionRun) -> some View {
        HStack(spacing: 10) {
            if !run.isFinished {
                ProgressView().controlSize(.small).frame(width: 16, height: 16)
            } else {
                Image(systemName: run.snapshot.state == .succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(run.snapshot.state == .succeeded ? .green : .orange)
            }
            Text(run.snapshot.state.title).fontWeight(.medium)
            Text(run.sourceTitle).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if run.snapshot.totalInvocations > 1 {
                Text(Strings.Custom.progress(run.snapshot.completedInvocations, run.snapshot.totalInvocations)).font(.caption).foregroundStyle(.secondary)
            }
            if let code = run.snapshot.exitCode { Text(Strings.Custom.exitCode(code)).font(.caption).foregroundStyle(.secondary) }
            Text(Strings.Custom.duration(run.snapshot.duration)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            if !run.isFinished { Button(Strings.Custom.stop) { model.stop(run.id) } }
        }
    }

    private func outputView(_ text: String) -> some View {
        ScriptTextView(text: .constant(text), isEditable: false)
            .frame(minHeight: 150, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            .overlay(alignment: .topLeading) {
                if text.isEmpty { Text(Strings.Custom.emptyOutput).font(.callout).foregroundStyle(.secondary).padding(12).allowsHitTesting(false) }
            }
    }
}
