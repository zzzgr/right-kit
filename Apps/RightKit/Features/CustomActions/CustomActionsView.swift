import AppKit
import RightKitShared
import SwiftUI

enum CustomActionsTab: Hashable { case configuration, script, test }

/// "My Actions": the action list on the left, the selected action's editor on the
/// right. Reordering is drag-and-drop (or ⌘⌥↑ / ⌘⌥↓); enabling is a switch in
/// the row, so the common cases never need the editor at all.
struct CustomActionsView: View {
    @EnvironmentObject private var model: CustomActionsModel
    @State private var search = ""

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Saved actions plus an unsaved new draft appended at the end.
    private var listedActions: [CustomAction] {
        var actions = model.actions
        if let draft = model.draft, !actions.contains(where: { $0.id == draft.id }) { actions.append(draft) }
        guard !query.isEmpty else { return actions }
        return actions.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.group.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340, maxHeight: .infinity)
            detail
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            if model.actions.isEmpty && model.draft == nil {
                emptyList
            } else {
                list
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var sidebarHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(Strings.Custom.myActions).font(.headline)
                Spacer()
                Menu {
                    Button(Strings.Custom.duplicate, action: model.duplicate)
                        .disabled(model.draft == nil || !model.canEdit || model.actions.count >= 100)
                    Button(Strings.Custom.copyAction, action: model.copyPackage)
                        .disabled(model.draft == nil)
                    Divider()
                    Button(Strings.Custom.moveUp) { model.move(-1) }
                        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                        .disabled((model.selectedIndex ?? 0) <= 0 || !model.canEdit || !query.isEmpty)
                    Button(Strings.Custom.moveDown) { model.move(1) }
                        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                        .disabled(model.selectedIndex == nil || model.selectedIndex == model.actions.count - 1
                                  || !model.canEdit || !query.isEmpty)
                    Divider()
                    Button(Strings.Custom.delete, role: .destructive, action: model.delete)
                        .disabled(model.draft == nil || !model.canEdit)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Strings.Custom.moreActions)
                .accessibilityLabel(Strings.Custom.moreActions)
                Button(action: model.create) { Image(systemName: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                    .help(Strings.Custom.newAction)
                    .accessibilityLabel(Strings.Custom.newAction)
                    .disabled(!model.canEdit || model.actions.count >= 100)
            }
            .buttonStyle(.borderless)
            SearchField(placeholder: Strings.Custom.searchActions, text: $search, clearLabel: Strings.Custom.clearSearch)
        }
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 10)
    }

    private var list: some View {
        List(selection: Binding(get: { model.draft?.id }, set: { if let id = $0 { model.select(id) } })) {
            ForEach(listedActions) { saved in
                ActionRow(action: model.draft?.id == saved.id ? model.draft ?? saved : saved,
                          isSaved: model.actions.contains { $0.id == saved.id })
                    .tag(saved.id)
            }
            .onMove { source, destination in
                guard query.isEmpty else { return }
                model.move(from: source, to: destination)
            }
            .moveDisabled(!query.isEmpty || !model.canEdit)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("actions.list")
        .overlay {
            if listedActions.isEmpty {
                Text(Strings.Custom.noMatchingActions)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(Strings.Custom.actionCount(model.actions.count))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private var emptyList: some View {
        EmptyStateView(symbol: "square.stack.3d.up", title: Strings.Custom.emptyActionsTitle,
                       detail: Strings.Custom.emptyActionsDetail) {
            Button(Strings.Custom.newAction, action: model.create)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canEdit)
            Button(Strings.Custom.browseMarket) { AppNavigation.shared.show(.market) }
        }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let message = model.catalogError {
            EmptyStateView(symbol: "exclamationmark.triangle", title: message, tint: .orange) {
                Button(Strings.Custom.retry, action: model.reload)
            }
        } else if let draft = model.draft {
            CustomActionEditor(action: Binding(
                get: { model.draft ?? draft },
                set: { model.draft = $0 }
            ))
            .id(draft.id)
        } else if !model.runs.isEmpty && model.editorTab == .test {
            CustomActionTestView(action: nil)
        } else {
            EmptyStateView(symbol: "cursorarrow.click.2", title: Strings.Custom.selectActionTitle,
                           detail: Strings.Custom.selectActionDetail)
        }
    }
}

// MARK: - Row

private struct ActionRow: View {
    @EnvironmentObject private var model: CustomActionsModel
    let action: CustomAction
    let isSaved: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: model.image(for: action.icon))
                .resizable().scaledToFit()
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(action.isEnabled ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title.isEmpty ? Strings.Custom.untitled : action.title)
                    .lineLimit(1)
                    .foregroundStyle(action.isEnabled ? .primary : .secondary)
                HStack(spacing: 6) {
                    if !action.group.isEmpty {
                        Text(action.group).lineLimit(1)
                    }
                    if let metadata = action.packageMetadata {
                        Text("v\(metadata.version)").monospacedDigit()
                    }
                    if !isSaved {
                        Text(Strings.Custom.unsaved)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if isSaved {
                Toggle("", isOn: Binding(
                    get: { action.isEnabled },
                    set: { model.setEnabled(action.id, $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(Strings.Custom.enabled)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Editor

private struct CustomActionEditor: View {
    @EnvironmentObject private var model: CustomActionsModel
    @Binding var action: CustomAction

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 8) {
                if let notice = model.notice {
                    InlineNotice(message: notice)
                }
                if let error = model.error {
                    InlineErrorBanner(message: error) { model.error = nil }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, model.notice == nil && model.error == nil ? 0 : 10)
            Picker(Strings.Custom.title, selection: $model.editorTab) {
                Text(Strings.Custom.configuration).tag(CustomActionsTab.configuration)
                Text(Strings.Custom.script).tag(CustomActionsTab.script)
                Text(Strings.Custom.test).tag(CustomActionsTab.test)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            .padding(.horizontal, 20).padding(.bottom, 12)
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: model.image(for: action.icon))
                .resizable().scaledToFit()
                .frame(width: 26, height: 26)
                .frame(width: 44, height: 44)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(action.title.isEmpty ? Strings.Custom.untitled : action.title)
                        .font(.title3.weight(.semibold)).lineLimit(1)
                    if model.isDirty {
                        Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                            .help(Strings.Custom.unsaved).accessibilityLabel(Strings.Custom.unsaved)
                    }
                }
                provenance
            }
            Spacer(minLength: 8)
            if model.isDirty {
                Button(Strings.Custom.discard, action: model.discard)
            }
            Button(Strings.Custom.save) { model.save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.isDirty || !model.canEdit)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
    }

    @ViewBuilder private var provenance: some View {
        HStack(spacing: 8) {
            if let metadata = action.packageMetadata {
                StatusPill(text: "v\(metadata.version)", tint: .secondary)
                if metadata.tracksUpdates == false {
                    Text(Strings.Custom.separateCopy)
                } else if let marketURL = metadata.marketURL {
                    Button(Strings.Custom.checkUpdates) { model.openMarketURL(marketURL) }
                        .buttonStyle(.link)
                }
            } else if !action.isEnabled {
                StatusPill(text: Strings.Custom.disabled, tint: .orange)
            } else if !action.group.isEmpty {
                Label(action.group, systemImage: "folder").lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
                LabeledContent(Strings.Custom.icon) {
                    HStack(spacing: 10) {
                        Image(nsImage: model.image(for: action.icon))
                            .resizable().scaledToFit().frame(width: 18, height: 18)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .accessibilityLabel(Strings.Custom.icon)
                            .accessibilityIdentifier("actions.currentIcon")
                        ActionSymbolPicker(icon: $action.icon)
                    }
                }
                Toggle(Strings.Custom.enabled, isOn: $action.isEnabled).toggleStyle(.switch)
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
        .scrollContentBackground(.hidden)
        .onAppear { isNameFocused = action.title.isEmpty }
    }
}

private struct CustomActionScriptEditor: View {
    @EnvironmentObject private var model: CustomActionsModel
    @Binding var action: CustomAction
    @State private var showEnvironment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Picker(Strings.Custom.language, selection: $action.language) {
                    ForEach(ScriptLanguage.allCases, id: \.self) { language in Text(language.title).tag(language) }
                }
                .fixedSize()
                Spacer(minLength: 0)
                Picker(Strings.Custom.source, selection: $action.source) {
                    Text(Strings.Custom.inline).tag(ScriptSource.inline)
                    Text(Strings.Custom.externalFile).tag(ScriptSource.file)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            } else {
                HStack {
                    TextField(Strings.Custom.externalFile, text: $action.scriptPath)
                        .textFieldStyle(.roundedBorder).help(Strings.Custom.externalScriptHint)
                    Button(Strings.Custom.chooseScript, action: model.chooseScript)
                }
                Text(Strings.Custom.externalScriptHint).font(.caption).foregroundStyle(.secondary)
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
                        Text("\(Strings.dateTime(run.startedAt)) · \(run.title) · \(run.snapshot.state.title)")
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
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(Strings.Custom.chooseSamples, action: model.chooseSamples)
                if !model.samples.isEmpty {
                    Text(Strings.Custom.items(model.samples.count)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: model.testDraft) { Label(Strings.Custom.testDraft, systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).keyboardShortcut("r", modifiers: .command)
                    .help(Strings.Custom.testNotice)
                    .disabled(model.samples.isEmpty || !matches || model.activeCount >= 3)
            }
            if model.samples.isEmpty {
                Text(Strings.Custom.noTestFiles).font(.caption).foregroundStyle(.secondary)
            } else {
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
                if !matches {
                    Label(Strings.Custom.sampleMismatch, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
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
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .overlay(alignment: .topLeading) {
                if text.isEmpty { Text(Strings.Custom.emptyOutput).font(.callout).foregroundStyle(.secondary).padding(12).allowsHitTesting(false) }
            }
    }
}
