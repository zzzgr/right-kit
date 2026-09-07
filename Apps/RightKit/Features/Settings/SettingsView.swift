import RightKitShared
import SwiftUI

/// One window, one screen, no tabs.
///
/// The old build split this across three tabs ("General" held an abstract *Default
/// Terminal*, "Menu Items" held the toggles that decided whether that terminal was
/// ever used). Here every row is one menu item, and the app it opens sits right next
/// to it — the window is literally a picture of the Finder submenu.
struct SettingsView: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var status: SetupStatus

    var body: some View {
        Form {
            menuSection
            statusSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 510)
        .onAppear {
            model.refresh()
            status.addWatcher()
        }
        .onDisappear { status.removeWatcher() }
    }

    // MARK: - Menu items

    private var menuSection: some View {
        Section {
            ForEach(MenuAction.allCases) { action in
                MenuActionRow(action: action, isOn: model.binding(for: action)) {
                    picker(for: action)
                }
            }
            if model.installedTerminals.isEmpty {
                Text(Strings.notDetectedHint(Strings.terminalKind))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if model.installedEditors.isEmpty {
                Text(Strings.notDetectedHint(Strings.editorKind))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Text(Strings.sectionMenu)
        } footer: {
            Text(Strings.sectionMenuFooter)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Terminal and editor rows carry their own app picker; the rest carry nothing.
    /// Pickers list Auto plus installed apps only — never software the user does not
    /// have, and "Auto" says what it currently resolves to.
    @ViewBuilder
    private func picker(for action: MenuAction) -> some View {
        switch action {
        case .openInTerminal:
            Picker("", selection: $model.preferredTerminal) {
                Text(autoLabel(model.resolvedTerminal?.displayName)).tag(TerminalApp?.none)
                ForEach(model.installedTerminals) { app in
                    Text(app.displayName).tag(TerminalApp?.some(app))
                }
            }
            .labelsHidden()
            .fixedSize()
        case .openInEditor:
            Picker("", selection: $model.preferredEditor) {
                Text(autoLabel(model.resolvedEditor?.displayName)).tag(EditorApp?.none)
                ForEach(model.installedEditors) { app in
                    Text(app.displayName).tag(EditorApp?.some(app))
                }
            }
            .labelsHidden()
            .fixedSize()
        case .newFile, .newFolder, .copyPath:
            EmptyView()
        }
    }

    private func autoLabel(_ resolved: String?) -> String {
        resolved.map(Strings.autoLabel(_:)) ?? Strings.autoLabel
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            LabeledContent(Strings.extensionRowTitle) {
                HStack(spacing: 8) {
                    extensionBadge
                    Button(Strings.openExtensionSettings) {
                        status.openExtensionSettings()
                    }
                    .controlSize(.small)
                }
            }
            LabeledContent(Strings.setupRowTitle) {
                Button(Strings.reopenSetup) {
                    // Clear the recorded proof so the checklist re-verifies this build
                    // rather than showing a ✓ earned by an earlier copy.
                    status.resetVerification()
                    AppWindows.setup.show()
                }
                .controlSize(.small)
            }
            launchAtLoginRow
        } header: {
            Text(Strings.sectionStatus)
        }
    }

    /// The toggle mirrors System Settings → Login Items. When macOS has accepted the
    /// registration but the user (or a policy) switched it off there, the toggle reads
    /// off and a one-line hint with a button to the right pane appears beneath it.
    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(Strings.launchAtLoginTitle, isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
            if let message = model.loginItemError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if model.loginItemState == .requiresApproval {
                HStack(spacing: 8) {
                    Text(Strings.launchAtLoginNeedsApproval)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(Strings.openLoginItems) {
                        LoginItem.openSystemSettings()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var extensionBadge: some View {
        if status.isVerified && status.extensionEnabled {
            Label(Strings.statusWorking, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if status.extensionEnabled {
            Label(Strings.statusEnabled, systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            Label(Strings.statusDisabled, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent(Strings.versionTitle) {
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            LabeledContent(Strings.authorTitle) {
                Text("乌鸡哥")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(Strings.sectionAbout)
        }
    }
}

// MARK: - Row

private struct MenuActionRow<Accessory: View>: View {
    let action: MenuAction
    @Binding var isOn: Bool
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(action.settingsTitle)
            Spacer(minLength: 8)
            accessory()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
