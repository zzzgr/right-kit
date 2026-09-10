import AppKit
import RightKitShared
import SwiftUI

/// The Finder submenu, editable on the left and previewed on the right.
///
/// Every row on the left is one built-in menu item, with the app it opens sitting
/// right next to it. The preview on the right is a literal picture of the submenu
/// Finder will show — including custom actions and their groups — so there is no
/// guessing what a toggle does.
struct MenuPane: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var actions: CustomActionsModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: Strings.sectionMenu)
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 8)
            HStack(alignment: .top, spacing: 0) {
                Form {
                    builtInSection
                    customSection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity)
                ScrollView {
                    preview.padding(.top, 20).padding(.bottom, 24)
                }
                .frame(width: 300)
                .padding(.trailing, 28)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refresh() }
    }

    // MARK: - Built-in rows

    private var builtInSection: some View {
        Section {
            ForEach(MenuAction.allCases) { action in
                MenuActionRow(action: action, isOn: model.binding(for: action), icon: icon(for: action)) {
                    picker(for: action)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if model.installedTerminals.isEmpty {
                    Text(Strings.notDetectedHint(Strings.terminalKind))
                }
                if model.installedEditors.isEmpty {
                    Text(Strings.notDetectedHint(Strings.editorKind))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
            .disabled(model.installedTerminals.isEmpty)
        case .openInEditor:
            Picker("", selection: $model.preferredEditor) {
                Text(autoLabel(model.resolvedEditor?.displayName)).tag(EditorApp?.none)
                ForEach(model.installedEditors) { app in
                    Text(app.displayName).tag(EditorApp?.some(app))
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(model.installedEditors.isEmpty)
        case .newFile, .newFolder, .copyPath:
            EmptyView()
        }
    }

    private func autoLabel(_ resolved: String?) -> String {
        resolved.map(Strings.autoLabel(_:)) ?? Strings.autoLabel
    }

    private func icon(for action: MenuAction) -> NSImage {
        if let url = action.iconAppURL() {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        return NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)!
    }

    // MARK: - Custom actions summary

    private var customSection: some View {
        Section {
            LabeledContent {
                Button(Strings.Custom.open) { AppNavigation.shared.show(.actions) }
            } label: {
                Text(Strings.Custom.title)
                Text(Strings.Custom.actionCount(actions.actions.filter(\.isEnabled).count))
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.menuPreview)
                .font(.headline)
            MenuPreview(builtIn: enabledBuiltIns, custom: actions.actions.filter(\.isEnabled))
        }
    }

    /// Enabled rows that could appear right now: terminal/editor rows vanish when
    /// no matching app is installed, exactly as they do in Finder.
    private var enabledBuiltIns: [(MenuAction, String, NSImage)] {
        model.enabledActions.compactMap { action in
            switch action {
            case .openInTerminal where model.resolvedTerminal == nil: return nil
            case .openInEditor where model.resolvedEditor == nil: return nil
            default: return (action, action.menuTitle(), icon(for: action))
            }
        }
    }
}

// MARK: - Row

private struct MenuActionRow<Accessory: View>: View {
    let action: MenuAction
    @Binding var isOn: Bool
    let icon: NSImage
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
            Text(action.settingsTitle)
            Spacer(minLength: 8)
            accessory()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(action.settingsTitle)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview panel

/// A mock of the `右键助手 ▸` submenu, drawn with the same titles, icons and
/// grouping rules as ``FinderSyncExtension``.
private struct MenuPreview: View {
    @EnvironmentObject private var actions: CustomActionsModel
    let builtIn: [(MenuAction, String, NSImage)]
    let custom: [CustomAction]

    private var groups: [(String, [CustomAction])] {
        var order: [String] = []
        var grouped: [String: [CustomAction]] = [:]
        for action in custom {
            if grouped[action.group] == nil { order.append(action.group) }
            grouped[action.group, default: []].append(action)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        if builtIn.isEmpty && custom.isEmpty {
            SurfaceCard {
                Label(Strings.menuPreviewEmpty, systemImage: "eye.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image("StatusItem").renderingMode(.template)
                        .resizable().scaledToFit().frame(width: 14, height: 14)
                    Text(Strings.appName)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider().padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(builtIn, id: \.0) { _, title, icon in
                        row(title: title, image: icon)
                    }
                    if !builtIn.isEmpty && !custom.isEmpty {
                        Divider().padding(.horizontal, 8).padding(.vertical, 3)
                    }
                    ForEach(groups, id: \.0) { group, members in
                        if group.isEmpty {
                            ForEach(members) { action in
                                row(title: action.title.isEmpty ? Strings.Custom.untitled : action.title,
                                    image: actions.image(for: action.icon))
                            }
                        } else {
                            row(title: group, image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil)!,
                                submenu: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .font(.system(size: 13))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Strings.menuPreview)
        }
    }

    private func row(title: String, image: NSImage, submenu: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: image)
                .resizable().scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(.primary)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            if submenu { Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
    }
}
